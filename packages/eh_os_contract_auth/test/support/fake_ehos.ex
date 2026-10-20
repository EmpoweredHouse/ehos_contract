defmodule EhOsContract.Auth.FakeEhos do
  @moduledoc """
  EHOS as sign-in sees it: a function plug handed to `EhOsContract.Auth.SignIn` as
  `plug:`, so no port is opened and the package's own transport
  (`EhOsContract.Auth.SignIn.Http`) — the request, the status, the size, the
  redirect — runs as it does against EHOS, as `EhOsContract.Auth.KeyCase` does for the
  key set.

  The discovery document is the one `Ehos.SignIn.discovery/0` serves on `eh-os`'s
  `main` of 2 October 2026. A test can change it, take EHOS down (`down/2`, `true`
  for everything or `:keys` for the key set only), or have it answer what no EHOS
  does (`answer/2`): `:redirect` to plain http, or `:huge`, a body past the limit.
  The client's key file is written in the shape `eh-os` D-68 fixes.

  Its token endpoint answers a code exchange as `Ehos.SignIn.Token` does on `eh-os`'s
  `main` of 2 October 2026: a credential in EHOS's form for the client's own
  application, carrying `client_id`, an ID token whose `aud` is the `client_id`, and a
  refresh token. A code is one `grant/3` made, and each token request is kept with
  its form (`token_requests/1`), the client's assertion included. A renewal that names
  a `resource` gets a credential for that application, if the grant has it in
  `"applications"`, and `invalid_target` otherwise, consuming nothing, as
  `Ehos.SignIn.Token` refuses a `resource` outside the sign-in's granted set.

  It also exchanges a person's credential and serves the grant routes, as `eh-os`'s
  `docs/grants-api.md` describes them on its pull request EmpoweredHouse/eh-os#754 of
  20 October 2026 (D-112). The exchange takes a credential it signed, unexpired, whose
  `client_id` is the assertion's client, and issues one for the audience `ehos` with
  `act`, for a minute; the routes take only such a credential. A grant registers a new
  email as invited and mails them, and answers `"bound": "before"` for a role bound
  already; a revocation unbinds, or answers `not_found`. A test can have either answer
  otherwise (`exchange_answer/2`, `grants_answer/2`), and reads what the routes were sent
  (`grant_calls/1`).
  """

  @issuer "https://ehos.test"

  @doc """
  An EHOS that is up and serves its own discovery document and one key: `signer:`, a
  private Ed25519 JWK such as `EhOsContract.Auth.KeyCase.key_pair/0`'s, or a new one.
  """
  def start(opts \\ []) do
    jwk = Keyword.get_lazy(opts, :signer, fn -> JOSE.JWK.generate_key({:okp, :Ed25519}) end)

    {:ok, ehos} =
      Agent.start_link(fn ->
        %{
          discovery: discovery(),
          down: false,
          answer: nil,
          signer: jwk,
          requests: [],
          grants: %{},
          token_requests: [],
          # refresh token => %{grant, family, consumed}; families revoked
          refresh: %{},
          revoked: MapSet.new(),
          offset: 0,
          on_refresh: nil,
          refresh_answer: nil,
          exchange_answer: nil,
          # an exchanged credential => the person it names
          exchanged: %{},
          grants_answer: nil,
          grant_calls: [],
          # email => {person id, "invited" | "joined"}; {person id, role} => binding id
          people: %{},
          bindings: %{}
        }
      end)

    ehos
  end

  @doc "What `EhOsContract.Auth.SignIn` takes as `plug:`, for `ehos`."
  def plug(ehos), do: &serve(ehos, &1)

  @doc "Changes the discovery document `ehos` serves."
  def discovery(ehos, fun), do: Agent.update(ehos, &%{&1 | discovery: fun.(&1.discovery)})

  @doc "Takes `ehos` down: `true` for everything, `:keys` for the key set only, `false` up."
  def down(ehos, down), do: Agent.update(ehos, &%{&1 | down: down})

  @doc "Has `ehos` answer the discovery document with `:redirect` or `:huge`, or `nil`."
  def answer(ehos, answer), do: Agent.update(ehos, &%{&1 | answer: answer})

  @doc """
  Makes `code` one the token endpoint exchanges, for a person signed in to `client_id`:
  `claims` replace the ID token's `"sub"`, `"sid"`, `"auth_time"` and `"nonce"`, and
  `"audience"` the credential's `aud` and `"credential_sub"` its `sub`. With `"code_challenge"` (S256) and
  `"redirect_uri"`, the exchange is refused, as EHOS refuses it, unless its
  `code_verifier` and `redirect_uri` match. `"applications"` maps the addresses a renewal
  may name as `resource` to the `aud` of the credential it then gets: the sign-in's
  granted set, where the person holds a role.
  """
  def grant(ehos, code, client_id, claims \\ %{}) do
    grant =
      Map.merge(
        %{
          "sub" => "u-anna",
          "sid" => "sid-" <> Integer.to_string(System.unique_integer([:positive])),
          "auth_time" => System.os_time(:second),
          "audience" => "clinic/test",
          "client_id" => client_id
        },
        Map.new(claims)
      )

    Agent.update(ehos, &put_in(&1, [:grants, code], grant))
  end

  @doc """
  Changes the `"applications"` of every sign-in `ehos` holds a refresh token for, by
  `fun`: a role granted or taken away meanwhile.
  """
  def applications(ehos, fun) do
    Agent.update(ehos, fn state ->
      refresh =
        Map.new(state.refresh, fn {token, record} ->
          {token, update_in(record, [:grant, "applications"], &fun.(&1 || %{}))}
        end)

      %{state | refresh: refresh}
    end)
  end

  @doc """
  Moves `ehos`'s clock `seconds` ahead of the real one, for what it issues from now on.
  """
  def advance(ehos, seconds), do: Agent.update(ehos, &%{&1 | offset: &1.offset + seconds})

  @doc """
  Runs `fun` inside each refresh request before it is answered, in the process the
  request arrived in: a delay, or a look at the database while the client waits.
  """
  def on_refresh(ehos, fun), do: Agent.update(ehos, &%{&1 | on_refresh: fun})

  @doc """
  Has `ehos` answer refresh requests with what EHOS does not answer, or `nil`:
  `:reset` (no response), `{:status, code}` (an error response), or a 200 that cannot be
  used: `:no_id_token`, `:foreign_sub` and `:foreign_sid` in its ID token,
  `:no_refresh_token`, `:expires_in_30`, `:jwt` (a body that is not JSON), `:huge` (past
  the transport's limit), `:foreign_audience` (a credential for another application).
  `:short_exp` is a usable 200 whose credential's `exp` is 100 seconds away though
  `expires_in` says 600; with `:exp_in_20`, 20 seconds away. `:invalid_target` refuses every
  renewal so, with or without a `resource`. None of these rotates the refresh token but the
  200s, which do, as EHOS would before answering.
  """
  def refresh_answer(ehos, answer), do: Agent.update(ehos, &%{&1 | refresh_answer: answer})

  @doc """
  Has `ehos` answer token exchanges with what it would not, or `nil`: `:invalid_grant`,
  `:reset` (no response), `{:status, code}` or `{:status, code, json}`, or `:no_token`, a 200
  without a credential.
  """
  def exchange_answer(ehos, answer), do: Agent.update(ehos, &%{&1 | exchange_answer: answer})

  @doc """
  Has `ehos` answer the grant routes with `{:status, code, json}`, `:reset` (no response),
  `:not_json`, or `nil` for what it decides itself.
  """
  def grants_answer(ehos, answer), do: Agent.update(ehos, &%{&1 | grants_answer: answer})

  @doc "Makes `email` a person of `ehos`, `\"invited\"` or `\"joined\"`, and returns their id."
  def person(ehos, email, person_state) do
    id = Ecto.UUID.generate()
    Agent.update(ehos, &put_in(&1, [:people, email], {id, person_state}))
    id
  end

  @doc "What the grant routes were sent, oldest first: method, path, bearer token and body."
  def grant_calls(ehos), do: Agent.get(ehos, &Enum.reverse(&1.grant_calls))

  @doc "The credentials `ehos` issued by exchange, each with the person it names."
  def exchanged(ehos), do: Agent.get(ehos, & &1.exchanged)

  @doc "Has `ehos` sign with `signer`, a private Ed25519 JWK, from now on, as after a key rotation."
  def rotate_signer(ehos, signer), do: Agent.update(ehos, &%{&1 | signer: signer})

  @doc "The forms of the token requests `ehos` was sent, oldest first."
  def token_requests(ehos), do: Agent.get(ehos, &Enum.reverse(&1.token_requests))

  @doc "The paths `ehos` was asked for, oldest first."
  def requests(ehos), do: Agent.get(ehos, &Enum.reverse(&1.requests))

  @doc "EHOS's discovery document, as served on `main` (`Ehos.SignIn.discovery/0`)."
  def discovery do
    %{
      "issuer" => @issuer,
      "jwks_uri" => @issuer <> "/.well-known/jwks.json",
      "authorization_endpoint" => @issuer <> "/oauth/authorize",
      "token_endpoint" => @issuer <> "/oauth/token",
      "userinfo_endpoint" => @issuer <> "/oauth/userinfo",
      "response_types_supported" => ["code"],
      "response_modes_supported" => ["query"],
      "grant_types_supported" => ["authorization_code", "refresh_token"],
      "subject_types_supported" => ["public"],
      "id_token_signing_alg_values_supported" => ["Ed25519"],
      "token_endpoint_auth_methods_supported" => ["private_key_jwt"],
      "token_endpoint_auth_signing_alg_values_supported" => ["Ed25519", "EdDSA"],
      "scopes_supported" => ["openid"],
      "claims_supported" => ["sub", "iss", "aud", "exp", "iat", "auth_time", "nonce"],
      "code_challenge_methods_supported" => ["S256"],
      "end_session_endpoint" => @issuer <> "/oauth/end_session",
      "authorization_response_iss_parameter_supported" => true,
      "request_parameter_supported" => false,
      "request_uri_parameter_supported" => false,
      "claims_parameter_supported" => false
    }
  end

  @doc """
  Writes a client key file in `dir`, as D-68 says the operator writes it, and returns
  its path and the key. `members` replace or add members, and `drop:` removes some.
  """
  def client_key_file(dir, members \\ %{}, opts \\ []) do
    jwk = JOSE.JWK.generate_key({:okp, :Ed25519})
    {_, map} = JOSE.JWK.to_map(jwk)

    map =
      map
      |> Map.merge(%{"use" => "sig", "alg" => "Ed25519", "kid" => JOSE.JWK.thumbprint(jwk)})
      |> Map.merge(members)
      |> Map.drop(Keyword.get(opts, :drop, []))

    path = Path.join(dir, "client-#{System.unique_integer([:positive])}.json")
    File.write!(path, Jason.encode!(map))
    {path, map}
  end

  defp serve(ehos, conn) do
    state =
      Agent.get_and_update(ehos, fn state ->
        {state, %{state | requests: [conn.request_path | state.requests]}}
      end)

    case {state.down, state.answer, conn.request_path} do
      {true, _answer, _path} ->
        Req.Test.transport_error(conn, :econnrefused)

      {_down, :redirect, "/.well-known/openid-configuration"} ->
        conn
        |> Plug.Conn.put_resp_header("location", "http://elsewhere.test/discovery")
        |> Plug.Conn.send_resp(302, "")

      {_down, :huge, "/.well-known/openid-configuration"} ->
        Req.Test.json(conn, Map.put(state.discovery, "padding", String.duplicate("x", 70_000)))

      {_down, _answer, "/.well-known/openid-configuration"} ->
        Req.Test.json(conn, state.discovery)

      {:keys, _answer, "/.well-known/jwks.json"} ->
        Plug.Conn.send_resp(conn, 503, "")

      {_down, _answer, "/.well-known/jwks.json"} ->
        {_, public} = state.signer |> JOSE.JWK.to_public() |> JOSE.JWK.to_map()
        key = Map.merge(public, %{"kid" => JOSE.JWK.thumbprint(state.signer), "alg" => "Ed25519"})
        Req.Test.json(conn, %{"keys" => [key]})

      {_down, _answer, "/oauth/token"} ->
        token(ehos, state, conn)

      {_down, _answer, "/api/v1/role-bindings/grants" <> _rest} ->
        grants(ehos, state, conn)

      {_down, _answer, _path} ->
        Plug.Conn.send_resp(conn, 404, "")
    end
  end

  defp token(ehos, state, conn) do
    {:ok, body, conn} = Plug.Conn.read_body(conn)
    form = URI.decode_query(body)
    Agent.update(ehos, &%{&1 | token_requests: [form | &1.token_requests]})

    case {form["grant_type"], Map.get(state.grants, form["code"])} do
      {"authorization_code", %{} = grant} ->
        token_for(ehos, state, conn, form, grant)

      {"refresh_token", _grant} ->
        if state.on_refresh, do: state.on_refresh.()
        refreshed(ehos, Agent.get(ehos, & &1), conn, form["refresh_token"], form["resource"])

      {"urn:ietf:params:oauth:grant-type:token-exchange", _grant} ->
        exchange(ehos, state, conn, form)

      _other ->
        invalid_grant(conn)
    end
  end

  # `Ehos.SignIn.Token`'s renewal: strict rotation, a token presented twice revokes its family
  # (the revocation kept though the request fails), and an ID token as eh-os-contract#80 lists it.
  # A `resource` outside the granted set is decided before anything is consumed.
  defp refreshed(ehos, state, conn, presented, resource) do
    # Looked up and marked in one step, so two presentations at once cannot both pass.
    {record, seen} =
      Agent.get_and_update(ehos, fn state ->
        case Map.get(state.refresh, presented) do
          %{consumed: false} = record when not is_nil(resource) ->
            if Map.has_key?(Map.get(record.grant, "applications", %{}), resource),
              do: consume(state, presented, record),
              else: {{record, :invalid_target}, state}

          %{consumed: false} = record ->
            consume(state, presented, record)

          %{} = record ->
            {{record, if(record.consumed, do: :consumed, else: :fresh)}, state}

          nil ->
            {{nil, :unknown}, state}
        end
      end)

    cond do
      state.refresh_answer == :reset ->
        Req.Test.transport_error(conn, :closed)

      match?({:status, _}, state.refresh_answer) ->
        {:status, status} = state.refresh_answer
        Plug.Conn.send_resp(conn, status, "")

      seen == :unknown or MapSet.member?(state.revoked, record.family) ->
        invalid_grant(conn)

      seen == :consumed ->
        Agent.update(ehos, &%{&1 | revoked: MapSet.put(&1.revoked, record.family)})
        invalid_grant(conn)

      seen == :invalid_target or state.refresh_answer == :invalid_target ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(400, Jason.encode!(%{"error" => "invalid_target"}))

      true ->
        grant =
          case {state.refresh_answer, resource} do
            {:short_exp, _} ->
              Map.put(record.grant, "credential_lifetime", 100)

            {:exp_in_20, _} ->
              Map.put(record.grant, "credential_lifetime", 20)

            {:foreign_audience, _} ->
              Map.put(record.grant, "audience", "ledger/test")

            {_other, nil} ->
              record.grant

            {_other, resource} ->
              %{record.grant | "audience" => record.grant["applications"][resource]}
          end

        body = issue(ehos, state, grant, record.family, renewal: true, keeps: record.grant)
        answer(conn, state, record.grant, body)
    end
  end

  # An answer of no response or an error status consumes nothing, as at EHOS.
  defp consume(state, presented, record) do
    if state.refresh_answer in [:reset, :invalid_target] or is_tuple(state.refresh_answer),
      do: {{record, :fresh}, state},
      else: {{record, :fresh}, put_in(state, [:refresh, presented, :consumed], true)}
  end

  defp answer(conn, state, grant, body) do
    case state.refresh_answer do
      :no_id_token ->
        Req.Test.json(conn, Map.delete(body, "id_token"))

      :foreign_sub ->
        Req.Test.json(conn, %{
          body
          | "id_token" => id_token(state, %{grant | "sub" => "u-bartek"}, true)
        })

      :foreign_sid ->
        Req.Test.json(conn, %{
          body
          | "id_token" => id_token(state, %{grant | "sid" => "sid-other"}, true)
        })

      :no_refresh_token ->
        Req.Test.json(conn, Map.delete(body, "refresh_token"))

      :expires_in_30 ->
        Req.Test.json(conn, %{body | "expires_in" => 30})

      :jwt ->
        conn
        |> Plug.Conn.put_resp_content_type("application/jwt")
        |> Plug.Conn.send_resp(200, body["id_token"])

      :huge ->
        Req.Test.json(conn, Map.put(body, "padding", String.duplicate("x", 70_000)))

      _usable ->
        Req.Test.json(conn, body)
    end
  end

  defp token_for(ehos, state, conn, form, grant) do
    verifier = form["code_verifier"] || ""
    challenge = Base.url_encode64(:crypto.hash(:sha256, verifier), padding: false)

    cond do
      Map.has_key?(grant, "code_challenge") and grant["code_challenge"] != challenge ->
        invalid_grant(conn)

      Map.has_key?(grant, "redirect_uri") and grant["redirect_uri"] != form["redirect_uri"] ->
        invalid_grant(conn)

      true ->
        Agent.update(ehos, &%{&1 | grants: Map.delete(&1.grants, form["code"])})
        family = Integer.to_string(System.unique_integer([:positive]))
        Req.Test.json(conn, issue(ehos, state, grant, family, renewal: false))
    end
  end

  # `docs/grants-api.md`, "The exchange": the person's credential the client's sign-in got, for
  # one EHOS takes on its grant routes, a minute at most. The assertion is checked for its shape
  # and its client, not its signature: `eh-os` holds the client's public key, this fake does not.
  defp exchange(ehos, state, conn, form) do
    client = assertion_client(form)
    subject = subject(state, form["subject_token"])

    cond do
      state.exchange_answer == :reset ->
        Req.Test.transport_error(conn, :closed)

      match?({:status, _}, state.exchange_answer) ->
        {:status, status} = state.exchange_answer
        Plug.Conn.send_resp(conn, status, "")

      match?({:status, _, _}, state.exchange_answer) ->
        {:status, status, json} = state.exchange_answer
        conn |> Plug.Conn.put_status(status) |> Req.Test.json(json)

      is_nil(client) or form["audience"] != "ehos" or
        form["subject_token_type"] != "urn:ietf:params:oauth:token-type:access_token" or
          Enum.any?(~w(scope resource actor_token), &Map.has_key?(form, &1)) ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(400, Jason.encode!(%{"error" => "invalid_request"}))

      state.exchange_answer == :invalid_grant or is_nil(subject) or
          subject["client_id"] != client ->
        invalid_grant(conn)

      state.exchange_answer == :no_token ->
        Req.Test.json(conn, %{"token_type" => "Bearer", "expires_in" => 60})

      true ->
        now = System.os_time(:second) + state.offset

        credential =
          sign(state.signer, %{
            "iss" => @issuer,
            "sub" => subject["sub"],
            "aud" => "ehos",
            "act" => %{"sub" => "workload-" <> client},
            "client_id" => client,
            "cap" => [],
            "iat" => now,
            "exp" => min(now + 60, subject["exp"]),
            "jti" => Ecto.UUID.generate()
          })

        Agent.update(ehos, &put_in(&1, [:exchanged, credential], subject["sub"]))

        Req.Test.json(conn, %{
          "access_token" => credential,
          "issued_token_type" => "urn:ietf:params:oauth:token-type:access_token",
          "token_type" => "Bearer",
          "expires_in" => 60
        })
    end
  end

  defp assertion_client(%{
         "client_assertion_type" => "urn:ietf:params:oauth:client-assertion-type:jwt-bearer",
         "client_assertion" => assertion
       }) do
    case JOSE.JWT.peek_payload(assertion).fields do
      %{"iss" => client, "sub" => client} -> client
      _other -> nil
    end
  rescue
    _not_a_jwt -> nil
  end

  defp assertion_client(_form), do: nil

  # A credential this EHOS signed and that has not expired, or nil.
  defp subject(state, token) when is_binary(token) do
    public = JOSE.JWK.to_public(state.signer)

    case JOSE.JWT.verify_strict(public, ["Ed25519", "EdDSA"], token) do
      {true, %JOSE.JWT{fields: %{"exp" => exp} = claims}, _jws} ->
        if exp > System.os_time(:second) + state.offset, do: claims

      _refused ->
        nil
    end
  rescue
    _not_a_jwt -> nil
  end

  defp subject(_state, _token), do: nil

  # `docs/grants-api.md`, "Granting a role" and "Revoking a role", for a credential it exchanged.
  defp grants(ehos, state, conn) do
    {:ok, body, conn} = Plug.Conn.read_body(conn)

    bearer =
      case Plug.Conn.get_req_header(conn, "authorization") do
        ["Bearer " <> token] -> token
        _other -> nil
      end

    call = %{
      method: conn.method,
      path: conn.request_path,
      bearer: bearer,
      body: if(body == "", do: nil, else: Jason.decode!(body))
    }

    Agent.update(ehos, &%{&1 | grant_calls: [call | &1.grant_calls]})

    case {state.grants_answer, Map.has_key?(state.exchanged, bearer)} do
      {:reset, _exchanged} ->
        Req.Test.transport_error(conn, :closed)

      {:not_json, _exchanged} ->
        Plug.Conn.send_resp(conn, 200, "<html></html>")

      {{:status, status, json}, _exchanged} ->
        conn |> Plug.Conn.put_status(status) |> Req.Test.json(json)

      {nil, false} ->
        refused(conn, 401, "wrong_audience")

      {nil, true} ->
        decide(ehos, conn, call)
    end
  end

  defp decide(ehos, conn, %{method: "POST", body: %{"email" => email, "role" => role}}) do
    {status, json} =
      Agent.get_and_update(ehos, fn state ->
        {id, person_state, state} =
          case Map.fetch(state.people, email) do
            {:ok, {id, person_state}} ->
              {id, person_state, state}

            :error ->
              id = Ecto.UUID.generate()
              {id, "invited", put_in(state, [:people, email], {id, "invited"})}
          end

        {bound, binding, state} =
          case Map.fetch(state.bindings, {id, role}) do
            {:ok, binding} ->
              {"before", binding, state}

            :error ->
              binding = Ecto.UUID.generate()
              {"now", binding, put_in(state, [:bindings, {id, role}], binding)}
          end

        json = %{
          "person" => %{"id" => id, "email" => email, "state" => person_state},
          "role_binding" => %{"id" => binding, "role" => role, "bound" => bound},
          "delivery" => if(person_state == "invited", do: "mailed", else: "none")
        }

        {{if(bound == "now", do: 201, else: 200), json}, state}
      end)

    conn |> Plug.Conn.put_status(status) |> Req.Test.json(json)
  end

  defp decide(ehos, conn, %{method: "DELETE", path: path}) do
    ["", "api", "v1", "role-bindings", "grants", person, role] = String.split(path, "/")
    role = URI.decode(role)

    case Agent.get_and_update(ehos, &(Map.pop(&1.bindings, {person, role}) |> keep(&1))) do
      nil -> refused(conn, 404, "not_found")
      binding -> Req.Test.json(conn, %{"role_binding" => %{"id" => binding, "role" => role}})
    end
  end

  defp keep({binding, bindings}, state), do: {binding, %{state | bindings: bindings}}

  defp refused(conn, status, error) do
    conn
    |> Plug.Conn.put_status(status)
    |> Req.Test.json(%{"error" => error, "message" => "Refused."})
  end

  defp invalid_grant(conn) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(400, Jason.encode!(%{"error" => "invalid_grant"}))
  end

  # `Ehos.SignIn.Token.response/3`: the credential and the ID token live ten minutes, and the
  # refresh token is a new member of the sign-in's family, which `keeps:` the sign-in's grant
  # whatever this one credential was issued for.
  defp issue(ehos, state, grant, family, opts) do
    now = System.os_time(:second) + state.offset
    refresh_token = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
    keeps = Keyword.get(opts, :keeps, grant)

    Agent.update(ehos, fn state ->
      put_in(state, [:refresh, refresh_token], %{grant: keeps, family: family, consumed: false})
    end)

    credential =
      sign(state.signer, %{
        "iss" => @issuer,
        "sub" => Map.get(grant, "credential_sub", grant["sub"]),
        "aud" => grant["audience"],
        "iat" => now,
        "exp" => now + Map.get(grant, "credential_lifetime", 600),
        "jti" => Ecto.UUID.generate(),
        "cap" => [],
        "client_id" => grant["client_id"]
      })

    %{
      "access_token" => credential,
      "token_type" => "Bearer",
      "expires_in" => 600,
      "refresh_token" => refresh_token,
      "scope" => "openid",
      "id_token" => id_token(state, grant, Keyword.fetch!(opts, :renewal))
    }
  end

  # At a renewal, eh-os-contract#80: `iss`, `sub` and `aud` the code exchange's, `auth_time` and
  # `sid` the sign-in's, a new `iat`, 600 s, no `nonce` and no `at_hash`.
  defp id_token(state, grant, renewal) do
    now = System.os_time(:second) + state.offset

    claims = %{
      "iss" => @issuer,
      "sub" => grant["sub"],
      "aud" => grant["client_id"],
      "iat" => now,
      "exp" => now + 600,
      "auth_time" => grant["auth_time"],
      "sid" => grant["sid"]
    }

    sign(
      state.signer,
      if(renewal, do: claims, else: Map.merge(claims, Map.take(grant, ["nonce"])))
    )
  end

  defp sign(signer, claims) do
    header = %{"kid" => JOSE.JWK.thumbprint(signer)}

    {:ok, token, _claims} =
      Joken.encode_and_sign(claims, Joken.Signer.create("Ed25519", signer, header))

    token
  end
end

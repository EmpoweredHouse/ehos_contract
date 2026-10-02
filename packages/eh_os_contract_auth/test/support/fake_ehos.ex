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
  its form (`token_requests/1`), the client's assertion included.
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
          refresh_answer: nil
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
  `code_verifier` and `redirect_uri` match.
  """
  def grant(ehos, code, client_id, claims \\ %{}) do
    grant =
      Map.merge(
        %{
          "sub" => "u-anna",
          "sid" => "sid-" <> Integer.to_string(System.unique_integer([:positive])),
          "auth_time" => System.os_time(:second),
          "audience" => "rehmed/test",
          "client_id" => client_id
        },
        Map.new(claims)
      )

    Agent.update(ehos, &put_in(&1, [:grants, code], grant))
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
  `:reset` (no response), `{:status, code}` (an error response), or a 200 that `oidcc`
  refuses, `:no_id_token` or `:foreign_sub`. None of these rotates the refresh token
  but the 200s, which do, as EHOS would before answering.
  """
  def refresh_answer(ehos, answer), do: Agent.update(ehos, &%{&1 | refresh_answer: answer})

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
        refreshed(ehos, Agent.get(ehos, & &1), conn, form["refresh_token"])

      _other ->
        invalid_grant(conn)
    end
  end

  # `Ehos.SignIn.Token`'s renewal: strict rotation, a token presented twice revokes its family
  # (the revocation kept though the request fails), and an ID token as eh-os-contract#80 lists it.
  defp refreshed(ehos, state, conn, presented) do
    record = Map.get(state.refresh, presented)

    cond do
      state.refresh_answer == :reset ->
        Req.Test.transport_error(conn, :closed)

      match?({:status, _}, state.refresh_answer) ->
        {:status, status} = state.refresh_answer
        Plug.Conn.send_resp(conn, status, "")

      record == nil or MapSet.member?(state.revoked, record.family) ->
        invalid_grant(conn)

      record.consumed ->
        Agent.update(ehos, &%{&1 | revoked: MapSet.put(&1.revoked, record.family)})
        invalid_grant(conn)

      true ->
        body = issue(ehos, state, record.grant, record.family, renewal: true)
        Agent.update(ehos, &put_in(&1, [:refresh, presented, :consumed], true))

        body =
          case state.refresh_answer do
            :no_id_token ->
              Map.delete(body, "id_token")

            :foreign_sub ->
              Map.put(
                body,
                "id_token",
                id_token(state, %{record.grant | "sub" => "u-bartek"}, true)
              )

            nil ->
              body
          end

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

  defp invalid_grant(conn) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(400, Jason.encode!(%{"error" => "invalid_grant"}))
  end

  # `Ehos.SignIn.Token.response/3`: the credential and the ID token live ten minutes, and the
  # refresh token is a new member of the sign-in's family.
  defp issue(ehos, state, grant, family, renewal: renewal) do
    now = System.os_time(:second) + state.offset
    refresh_token = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

    Agent.update(ehos, fn state ->
      put_in(state, [:refresh, refresh_token], %{grant: grant, family: family, consumed: false})
    end)

    credential =
      sign(state.signer, %{
        "iss" => @issuer,
        "sub" => Map.get(grant, "credential_sub", grant["sub"]),
        "aud" => grant["audience"],
        "iat" => now,
        "exp" => now + 600,
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
      "id_token" => id_token(state, grant, renewal)
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

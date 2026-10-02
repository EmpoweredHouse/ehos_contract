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
  """

  @issuer "https://ehos.test"

  @doc "An EHOS that is up and serves its own discovery document and one key."
  def start do
    jwk = JOSE.JWK.generate_key({:okp, :Ed25519})

    {:ok, ehos} =
      Agent.start_link(fn ->
        %{discovery: discovery(), down: false, answer: nil, signer: jwk, requests: []}
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

      {_down, _answer, _path} ->
        Plug.Conn.send_resp(conn, 404, "")
    end
  end
end

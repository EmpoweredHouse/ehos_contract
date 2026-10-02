defmodule EhOsContract.Auth.FakeEhos do
  @moduledoc """
  EHOS as `oidcc` sees it, played through `oidcc`'s HTTP adapter, so no port is
  opened and `oidcc`'s own code — the request, the content type, the parsing — runs as
  it does against EHOS.

  The discovery document is the one `Ehos.SignIn.discovery/0` serves on `eh-os`'s
  `main` of 2 October 2026, and a test can change it or take EHOS down. The client's
  key file is written in the shape `eh-os` D-68 fixes.
  """

  @behaviour :oidcc_http_adapter

  @issuer "https://ehos.test"

  @doc "An EHOS that is up and serves its own discovery document and one key."
  def start do
    jwk = JOSE.JWK.generate_key({:okp, :Ed25519})
    {:ok, ehos} = Agent.start_link(fn -> %{discovery: discovery(), down: false, signer: jwk} end)
    ehos
  end

  @doc "What `oidcc` takes as `request_opts.http_adapter`, for `ehos`."
  def adapter(ehos), do: {__MODULE__, %{ehos: ehos}}

  @doc "Changes the discovery document `ehos` serves."
  def discovery(ehos, fun), do: Agent.update(ehos, &%{&1 | discovery: fun.(&1.discovery)})

  @doc "Takes `ehos` down (`true`) or brings it back."
  def down(ehos, down?), do: Agent.update(ehos, &%{&1 | down: down?})

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

  @impl :oidcc_http_adapter
  def request(:get, {url, _headers}, _http_options, _request_options, %{ehos: ehos}) do
    state = Agent.get(ehos, & &1)

    case {state.down, URI.parse(to_string(url)).path} do
      {true, _path} ->
        {:error, :econnrefused}

      {false, "/.well-known/openid-configuration"} ->
        json(state.discovery)

      {false, "/.well-known/jwks.json"} ->
        {_, public} = state.signer |> JOSE.JWK.to_public() |> JOSE.JWK.to_map()
        key = Map.merge(public, %{"kid" => JOSE.JWK.thumbprint(state.signer), "alg" => "Ed25519"})
        json(%{"keys" => [key]})

      {false, _other} ->
        {:ok, {{~c"HTTP/1.1", 404, ~c"Not Found"}, [], ""}}
    end
  end

  defp json(body) do
    {:ok,
     {{~c"HTTP/1.1", 200, ~c"OK"}, [{~c"content-type", ~c"application/json"}],
      Jason.encode!(body)}}
  end
end

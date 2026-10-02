defmodule EhOsContract.Auth.SignInTest do
  @moduledoc """
  EB1 (#78): the sign-in child — what it refuses at boot, the client key in the shape
  `eh-os` D-68 fixes, and how it keeps EHOS's discovery document and keys: fetched
  over a transport that follows no redirect and reads a bounded body, retried while
  EHOS is down, and checked before any sign-in (S6 in docs/adr/browser-session.md).
  The sign-in itself is EB2's.

  Not async: the tests change `config :eh_os_contract_auth`.
  """

  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias EhOsContract.Auth.{FakeEhos, SignIn}

  @moduletag :tmp_dir

  setup %{tmp_dir: dir} do
    previous = Application.get_all_env(:eh_os_contract_auth)
    on_exit(fn -> restore(previous) end)

    {key_file, key} = FakeEhos.client_key_file(dir)

    Application.put_env(:eh_os_contract_auth, :sign_in,
      client_id: "rehmed/test",
      client_key_file: key_file,
      address: "https://rehmed.test",
      secret_key_base: String.duplicate("s", 64),
      applications: %{"ledger" => "https://ledger.test.ehos.test"}
    )

    %{ehos: FakeEhos.start(), key: key, dir: dir}
  end

  describe "at boot" do
    test "a configuration as EHOS gives it starts, and derives the client's addresses",
         %{ehos: ehos, key: key} do
      name = start!(ehos)
      config = SignIn.config(name)

      assert config.client_id == "rehmed/test"
      assert config.issuer == "https://ehos.test"
      assert config.redirect_uri == "https://rehmed.test/auth/ehos/callback"
      # Exactly the string EHOS compares (eh-os D-68).
      assert config.post_logout_redirect_uri == "https://rehmed.test/"
      assert config.applications == %{"ledger" => "https://ledger.test.ehos.test"}

      # Every call oidcc makes goes through the package's transport, with a deadline.
      assert %{timeout: 10_000, http_adapter: {SignIn.Http, _http}} = config.request_opts

      # Handed to oidcc as it is: kid and use kept, for its client assertions.
      assert %JOSE.JWK{fields: %{"kid" => kid, "use" => "sig"}} = config.client_key
      assert kid == key["kid"]

      # Nothing secret in what an inspection prints.
      refute inspect(config) =~ key["d"]
      refute inspect(config) =~ String.duplicate("s", 64)
    end

    test "the client's sign_in: is required, a keyword list, and takes only what it names" do
      sign_in = Application.fetch_env!(:eh_os_contract_auth, :sign_in)

      Application.delete_env(:eh_os_contract_auth, :sign_in)

      assert_raise ArgumentError, ~r/sign_in: \[\.\.\.\] is missing/, fn ->
        SignIn.child_spec([])
      end

      # A map is refused without being printed: it holds the secret.
      Application.put_env(:eh_os_contract_auth, :sign_in, Map.new(sign_in))

      error =
        assert_raise ArgumentError, ~r/must be a keyword list/, fn -> SignIn.child_spec([]) end

      refute error.message =~ String.duplicate("s", 64)

      Application.put_env(:eh_os_contract_auth, :sign_in, sign_in)
      put_sign_in(redirect_uri: "https://rehmed.test/elsewhere")
      assert_raise ArgumentError, ~r/not \[:redirect_uri\]/, fn -> SignIn.child_spec([]) end
    end

    test "a client_id that is not a non-empty string is refused" do
      put_sign_in(client_id: "")
      assert_raise ArgumentError, ~r/client_id must be/, fn -> SignIn.child_spec([]) end
    end

    test "an address that is not exactly https://<host> is refused (eh-os D-68)" do
      for address <- [
            "https://rehmed.test/",
            "https://rehmed.test/pages",
            "https://rehmed.test?x=1",
            "https://rehmed.test:8443",
            "https://Rehmed.test",
            "http://rehmed.test",
            "rehmed.test",
            nil
          ] do
        put_sign_in(address: address)

        assert_raise ArgumentError, ~r/address must be https:\/\/<host>/, fn ->
          SignIn.child_spec([])
        end
      end
    end

    test "an application's address with a path or a trailing slash is refused (eh-os D-68)" do
      put_sign_in(applications: %{"ledger" => "https://ledger.test.ehos.test/"})

      assert_raise ArgumentError, ~r/address of "ledger" in applications must be/, fn ->
        SignIn.child_spec([])
      end

      put_sign_in(applications: [{"ledger", "https://ledger.test.ehos.test"}])
      assert_raise ArgumentError, ~r/applications must map/, fn -> SignIn.child_spec([]) end
    end

    test "a secret_key_base shorter than 64 bytes is refused" do
      put_sign_in(secret_key_base: String.duplicate("s", 63))
      assert_raise ArgumentError, ~r/at least 64 bytes/, fn -> SignIn.child_spec([]) end
    end

    test "an issuer that is not https://<host>, localhost included, is refused at boot" do
      for issuer <- [
            "http://ehos.test",
            "http://localhost:4000",
            "https://ehos.test?tenant=1",
            "https://ehos.test#x",
            "https://user:pass@ehos.test"
          ] do
        Application.put_env(:eh_os_contract_auth, :issuer, issuer)
        assert_raise ArgumentError, ~r/is not https:\/\/<host>/, fn -> SignIn.child_spec([]) end
      end

      Application.put_env(:eh_os_contract_auth, :issuer, ~c"https://ehos.test")
      assert_raise ArgumentError, ~r/issuer: must be a string/, fn -> SignIn.child_spec([]) end
    end

    test "a plug in place of EHOS is taken only where test keys may be pinned", %{ehos: ehos} do
      Application.put_env(:eh_os_contract_auth, :pin_keys, false)

      assert_raise ArgumentError, ~r/plug: only in a test/, fn ->
        SignIn.child_spec(plug: FakeEhos.plug(ehos))
      end
    end

    test "a name that is not an atom is refused" do
      assert_raise ArgumentError, ~r/name: as an atom/, fn ->
        SignIn.child_spec(name: {:global, :sign_in})
      end
    end

    test "the authority given is handed to every connection to EHOS", %{ehos: ehos} do
      {SignIn.Http, http} = SignIn.config(start!(ehos)).request_opts.http_adapter
      refute Map.has_key?(http, :cacertfile)

      {SignIn.Http, http} =
        SignIn.config(start!(ehos, cacertfile: "/etc/ehos/ca.pem")).request_opts.http_adapter

      assert http.cacertfile == "/etc/ehos/ca.pem"
    end
  end

  describe "the client key file (eh-os D-68)" do
    test "a PEM is refused, and so is a file that is not one JSON object", %{dir: dir} do
      pem = Path.join(dir, "client.pem")

      File.write!(
        pem,
        "-----BEGIN PRIVATE KEY-----\nMC4CAQAwBQYDK2VwBCIEIA==\n-----END PRIVATE KEY-----\n"
      )

      put_sign_in(client_key_file: pem)
      assert_raise ArgumentError, ~r/is a PEM/, fn -> SignIn.child_spec([]) end

      list = Path.join(dir, "keys.json")
      File.write!(list, "[]")
      put_sign_in(client_key_file: list)
      assert_raise ArgumentError, ~r/is not a JSON object/, fn -> SignIn.child_spec([]) end

      put_sign_in(client_key_file: Path.join(dir, "absent.json"))
      assert_raise ArgumentError, ~r/cannot be read/, fn -> SignIn.child_spec([]) end
    end

    test "a JWK without exactly D-68's members is refused", %{dir: dir} do
      for {members, opts} <- [
            {%{}, drop: ["use"]},
            {%{}, drop: ["kid"]},
            {%{}, drop: ["d"]},
            {%{"key_ops" => ["sign"]}, []}
          ] do
        {path, _key} = FakeEhos.client_key_file(dir, members, opts)
        put_sign_in(client_key_file: path)

        assert_raise ArgumentError, ~r/must have exactly the members/, fn ->
          SignIn.child_spec([])
        end
      end
    end

    test "a JWK whose fixed members say otherwise is refused, each by name", %{dir: dir} do
      for {member, value} <- [
            {"use", "enc"},
            {"alg", "EdDSA"},
            {"crv", "Ed448"},
            {"kty", "EC"}
          ] do
        {path, _key} = FakeEhos.client_key_file(dir, %{member => value})
        put_sign_in(client_key_file: path)

        assert_raise ArgumentError, ~r/has #{member} "#{value}"/, fn -> SignIn.child_spec([]) end
      end
    end

    test "a kid that is not the public key's thumbprint is refused", %{dir: dir} do
      {path, _key} = FakeEhos.client_key_file(dir, %{"kid" => "client-1"})
      put_sign_in(client_key_file: path)

      assert_raise ArgumentError, ~r/kid that is not the RFC 7638 thumbprint/, fn ->
        SignIn.child_spec([])
      end
    end

    test "an x that is not d's public half is refused, and d is never printed", %{dir: dir} do
      {_other, other} = FakeEhos.client_key_file(dir)
      {path, key} = FakeEhos.client_key_file(dir, %{"x" => other["x"]})
      put_sign_in(client_key_file: path)

      error =
        assert_raise ArgumentError, ~r/not the public half of its d/, fn ->
          SignIn.child_spec([])
        end

      refute error.message =~ key["d"]
    end
  end

  describe "EHOS's discovery document and keys" do
    test "EHOS's own document and keys can be signed in with", %{ehos: ehos} do
      name = start!(ehos)

      assert {:ok, %Oidcc.ProviderConfiguration{issuer: "https://ehos.test"}} =
               SignIn.provider(name)

      assert FakeEhos.requests(ehos) == [
               "/.well-known/openid-configuration",
               "/.well-known/jwks.json"
             ]
    end

    test "while EHOS is down the process runs, and retries after one second, doubling",
         %{ehos: ehos} do
      FakeEhos.down(ehos, true)
      name = start!(ehos)

      assert SignIn.provider(name) == {:error, :ehos_unavailable}
      # The first retry is a second away, and the one after it two.
      assert %{retry_in: 2_000, timer: timer} = :sys.get_state(name)
      assert Process.read_timer(timer) in 1..1_000

      FakeEhos.down(ehos, false)
      # The retry the timer would send.
      send(Process.whereis(name), :fetch)
      :sys.get_state(name)
      assert {:ok, _configuration} = SignIn.provider(name)
      assert %{retry_in: 1_000} = :sys.get_state(name)
    end

    test "a document without its keys is not held, and both are fetched again",
         %{ehos: ehos} do
      FakeEhos.down(ehos, :keys)
      name = start!(ehos)

      # The document alone signs nobody in: its ID tokens could not be checked.
      assert SignIn.provider(name) == {:error, :ehos_unavailable}

      FakeEhos.down(ehos, false)
      assert SignIn.refresh(name) == :ok
      assert {:ok, _configuration} = SignIn.provider(name)
    end

    test "a failed refetch keeps what is held", %{ehos: ehos} do
      name = start!(ehos)
      FakeEhos.down(ehos, true)

      assert {:error, _reason} = SignIn.refresh(name)
      assert {:ok, _configuration} = SignIn.provider(name)
    end

    test "a document that changes is read as it now is", %{ehos: ehos} do
      name = start!(ehos)

      for path <- ["/oauth/end_session/v2", "/oauth/end_session/v3"] do
        FakeEhos.discovery(
          ehos,
          &Map.put(&1, "end_session_endpoint", "https://ehos.test" <> path)
        )

        assert SignIn.refresh(name) == :ok

        assert {:ok, configuration} = SignIn.provider(name)
        assert configuration.end_session_endpoint == "https://ehos.test" <> path
      end
    end

    test "a redirect is not followed, and the document it names is never asked for",
         %{ehos: ehos} do
      FakeEhos.answer(ehos, :redirect)
      name = start!(ehos)

      assert SignIn.provider(name) == {:error, :ehos_unavailable}
      assert SignIn.refresh(name) == {:error, {:status, 302}}
      refute "/discovery" in FakeEhos.requests(ehos)
    end

    test "a document past 64 KiB is refused", %{ehos: ehos} do
      FakeEhos.answer(ehos, :huge)
      name = start!(ehos)

      assert SignIn.refresh(name) == {:error, :response_too_large}
      assert SignIn.provider(name) == {:error, :ehos_unavailable}
    end

    test "a document of another issuer, or with an endpoint over plain http, is not held",
         %{ehos: ehos} do
      FakeEhos.discovery(ehos, &Map.put(&1, "issuer", "https://elsewhere.test"))
      name = start!(ehos)
      assert SignIn.refresh(name) == {:error, {:issuer_mismatch, "https://elsewhere.test"}}
      assert SignIn.provider(name) == {:error, :ehos_unavailable}

      FakeEhos.discovery(ehos, fn _ ->
        Map.merge(FakeEhos.discovery(), %{
          "jwks_uri" => "http://ehos.test/.well-known/jwks.json",
          "token_endpoint" => "http://ehos.test/oauth/token"
        })
      end)

      assert SignIn.refresh(name) == {:error, {:not_https, [:token_endpoint, :jwks_uri]}}
      assert SignIn.provider(name) == {:error, :ehos_unavailable}
    end

    # oidcc's decoder raises `case_clause` on a relative URI where it wants https.
    test "a document oidcc's decoder raises on is refused, and the process lives on",
         %{ehos: ehos} do
      FakeEhos.discovery(ehos, &Map.put(&1, "userinfo_endpoint", "/oauth/userinfo"))
      name = start!(ehos)
      pid = Process.whereis(name)

      assert {:error, {:invalid_document, _reason}} = SignIn.refresh(name)
      assert Process.alive?(pid)
      assert SignIn.provider(name) == {:error, :ehos_unavailable}
    end

    test "a document without what oidcc would otherwise do without is refused, each named",
         %{ehos: ehos} do
      for {change, reason} <- [
            {&Map.delete(&1, "authorization_response_iss_parameter_supported"),
             :no_iss_parameter},
            {&Map.put(&1, "authorization_response_iss_parameter_supported", false),
             :no_iss_parameter},
            {&Map.delete(&1, "code_challenge_methods_supported"), :no_s256},
            {&Map.put(&1, "code_challenge_methods_supported", ["plain"]), :no_s256},
            {&Map.put(&1, "id_token_signing_alg_values_supported", ["EdDSA"]),
             :no_ed25519_id_token},
            {&Map.put(&1, "id_token_signing_alg_values_supported", ["Ed25519", "HS256"]),
             :symmetric_id_token_alg},
            {&Map.put(&1, "id_token_signing_alg_values_supported", ["Ed25519", "none"]),
             :symmetric_id_token_alg},
            {&Map.put(&1, "token_endpoint_auth_methods_supported", ["client_secret_basic"]),
             :no_private_key_jwt},
            {&Map.put(&1, "token_endpoint_auth_signing_alg_values_supported", ["RS256"]),
             :no_private_key_jwt}
          ] do
        FakeEhos.discovery(ehos, fn _ -> change.(FakeEhos.discovery()) end)
        name = start!(ehos)

        assert SignIn.provider(name) == {:error, {:unsupported_provider, [reason]}}
      end
    end

    test "a refused document is logged once, not on every refetch", %{ehos: ehos} do
      FakeEhos.discovery(ehos, &Map.delete(&1, "code_challenge_methods_supported"))

      log =
        capture_log(fn ->
          name = start!(ehos)
          :ok = SignIn.refresh(name)
          :ok = SignIn.refresh(name)
        end)

      assert length(String.split(log, "refuses to sign anyone in")) == 2
    end

    test "a child that has stopped, or never started, holds nothing", %{ehos: ehos} do
      name = start!(ehos)
      assert {:ok, _configuration} = SignIn.provider(name)
      :ok = stop_supervised(name)

      assert SignIn.provider(name) == {:error, :ehos_unavailable}
      assert_raise ArgumentError, ~r/is not started/, fn -> SignIn.config(name) end
      assert SignIn.refresh(name) == {:error, :not_running}

      assert SignIn.provider(:sign_in_never_started) == {:error, :ehos_unavailable}
    end
  end

  describe "the client context (EB2a)" do
    # S6, as amended at EB1's review: a fixed secret would be an `oct` key anyone knows for
    # any `HS*` algorithm a document named.
    test "the client secret is random, made at each start, and never inspected", %{ehos: ehos} do
      first = SignIn.config(start!(ehos))
      second = SignIn.config(start!(ehos))

      assert byte_size(first.client_secret) >= 43
      refute first.client_secret == second.client_secret
      refute inspect(first) =~ first.client_secret
      refute inspect(first) =~ Base.encode64(first.cipher_key)
    end

    test "is built from what is held, with the client's own key", %{ehos: ehos, key: key} do
      name = start!(ehos)

      assert {:ok, %Oidcc.ClientContext{} = context} = SignIn.client_context(name)
      assert context.client_id == "rehmed/test"
      assert context.client_secret == SignIn.config(name).client_secret
      assert %JOSE.JWK{fields: %{"kid" => kid}} = context.client_jwks
      assert kid == key["kid"]
      assert context.provider_configuration.issuer == "https://ehos.test"
    end

    test "is unavailable as the provider is", %{ehos: ehos} do
      FakeEhos.discovery(ehos, &Map.delete(&1, "code_challenge_methods_supported"))
      name = start!(ehos)
      assert SignIn.client_context(name) == {:error, {:unsupported_provider, [:no_s256]}}

      :ok = stop_supervised(name)
      assert SignIn.client_context(name) == {:error, :ehos_unavailable}
    end

    # eh-os D-68: EHOS checks an assertion only against the key its `kid` names.
    test "a code exchange authenticates the client by its key alone, the assertion naming its kid",
         %{ehos: ehos, key: key} do
      name = start!(ehos)
      config = SignIn.config(name)
      FakeEhos.grant(ehos, "code-1", "rehmed/test", %{"nonce" => "n-1"})
      {:ok, context} = SignIn.client_context(name)

      assert {:ok, %Oidcc.Token{id: %Oidcc.Token.Id{claims: claims}}} =
               Oidcc.Token.retrieve("code-1", context, %{
                 redirect_uri: config.redirect_uri,
                 nonce: "n-1",
                 preferred_auth_methods: [:private_key_jwt],
                 request_opts: config.request_opts
               })

      assert %{"sub" => "u-anna", "aud" => "rehmed/test"} = claims

      assert [form] = FakeEhos.token_requests(ehos)

      assert form["client_assertion_type"] ==
               "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"

      refute Map.has_key?(form, "client_secret")

      assertion = form["client_assertion"]
      header = assertion |> JOSE.JWS.peek_protected() |> Jason.decode!()
      assert header["kid"] == key["kid"]
      assert header["alg"] in ["Ed25519", "EdDSA"]

      public = key |> JOSE.JWK.from_map() |> JOSE.JWK.to_public()

      assert {true, %JOSE.JWT{fields: fields}, _jws} =
               JOSE.JWT.verify_strict(public, [header["alg"]], assertion)

      assert fields["iss"] == "rehmed/test"
      assert fields["sub"] == "rehmed/test"
    end
  end

  describe "the transport" do
    test "a call over plain http is refused before it is made", %{ehos: ehos} do
      assert SignIn.Http.request(:get, {"http://ehos.test/x", []}, [timeout: 1_000], [], %{
               plug: FakeEhos.plug(ehos)
             }) == {:error, {:not_https, "http://ehos.test/x"}}

      assert FakeEhos.requests(ehos) == []
    end

    test "a call ends at its deadline" do
      slow = fn conn ->
        Process.sleep(500)
        Plug.Conn.send_resp(conn, 200, "")
      end

      assert SignIn.Http.request(:get, {"https://ehos.test/x", []}, [timeout: 50], [], %{
               plug: slow
             }) == {:error, :timeout}
    end
  end

  # Starts the child under a name of its own and waits until its first fetch has run:
  # a call is answered only after `handle_continue/2`.
  defp start!(ehos, opts \\ []) do
    name = :"sign_in_#{System.unique_integer([:positive])}"
    start_supervised!({SignIn, [name: name, plug: FakeEhos.plug(ehos)] ++ opts})
    :sys.get_state(name)
    name
  end

  defp put_sign_in(changes) do
    sign_in = Application.fetch_env!(:eh_os_contract_auth, :sign_in)
    Application.put_env(:eh_os_contract_auth, :sign_in, Keyword.merge(sign_in, changes))
  end

  defp restore(previous) do
    for {key, _value} <- Application.get_all_env(:eh_os_contract_auth),
        not Keyword.has_key?(previous, key),
        do: Application.delete_env(:eh_os_contract_auth, key)

    for {key, value} <- previous, do: Application.put_env(:eh_os_contract_auth, key, value)
  end
end

defmodule EhOsContract.Auth.SignInTest do
  @moduledoc """
  EB1 (#78): the sign-in child — what it refuses at boot, the client key in the shape
  `eh-os` D-68 fixes, and the check of EHOS's discovery document before any sign-in
  (S6 in docs/adr/browser-session.md). The sign-in itself is EB2's.

  Not async: the tests change `config :eh_os_contract_auth`.
  """

  use ExUnit.Case, async: false

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
      assert config.request_opts.timeout == 10_000

      # Handed to oidcc as it is: kid and use kept, for its client assertions.
      assert %JOSE.JWK{fields: %{"kid" => kid, "use" => "sig"}} = config.client_key
      assert kid == key["kid"]

      # Nothing secret in what an inspection prints.
      refute inspect(config) =~ key["d"]
      refute inspect(config) =~ String.duplicate("s", 64)
    end

    test "the client's sign_in: configuration is required, and takes only what it names" do
      sign_in = Application.fetch_env!(:eh_os_contract_auth, :sign_in)
      Application.delete_env(:eh_os_contract_auth, :sign_in)

      assert_raise ArgumentError, ~r/sign_in: \[\.\.\.\] is missing/, fn ->
        SignIn.child_spec([])
      end

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

    test "an issuer that is not https is refused, but for localhost" do
      Application.put_env(:eh_os_contract_auth, :issuer, "http://ehos.test")
      assert_raise ArgumentError, ~r/not https/, fn -> SignIn.child_spec([]) end

      Application.put_env(:eh_os_contract_auth, :issuer, "http://localhost:4000")
      assert %{id: SignIn} = SignIn.child_spec([])
    end

    test "an HTTP adapter in place of EHOS is taken only where test keys may be pinned",
         %{ehos: ehos} do
      Application.put_env(:eh_os_contract_auth, :pin_keys, false)

      assert_raise ArgumentError, ~r/http_adapter: only in a test/, fn ->
        SignIn.child_spec(http_adapter: FakeEhos.adapter(ehos))
      end
    end

    test "EHOS's certificate is checked, against the authority given or the system's",
         %{ehos: ehos} do
      ssl = SignIn.config(start!(ehos)).request_opts.ssl
      assert ssl[:verify] == :verify_peer
      assert ssl[:customize_hostname_check]
      assert ssl[:cacerts] != []

      ssl = SignIn.config(start!(ehos, cacertfile: "/etc/ehos/ca.pem")).request_opts.ssl
      assert ssl[:verify] == :verify_peer
      assert ssl[:customize_hostname_check]
      assert ssl[:cacertfile] == "/etc/ehos/ca.pem"
      refute Keyword.has_key?(ssl, :cacerts)
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

  describe "EHOS's discovery document (S6)" do
    test "EHOS's own document can be signed in with", %{ehos: ehos} do
      name = start!(ehos)

      assert {:ok, %Oidcc.ProviderConfiguration{issuer: "https://ehos.test"}} =
               SignIn.provider(name)
    end

    test "while EHOS is down the child runs, and nobody can be signed in until it answers",
         %{ehos: ehos} do
      FakeEhos.down(ehos, true)
      name = start!(ehos)

      assert SignIn.provider(name) == {:error, :ehos_unavailable}
      assert Process.alive?(Process.whereis(Module.concat(name, Provider)))

      FakeEhos.down(ehos, false)

      :ok =
        Oidcc.ProviderConfiguration.Worker.refresh_configuration(Module.concat(name, Provider))

      :sys.get_state(Module.concat(name, Provider))
      assert {:ok, _configuration} = SignIn.provider(name)
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

    test "a child that is not running cannot sign anyone in" do
      assert SignIn.provider(:sign_in_never_started) == {:error, :ehos_unavailable}

      assert_raise ArgumentError, ~r/is not started/, fn ->
        SignIn.config(:sign_in_never_started)
      end
    end
  end

  # Starts the child under a name of its own and waits until its worker's first fetch
  # has run: a call is answered only after the worker's `handle_continue/2`.
  defp start!(ehos, opts \\ []) do
    name = :"sign_in_#{System.unique_integer([:positive])}"
    start_supervised!({SignIn, [name: name, http_adapter: FakeEhos.adapter(ehos)] ++ opts})
    :sys.get_state(Module.concat(name, Provider))
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

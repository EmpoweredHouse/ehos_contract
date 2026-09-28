defmodule EhOsContract.Auth.PackageTest do
  @moduledoc """
  What the package declares about itself, and what it asks of a host at boot.
  """

  use ExUnit.Case, async: false

  test "what the package calls directly is declared, not inherited through the engine" do
    declared = Mix.Project.config()[:deps] |> Enum.map(&elem(&1, 0))

    for dep <- [:jason, :ecto_sql, :postgrex, :joken, :req] do
      assert dep in declared, "#{dep} is called here directly and must be a direct dependency"
    end
  end

  test "the metadata Hex would need is present, though publication is not decided" do
    assert Mix.Project.config()[:package][:licenses] == ["Apache-2.0"]
    assert File.exists?("LICENSE")
    assert File.exists?("README.md")
    assert File.exists?("CHANGELOG.md")
  end

  test "a test credential without the key process says what to start" do
    assert_raise ArgumentError,
                 ~r/start EhOsContract.Auth in the application's supervision/,
                 fn ->
                   EhOsContract.Auth.Testing.credential("u-anna", [], %{}, keys: :not_started)
                 end
  end

  describe "the child for the host's supervision tree" do
    setup do
      config = Application.get_all_env(:eh_os_contract_auth)

      on_exit(fn ->
        for {key, _} <- Application.get_all_env(:eh_os_contract_auth),
            do: Application.delete_env(:eh_os_contract_auth, key)

        Application.put_all_env(eh_os_contract_auth: config)
      end)
    end

    test "fetches from the issuer's well-known path unless jwks_url says otherwise" do
      assert %{start: {EhOsContract.Auth.Keys, :start_link, [opts]}} =
               EhOsContract.Auth.child_spec([])

      assert opts[:url] == "https://ehos.test/.well-known/jwks.json"

      Application.put_env(:eh_os_contract_auth, :jwks_url, "https://keys.ehos.test/jwks.json")
      assert %{start: {_, _, [opts]}} = EhOsContract.Auth.child_spec(req_options: [inet6: true])
      assert opts[:url] == "https://keys.ehos.test/jwks.json"
      assert opts[:req_options] == [inet6: true]
    end

    test "fails the boot when keys would be fetched over anything but https" do
      for url <- ["http://ehos.example.com/jwks.json", "ftp://ehos.example.com/jwks.json", "ehos"] do
        Application.put_env(:eh_os_contract_auth, :jwks_url, url)

        assert_raise ArgumentError, ~r/not https/, fn -> EhOsContract.Auth.child_spec([]) end
      end

      # Credentials in the address stay out of the message, and so out of the logs.
      Application.put_env(
        :eh_os_contract_auth,
        :jwks_url,
        "http://user:secret@ehos.example.com/k"
      )

      error = assert_raise ArgumentError, fn -> EhOsContract.Auth.child_spec([]) end
      refute error.message =~ "secret"

      # The control: loopback may be plain, for development.
      Application.put_env(:eh_os_contract_auth, :jwks_url, "http://localhost:4100/jwks.json")
      assert %{start: {_, _, [opts]}} = EhOsContract.Auth.child_spec([])
      assert opts[:url] == "http://localhost:4100/jwks.json"
    end

    test "fails the boot on request options outside the few it takes" do
      # Each of these undoes what the key set is trusted by, and none is named in a
      # list of what is unsafe: each is simply not among what is allowed.
      for {req_options, message} <- [
            {[follow_redirects: true], ~r/does not take follow_redirects: in req_options/},
            {[redirect: true], ~r/does not take redirect: in req_options/},
            {[into: :self], ~r/does not take into: in req_options/},
            {[url: "http://ehos.example.com/jwks.json"], ~r/does not take url: in req_options/},
            {[finch: SomePool], ~r/does not take finch: in req_options/},
            {[finch_request: &Function.identity/1], ~r/does not take finch_request:/},
            {[decoders: [:gz]], ~r/does not take decoders: in req_options/},
            {[connect_options: [hostname: "other.example"]],
             ~r/does not take hostname: in connect_options/},
            # Mint connects to a proxy with its own thirty seconds, and to one for an
            # http address in the clear.
            {[connect_options: [proxy: {:http, "proxy.internal", 3128, []}]],
             ~r/does not take proxy: in connect_options/},
            {[connect_options: [transport_opts: [verify: :verify_none]]],
             ~r/does not take verify: in transport_opts/},
            {[
               connect_options: [
                 transport_opts: [verify_fun: {fn _, _, s -> {:valid, s} end, nil}]
               ]
             ], ~r/does not take verify_fun: in transport_opts/},
            {[connect_options: [transport_opts: [server_name_indication: :disable]]],
             ~r/does not take server_name_indication: in transport_opts/},
            {[
               connect_options: [
                 transport_opts: [cacertfile: "/etc/ehos/ca.pem", timeout: 30_000]
               ]
             ], ~r/does not take timeout: in transport_opts/},
            # Req reads the last of a key given twice, so a check of the first is fooled.
            {[connect_options: [timeout: 1], connect_options: []],
             ~r/takes connect_options: in req_options only once/},
            {%{retry: false}, ~r/takes req_options as a keyword list$/},
            {[connect_options: "ca.pem"], ~r/takes connect_options as a keyword list$/}
          ] do
        assert_raise ArgumentError, message, fn ->
          EhOsContract.Auth.child_spec(req_options: req_options)
        end
      end

      # The control: an internal authority, tuned timeouts, and tests' stubs.
      for req_options <- [
            [connect_options: [transport_opts: [cacertfile: "/etc/ehos/ca.pem"]]],
            [connect_options: [timeout: 1_000, transport_opts: [cacerts: []]]],
            [connect_options: [transport_opts: nil]],
            [connect_options: nil, receive_timeout: 2_000, inet6: true],
            [plug: {Req.Test, __MODULE__}],
            [adapter: &{&1, Req.Response.new(status: 503)}]
          ] do
        assert %{start: {_, _, [opts]}} = EhOsContract.Auth.child_spec(req_options: req_options)
        assert opts[:req_options] == req_options
      end
    end

    test "fails the boot on a stub in place of the network, except in a test" do
      Application.put_env(:eh_os_contract_auth, :pin_keys, false)

      for req_options <- [[plug: {Req.Test, __MODULE__}], [adapter: &{&1, Req.Response.new()}]] do
        assert_raise ArgumentError, ~r/in req_options only in a test/, fn ->
          EhOsContract.Auth.child_spec(req_options: req_options)
        end
      end
    end

    test "fails the boot on an option it does not take, rather than dropping it" do
      assert_raise ArgumentError, ~r/does not take req_option: in options/, fn ->
        EhOsContract.Auth.child_spec(req_option: [inet6: true])
      end
    end

    test "fails the boot on an address given in its child options" do
      assert_raise ArgumentError, ~r/not from url: in its child options/, fn ->
        EhOsContract.Auth.child_spec(url: "https://elsewhere.example.com/jwks.json")
      end
    end

    test "fails the boot without an audience, or without an issuer even with a jwks_url" do
      Application.delete_env(:eh_os_contract_auth, :audience)
      assert_raise ArgumentError, ~r/audience:/, fn -> EhOsContract.Auth.child_spec([]) end

      Application.put_env(:eh_os_contract_auth, :audience, "rehmed/test")
      Application.delete_env(:eh_os_contract_auth, :issuer)
      Application.put_env(:eh_os_contract_auth, :jwks_url, "https://keys.ehos.test/jwks.json")
      assert_raise ArgumentError, ~r/issuer:/, fn -> EhOsContract.Auth.child_spec([]) end
    end
  end
end

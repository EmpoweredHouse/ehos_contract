defmodule EhOsContract.Auth.PackageTest do
  @moduledoc """
  What the package declares about itself, and what it asks of a host at boot.
  """

  use ExUnit.Case, async: false

  test "what the package calls directly is declared, not inherited through the engine" do
    declared = Mix.Project.config()[:deps] |> Enum.map(&elem(&1, 0))

    for dep <- [:jason, :ecto_sql, :postgrex, :joken, :req, :yamerl, :jsv] do
      assert dep in declared, "#{dep} is called here directly and must be a direct dependency"
    end
  end

  test "yamerl is held to the minor version whose tokens and nodes the reader matches" do
    assert {:yamerl, "~> 0.10.0", runtime: false} in Mix.Project.config()[:deps]
  end

  test "the package carries the ehos.yaml schemas it validates with, and not its test migrations" do
    files = Mix.Project.config()[:package][:files]

    assert "priv/schemas" in files
    refute "priv" in files
    assert File.exists?("priv/schemas/ehos.yaml/v1.json")
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
      assert %{start: {_, _, [opts]}} = EhOsContract.Auth.child_spec(cacertfile: "/etc/ca.pem")
      assert opts[:url] == "https://keys.ehos.test/jwks.json"
      assert opts[:cacertfile] == "/etc/ca.pem"
    end

    # #89: the issuer is compared with each credential's iss as a string, so one EHOS could
    # never publish fails the boot, whichever address the keys come from (EHOS's rule for its issuer).
    test "fails the boot on an issuer EHOS would not start with, a jwks_url beside it or not" do
      Application.put_env(:eh_os_contract_auth, :jwks_url, "https://keys.ehos.test/jwks.json")

      for issuer <- [
            "https://EHOS.example.com",
            "https://ehos.example.com?x=1",
            "https://ehos.example.com/",
            "https://ehos.example.com/ehos",
            "http://ehos.example.com",
            "https://evil.example\\@ehos.example.com",
            "https://127.1"
          ] do
        Application.put_env(:eh_os_contract_auth, :issuer, issuer)

        assert_raise ArgumentError, ~r/issuer: is .* which EHOS would not start with/, fn ->
          EhOsContract.Auth.child_spec([])
        end
      end

      # EHOS takes plain http on loopback for its issuer, as in development.
      for issuer <- [
            "http://localhost:4000",
            "http://127.0.0.1:4000",
            "https://ehos.example.com:8443"
          ] do
        Application.put_env(:eh_os_contract_auth, :issuer, issuer)
        assert %{start: _} = EhOsContract.Auth.child_spec([]), issuer
      end
    end

    # EHOS's own start never shows a refused issuer's user, path, query or fragment.
    test "a refused address is shown without what may hold a secret" do
      for {key, value} <- [
            jwks_url: "https://svc:hunter2@keys.ehos.test/jwks.json",
            issuer: "https://svc:hunter2@ehos.example.com"
          ] do
        Application.put_env(:eh_os_contract_auth, key, value)
        error = assert_raise ArgumentError, fn -> EhOsContract.Auth.child_spec([]) end
        refute error.message =~ "hunter2"
        assert error.message =~ "with more, not shown"
        Application.delete_env(:eh_os_contract_auth, key)
        Application.put_env(:eh_os_contract_auth, :issuer, "https://ehos.test")
      end
    end

    test "fails the boot when keys would be fetched over anything but https" do
      for url <- ["http://ehos.example.com/jwks.json", "ftp://ehos.example.com/jwks.json", "ehos"] do
        Application.put_env(:eh_os_contract_auth, :jwks_url, url)

        assert_raise ArgumentError, ~r/not https/, fn -> EhOsContract.Auth.child_spec([]) end
      end

      # The control: loopback may be plain, for development.
      Application.put_env(:eh_os_contract_auth, :jwks_url, "http://localhost:4100/jwks.json")
      assert %{start: {_, _, [opts]}} = EhOsContract.Auth.child_spec([])
      assert opts[:url] == "http://localhost:4100/jwks.json"
    end

    test "fails the boot on an address in its child options, which would replace the checked one" do
      assert_raise ArgumentError, ~r/not from url: in its child options/, fn ->
        EhOsContract.Auth.child_spec(url: "http://ehos.example.com/jwks.json")
      end
    end

    test "fails the boot on an option the key process does not take" do
      assert_raise ArgumentError, ~r/unknown keys \[:req_options\]/, fn ->
        EhOsContract.Auth.child_spec(req_options: [redirect: true])
      end
    end

    test "fails the boot on a plug in place of the network, except in a test" do
      Application.put_env(:eh_os_contract_auth, :pin_keys, false)

      assert_raise ArgumentError, ~r/plug: only in a test/, fn ->
        EhOsContract.Auth.child_spec(plug: {Req.Test, __MODULE__})
      end
    end

    test "fails the boot without an audience, or without an issuer even with a jwks_url" do
      Application.delete_env(:eh_os_contract_auth, :audience)
      assert_raise ArgumentError, ~r/audience:/, fn -> EhOsContract.Auth.child_spec([]) end

      Application.put_env(:eh_os_contract_auth, :audience, "clinic/test")
      Application.delete_env(:eh_os_contract_auth, :issuer)
      Application.put_env(:eh_os_contract_auth, :jwks_url, "https://keys.ehos.test/jwks.json")
      assert_raise ArgumentError, ~r/issuer:/, fn -> EhOsContract.Auth.child_spec([]) end
    end
  end
end

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
      assert %{start: {_, _, [opts]}} = EhOsContract.Auth.child_spec(req_options: [retry: false])
      assert opts[:url] == "https://keys.ehos.test/jwks.json"
      assert opts[:req_options] == [retry: false]
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

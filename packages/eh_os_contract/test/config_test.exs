defmodule EhOsContract.ConfigTest do
  @moduledoc """
  `EhOsContract.Config`: one schema for every key of `config :eh_os_contract`, checked
  when the engine starts, and the only place the library reads them (#203).
  """

  use ExUnit.Case, async: true

  alias EhOsContract.Config

  @valid [applications: [:my_app], repo: EhOsContract.TestRepo]

  test "a configuration with the required keys is valid" do
    assert Config.validate!(@valid) == :ok
  end

  test "the configuration this suite runs with is valid" do
    assert Config.validate!() == :ok
  end

  test "a misspelled key stops the engine, naming the key" do
    message = refused(@valid ++ [autorizer: MyApp.Authorizer])
    assert message =~ "config :eh_os_contract"
    assert message =~ ":autorizer"
  end

  test "a missing required key is named, with what to write" do
    assert refused(applications: [:my_app]) =~ ":repo"
    assert refused(repo: EhOsContract.TestRepo) =~ "applications: [:my_app]"
  end

  test "a required key set to nil is refused, not taken as set" do
    assert refused(applications: [:my_app], repo: nil) =~ ":repo"
    assert refused(applications: nil, repo: EhOsContract.TestRepo) =~ ":applications"
  end

  test "a module that is not loaded is named" do
    assert refused(@valid ++ [authorizer: MyApp.Authorizr]) =~ "MyApp.Authorizr"
    assert refused(@valid ++ [store: true]) =~ ":store"
  end

  test "a module key meant for the vault is refused; another module's is left alone" do
    assert refused(@valid ++ [{EhOsContract.Vault.Local, keys: []}]) =~ "EhOsContract.Vault.Local"
    assert refused(@valid ++ [{:"Elixir.EhOsContract.Vualt", keys: []}]) =~ "EhOsContract.Vualt"
    assert Config.validate!(@valid ++ [{EhOsContract.TestRepo, pool_size: 10}]) == :ok
  end

  test "an error under EhOsContract.Vault says it is the vault's" do
    assert refused(@valid ++ [{EhOsContract.Vault, key: []}]) =~ "EhOsContract.Vault"
    assert refused(@valid ++ [{EhOsContract.Vault, keys: :none}]) =~ "EhOsContract.Vault"
  end

  test "a value of the wrong shape is named by its key" do
    assert refused(@valid ++ [subscriptions: :later]) =~ ":subscriptions"
    assert refused(@valid ++ [exclude: "MyApp.Legacy"]) =~ ":exclude"
  end

  test "no message repeats a value that may be a secret" do
    secret = "s3cr3t-broker-password"

    refute refused(@valid ++ [bus: [password: secret]]) =~ secret
    refute refused(@valid ++ [{EhOsContract.Vault, keys: [secret]}]) =~ secret
    refute refused(@valid ++ [{EhOsContract.Vault, keys: secret}]) =~ secret
    refute refused(@valid ++ [{EhOsContract.Vault, secret}]) =~ secret
    refute refused(@valid ++ [store: secret]) =~ secret
    refute refused(@valid ++ [{EhOsContract.Vault, keys: [{"k1", "a2V5"} | secret]}]) =~ secret
  end

  test "the vault's keys and the bus are checked in their shape" do
    assert Config.validate!(@valid ++ [{EhOsContract.Vault, keys: [{"2026-09", "a2V5"}]}]) == :ok
    assert Config.validate!(@valid ++ [bus: {EhOsContract.Bus.Local, []}]) == :ok
    assert Config.validate!(@valid ++ [bus: EhOsContract.Bus.Local]) == :ok
  end

  test "a module's own configuration and Ecto's :ecto_repos are left alone" do
    env =
      @valid ++
        [
          ecto_repos: [EhOsContract.TestRepo],
          "Elixir.Oban": [testing: :manual],
          "Elixir.MyApp.Repo": [pool_size: 10]
        ]

    assert Config.validate!(env) == :ok
  end

  test "an unset key reads as its default" do
    assert Config.get(:store) == EhOsContract.Store.Postgres
    assert Config.get(:authorizer) == EhOsContract.Authorizer.Default
    assert Config.get(:bus) == nil
  end

  test "the library reads its configuration only through EhOsContract.Config" do
    readers =
      for path <- Path.wildcard("lib/**/*.ex"),
          path != "lib/eh_os_contract/config.ex",
          source = File.read!(path),
          source =~ ~r/(get|fetch|get_all)_env!?\(\s*:eh_os_contract\b/ or
            source =~ ~r/:eh_os_contract\s*\|>\s*Application\./,
          do: path

    assert readers == []
  end

  defp refused(env) do
    assert_raise(ArgumentError, fn -> Config.validate!(env) end).message
  end
end

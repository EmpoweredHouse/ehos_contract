defmodule EhosContract.RegistryExcludeTest do
  @moduledoc """
  **`config :ehos_contract, exclude: [...]` keeps a namespace out of the scan** — for
  v2 contracts and the domains they share.

  `EhosContract.Registry.load!/1` is where every reader of v2 starts:
  `contracts/0` feeds the deployment table, the check and the graphs, and
  `domains/0` feeds the glossary and the view. Filtering there once is the point —
  a namespace dropped from one of those lists and not the other would put a domain in
  the glossary whose contracts no report knows. Which binary runs is an operational
  fact a deployer states in configuration, never a claim a contract makes.

  ## Why this test resets the registry explicitly

  `load!/1` caches its result in `:persistent_term` — shared, global state, not
  something the sandbox resets between tests. Every other test reads through that
  cache, so a test that narrows it and leaves it narrowed would silently break every
  test that runs after it. `on_exit` restores both the configuration and the
  unfiltered scan before the next test can observe either.
  """

  use EhosContract.DataCase, async: false

  alias EhosContract.Registry

  setup do
    on_exit(fn ->
      Application.delete_env(:ehos_contract, :exclude)
      Registry.load!()
    end)

    :ok
  end

  describe "the default: nothing excluded" do
    test "a fixture contract and its domain are in the scan" do
      Registry.load!()

      assert ProcessShapes.Promised in Registry.contracts()
      assert ProcessShapes.Domain in Registry.domains()
    end
  end

  describe "config :ehos_contract, exclude: [...]" do
    test "drops every v2 contract and domain under the named namespace" do
      Application.put_env(:ehos_contract, :exclude, ["ProcessShapes"])
      Registry.load!()

      refute ProcessShapes.Promised in Registry.contracts()
      refute ProcessShapes.Domain in Registry.domains()

      # The control: a namespace nobody named stays in the scan, so this is a filter
      # on the one prefix given, not an accident that emptied everything.
      assert UniversalityGate.TreatmentEpisode in Registry.contracts()
    end

    test "an unmatched prefix excludes nothing" do
      Application.put_env(:ehos_contract, :exclude, ["NoSuchNamespace"])
      Registry.load!()

      assert ProcessShapes.Promised in Registry.contracts()
      assert ProcessShapes.Domain in Registry.domains()
    end
  end
end

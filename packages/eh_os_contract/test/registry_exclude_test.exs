defmodule EhOsContract.RegistryExcludeTest do
  @moduledoc """
  **`config :eh_os_contract, exclude: [...]` keeps a namespace out of the scan, not just out
  of one report.**

  `EhOsContract.Registry.load!/1` is the single point every mechanism reads through —
  `mix eh_os_contract.check`, `mix eh_os_contract.report`, `EhOsContract.Graph`, `EhOsContract.Trace` — so filtering here
  once is the whole point, rather than an exception written into each report by
  hand. `PLAN.md` records why this is engine configuration and not a DSL word:
  which binary is running is an operational fact, never a claim the contract
  itself makes.

  ## Why this test resets the registry explicitly

  `load!/1` caches its result in `:persistent_term` — shared, global state, not
  something the sandbox resets between tests. Every other test in this suite
  reads through that same cache via `contracts()`/`handlers()`, so a test that
  narrows it and leaves it narrowed would silently break every test that runs
  after it. `on_exit` restores both the configuration and the unfiltered scan
  before the next test can observe either.
  """

  use EhOsContract.DataCase, async: false

  setup do
    on_exit(fn ->
      Application.delete_env(:eh_os_contract, :exclude)
      EhOsContract.Registry.load!()
    end)

    :ok
  end

  describe "the default: nothing excluded" do
    test "a fixture contract is in the scan" do
      EhOsContract.Registry.load!()
      assert ProcessShapes.Rig in EhOsContract.Registry.contracts()
    end
  end

  describe "config :eh_os_contract, exclude: [...]" do
    test "drops every contract under the named namespace" do
      Application.put_env(:eh_os_contract, :exclude, ["ProcessShapes"])
      EhOsContract.Registry.load!()

      refute ProcessShapes.Rig in EhOsContract.Registry.contracts()
      # The control: a namespace nobody named stays in the scan, so this is a
      # filter on the one prefix given, not an accident that emptied everything.
      assert UniversalityGate.TreatmentEpisode in EhOsContract.Registry.contracts()
    end

    test "drops that namespace's handlers along with its contracts" do
      Application.put_env(:eh_os_contract, :exclude, ["ProcessShapes"])
      EhOsContract.Registry.load!()

      refute Enum.any?(EhOsContract.Registry.handlers(), &(&1.contract == ProcessShapes.Rig))
    end

    test "an unmatched prefix excludes nothing" do
      Application.put_env(:eh_os_contract, :exclude, ["NoSuchNamespace"])
      EhOsContract.Registry.load!()

      assert ProcessShapes.Rig in EhOsContract.Registry.contracts()
    end
  end
end

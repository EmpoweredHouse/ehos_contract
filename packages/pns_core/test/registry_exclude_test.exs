defmodule PNS.RegistryExcludeTest do
  @moduledoc """
  **`config :pns, exclude: [...]` keeps a namespace out of the scan, not just out
  of one report.**

  `PNS.Registry.load!/1` is the single point every mechanism reads through —
  `mix pns.check`, `mix pns.report`, `PNS.Graph`, `PNS.Trace` — so filtering here
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

  use PNS.DataCase, async: false

  setup do
    on_exit(fn ->
      Application.delete_env(:pns, :exclude)
      PNS.Registry.load!()
    end)

    :ok
  end

  describe "the default: nothing excluded" do
    test "a fixture contract is in the scan" do
      PNS.Registry.load!()
      assert ProcessShapes.Rig in PNS.Registry.contracts()
    end
  end

  describe "config :pns, exclude: [...]" do
    test "drops every contract under the named namespace" do
      Application.put_env(:pns, :exclude, ["ProcessShapes"])
      PNS.Registry.load!()

      refute ProcessShapes.Rig in PNS.Registry.contracts()
      # The control: a namespace nobody named stays in the scan, so this is a
      # filter on the one prefix given, not an accident that emptied everything.
      assert UniversalityGate.TreatmentEpisode in PNS.Registry.contracts()
    end

    test "drops that namespace's handlers along with its contracts" do
      Application.put_env(:pns, :exclude, ["ProcessShapes"])
      PNS.Registry.load!()

      refute Enum.any?(PNS.Registry.handlers(), &(&1.contract == ProcessShapes.Rig))
    end

    test "an unmatched prefix excludes nothing" do
      Application.put_env(:pns, :exclude, ["NoSuchNamespace"])
      PNS.Registry.load!()

      assert ProcessShapes.Rig in PNS.Registry.contracts()
    end
  end
end

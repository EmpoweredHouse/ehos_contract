defmodule EhOsContract.UniversalityGateTest do
  @moduledoc """
  v2 plan, E4: **the universality gate's invented contract, in the v2 DSL.**
  `UniversalityGate.TreatmentEpisode` is compiled by `mix compile` from
  `test/support/`, like a consumer's contract, and describes a domain with nothing
  to do with accounting in the words `vocabulary/0` pins
  (`contract_vocabulary_test.exs`) — none added for it, counted since 29 September 2026
  from that literal (its note says why not from v1's keys).

  One test here does by hand what the Mix compiler also does (L3, X2–X4): every actor,
  value, subject and external the contract names is declared by its domain.
  """

  use ExUnit.Case, async: true

  alias EhOsContract.Model

  @contract UniversalityGate.TreatmentEpisode
  # Its run, a process module since plan DD, P2g (#228).
  @run UniversalityGate.TreatmentEpisodeRun

  test "the shapes TaxVision does not have survive the translation" do
    model = Model.fetch(@contract)
    events = Map.new(model.events, &{&1.name, &1})

    # An event arriving without a command.
    assert events.referral_received.recorded_by == [:referral_intake]
    refute Enum.any?(model.commands, &(:referral_received in &1.emits))

    # The same event many times in one run: a stream, and no key of its own.
    assert Enum.map(events.session_completed.fields, & &1.name) ==
             [:episode_id, :session_no, :performed_at]

    # Run identity from a single field.
    run = Model.process(@run)
    assert run.correlate == [:episode_id]
    assert run.deadline == %{amount: 30, unit: :day, unverified: true}
  end

  test "the stages keep v1's order, and every event sits in one" do
    model = Model.fetch(@contract)

    assert Enum.map(Model.process(@run).stages, & &1.name) ==
             [:qualification, :plan, :treatment, :closing]

    assert Enum.map(Model.process_events(@run), & &1.name) == Enum.map(model.events, & &1.name)
    assert Enum.all?(Model.process_events(@run), &(&1.stage != nil))
  end

  test "the rule became an invariant with a rejected scenario, the examples scenarios" do
    model = Model.fetch(@contract)

    assert [%{invariants: [%{name: :treatment_starts_only_on_confirmed_eligibility}]}] =
             model.units

    # The second, an active payer naming no scope, since the property tests found the
    # decision confirmed one without it (plan DD, PC2, #266).
    assert Enum.map(model.scenarios, & &1.rejected) == [
             nil,
             :treatment_starts_only_on_confirmed_eligibility,
             nil,
             :treatment_starts_only_on_confirmed_eligibility
           ]
  end

  test "everything the contract names, its domain declares" do
    contract = Model.fetch(@contract)
    domain = Model.fetch(contract.domain)
    names = fn key -> MapSet.new(Map.fetch!(domain, key), & &1.name) end

    actors =
      Enum.flat_map(contract.commands, & &1.by) ++
        Enum.flat_map(contract.events, & &1.recorded_by) ++ [Model.process(@run).accountable]

    fields =
      Enum.flat_map(contract.commands ++ contract.events, & &1.fields) ++
        hd(contract.units).state.fields

    built_in = EhOsContract.Domain.Rules.built_in_types()
    values = for %{type: type} <- fields, is_atom(type), type not in built_in, do: type

    assert MapSet.subset?(MapSet.new(actors), names.(:actors))
    assert MapSet.subset?(MapSet.new(values), names.(:values))
    assert MapSet.subset?(MapSet.new(for(%{subject: s} <- fields, s, do: s)), names.(:subjects))

    assert MapSet.subset?(
             MapSet.new(for(%{depends_on: d} <- contract.events, d, do: d)),
             names.(:externals)
           )

    assert Enum.any?(domain.contexts, &(&1.name == contract.context))
  end

  test "the built-in types are a closed set, pinned as a literal" do
    # The filter above trusts this list: a type in it is a shape and needs no
    # declaration, anything else is a domain's value. So the set is closed, as v1's
    # `payload_types/0` was — each type names a shape, never a thing somebody's
    # business calls a thing, and a new one is a decision about the DSL, written down
    # where decisions are, not a drive-by in `Domain.Rules`. Pinned as a literal, so
    # adding one fails here the same day.
    assert EhOsContract.Domain.Rules.built_in_types() ==
             [:id, :string, :integer, :decimal, :boolean, :date, :timestamp]
  end
end

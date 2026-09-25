defmodule EhOsContract.ModelTest do
  @moduledoc """
  v2 plan, E1: **the model says what the generated functions say, and nothing else.**

  Every reader moves from `contract.events()` to `EhOsContract.Model.events(contract)`
  one commit at a time, and each move claims to change no behaviour. That claim
  rests on this file: for every fixture contract, each accessor returns exactly what
  the function it replaces returned — same values, same order, same error. The
  fixtures cover every declaration kind between them: processes with and without
  stages, traces with `within` and `or_else`, externals, rules with examples, and
  commands.
  """

  use ExUnit.Case, async: true

  alias EhOsContract.Model

  @contracts [
    ProcessShapes.Bare,
    ProcessShapes.Promised,
    ProcessShapes.Rig,
    ProcessShapes.Timed,
    UniversalityGate.TreatmentEpisode
  ]

  test "the fixtures between them declare every kind the model carries" do
    for kind <- [:events, :processes, :commands, :traces, :externals, :rules, :examples] do
      assert Enum.any?(@contracts, &(Model.fetch(&1)[kind] != [])),
             "no fixture declares any #{kind}, so this file proves nothing about them"
    end
  end

  for contract <- @contracts do
    describe inspect(contract) do
      @contract contract

      test "collections equal the generated functions, in declaration order" do
        assert Model.events(@contract) == @contract.events()
        assert Model.event_names(@contract) == @contract.event_names()
        assert Model.processes(@contract) == @contract.processes()
        assert Model.commands(@contract) == @contract.commands()
        assert Model.traces(@contract) == @contract.traces()
        assert Model.externals(@contract) == @contract.externals()
        assert Model.rules(@contract) == @contract.rules()
        assert Model.examples(@contract) == @contract.examples()
        assert Model.version(@contract) == @contract.version()
        assert Model.digests(@contract) == @contract.declaration_digests()
        assert Model.module(@contract) == @contract
      end

      test "lookups by name equal the generated ones, including misses" do
        names = fn list -> [:no_such_declaration | Enum.map(list, & &1.name)] end

        for name <- names.(@contract.events()) do
          assert Model.event?(@contract, name) == @contract.event?(name)
          assert Model.process_of(@contract, name) == @contract.process_of(name)
        end

        for name <- names.(@contract.processes()) do
          assert Model.process(@contract, name) == @contract.process(name)
          assert Model.events_of(@contract, name) == @contract.events_of(name)
        end

        for name <- names.(@contract.externals()),
            do: assert(Model.external(@contract, name) == @contract.external(name))

        for name <- names.(@contract.rules()),
            do: assert(Model.rule(@contract, name) == @contract.rule(name))

        for name <- names.(@contract.commands()),
            do: assert(Model.command(@contract, name) == @contract.command(name))

        for name <- names.(@contract.traces()),
            do:
              assert(
                Model.trace(@contract, name) == Enum.find(@contract.traces(), &(&1.name == name))
              )

        for event <- @contract.events(),
            do: assert(Model.event(@contract, event.name) == @contract.event(event.name))
      end

      test "an undeclared event raises the same error" do
        expected = assert_raise ArgumentError, fn -> @contract.event(:no_such_event) end
        actual = assert_raise ArgumentError, fn -> Model.event(@contract, :no_such_event) end
        assert actual.message == expected.message
      end

      test "a built model answers like its module" do
        model = Model.fetch(@contract)
        assert Model.fetch(model) == model
        assert Model.events(model) == Model.events(@contract)
        assert Model.version(model) == Model.version(@contract)
      end
    end
  end

  test "contract?/1 recognises contracts and nothing else" do
    assert Enum.all?(@contracts, &Model.contract?/1)
    refute Model.contract?(ProcessShapes.Promised.OnRequestReceived)
    refute Model.contract?(Enum)
    refute Model.contract?(No.Such.Module)
  end
end

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

  test "a module that is not a contract is refused by name, not by a missing function" do
    error = assert_raise ArgumentError, fn -> Model.traces(Enum) end
    assert error.message =~ "Enum is not an EhOsContract contract"
  end

  test "to_data names and digests the JSON-ready v2 model, domain and capabilities" do
    document = Model.to_data(DispatchRig.Transfer)

    assert document["schema"] == "eh_os_contract.model.v1"
    assert document["contract"]["module"] == "DispatchRig.Transfer"
    assert document["domain"]["module"] == "DispatchRig.Domain"

    assert document["capabilities"]["dispatch_rig.move_account"] == %{
             "kind" => "command",
             "name" => "move_account",
             "roles" => ["dispatch_rig.clerk"],
             "scope" => "branch_id"
           }

    assert byte_size(document["digest"]) == 12
    assert Jason.decode!(Jason.encode!(document)) == document
    assert Model.to_data(DispatchRig.Transfer) == document
  end

  test "to_data is for v2 contracts, not domains or v1 contracts" do
    assert_raise ArgumentError, ~r/is a domain, not a contract/, fn ->
      Model.to_data(DispatchRig.Domain)
    end

    assert_raise ArgumentError, ~r/is a v1 contract/, fn ->
      Model.to_data(ProcessShapes.Bare)
    end
  end

  # A contract whose module exists on the code path but is not loaded yet, which is
  # the ordinary state of any module in dev before first use. `function_exported?/3`
  # alone answers false for it. The module is private to this test, so unloading it
  # cannot disturb any other test running alongside.
  @tag :tmp_dir
  test "contract?/1 recognises a contract that is not loaded yet", %{tmp_dir: dir} do
    source = Path.join(dir, "not_yet_loaded.ex")

    File.write!(source, """
    defmodule EhOsContract.ModelTest.NotYetLoaded do
      use EhOsContract.Contract
      event :noted, label: "Zanotowano"
    end
    """)

    {:ok, [module], _} = Kernel.ParallelCompiler.compile_to_path([source], dir)
    true = Code.prepend_path(dir)
    on_exit(fn -> Code.delete_path(dir) end)
    :code.purge(module)
    :code.delete(module)
    :code.purge(module)
    refute :code.is_loaded(module)

    assert Model.contract?(module)
    assert Model.event_names(module) == [:noted]
  end

  test "contract?/1 recognises contracts and nothing else" do
    assert Enum.all?(@contracts, &Model.contract?/1)
    refute Model.contract?(ProcessShapes.Promised.OnRequestReceived)
    refute Model.contract?(Enum)
    refute Model.contract?(No.Such.Module)
  end
end

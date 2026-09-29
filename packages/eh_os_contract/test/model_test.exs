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

  defmodule PersonalExport do
    @moduledoc false
    use EhOsContract.Next.Contract, domain: ShreddingRig.Domain, context: :membership

    aggregate :profile, "Profile" do
      identity :profile_id

      command :register, "Register", by: :clerk, emits: :registered do
        field :member_id, :id, subject: :member
        field :name, :string, personal: :member_id
        field :contacts, {:list, :contact}
      end

      event :registered, "Registered" do
        field :member_id, :id, subject: :member
        field :name, :string, personal: :member_id
        field :contacts, {:list, :contact}
      end
    end

    process :profile, "Profile" do
      correlate :profile_id
    end

    read_model :profiles, "Profiles", projects: :registered do
      field :member_id, :id, subject: :member
      field :name, :string, personal: :member_id
      field :contacts, {:list, :contact}
    end

    query :profiles, "Profiles", reads: :profiles, by: :clerk do
      param :member_id, :id
    end

    scenario "a profile carries direct and nested personal values" do
      command :register, %{
        profile_id: "profile-1",
        member_id: "member-1",
        name: "Ada Example",
        contacts: [%{member_id: "member-2", phone: "+48-555-0100"}]
      }

      expect :registered, %{
        member_id: "member-1",
        name: "Ada Example",
        contacts: [%{member_id: "member-2", phone: "+48-555-0100"}]
      }
    end

    scenario "a query answer carries direct and nested personal values" do
      query :profiles, %{member_id: "member-1"}

      answers [
        %{
          member_id: "member-1",
          name: "Ada Example",
          contacts: [%{member_id: "member-2", phone: "+48-555-0100"}]
        }
      ]
    end
  end

  # A consumer's scenario names the sibling's event, under its local name, and its
  # personal fields are declared there, not here.
  defmodule PersonalConsumer do
    @moduledoc false
    use EhOsContract.Next.Contract, domain: ShreddingRig.Domain, context: :membership

    consumes EhOsContract.ModelTest.PersonalExport, :registered,
      as: [registered: :member_registered]

    aggregate :welcome, "Welcome" do
      identity :profile_id

      command :welcome, "Welcome", emits: :welcomed do
        field :member_id, :id, subject: :member
        field :name, :string, personal: :member_id
      end

      event :welcomed, "Welcomed" do
        field :member_id, :id, subject: :member
        field :name, :string, personal: :member_id
      end
    end

    policy :welcome_registered, "Welcome a registered member",
      handles: :member_registered,
      issues: :welcome

    process :welcome, "Welcome" do
      correlate :profile_id
    end

    scenario "a sibling's registration carries direct and nested personal values" do
      scope :welcome_registered

      on :member_registered, %{
        profile_id: "profile-1",
        member_id: "member-1",
        name: "Ada Example",
        contacts: [%{member_id: "member-2", phone: "+48-555-0100"}]
      }

      issues :welcome, %{member_id: "member-1", name: "Ada Example"}
    end
  end

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

    ledger = Model.to_data(DispatchRig.Ledger)
    query = Enum.find(ledger["contract"]["queries"], &(&1["name"] == "balances_for_branch"))
    refute Map.has_key?(hd(query["params"]), "default")
  end

  test "to_data is for v2 contracts, not domains or v1 contracts" do
    assert_raise ArgumentError, ~r/is a domain, not a contract/, fn ->
      Model.to_data(DispatchRig.Domain)
    end

    assert_raise ArgumentError, ~r/is a v1 contract/, fn ->
      Model.to_data(ProcessShapes.Bare)
    end
  end

  test "to_data keeps example structure but redacts direct and nested personal values" do
    document = Model.to_data(PersonalExport)
    encoded = Jason.encode!(document)

    refute encoded =~ "Ada Example"
    refute encoded =~ "+48-555-0100"
    assert encoded =~ "member-1"
    assert encoded =~ "member-2"

    scenario = hd(document["contract"]["scenarios"])
    assert scenario["trigger"]["data"]["name"] == nil
    assert hd(scenario["trigger"]["data"]["contacts"])["phone"] == nil
    assert hd(scenario["expect"])["data"]["name"] == nil

    query_scenario = List.last(document["contract"]["scenarios"])
    assert hd(query_scenario["answers"])["name"] == nil
    assert hd(hd(query_scenario["answers"])["contacts"])["phone"] == nil

    register = Enum.find(document["contract"]["commands"], &(&1["name"] == "register"))
    name = Enum.find(register["fields"], &(&1["name"] == "name"))
    assert name["personal"] == "member_id"
  end

  test "to_data redacts a consumed sibling event by the sibling's personal fields" do
    document = Model.to_data(PersonalConsumer)
    encoded = Jason.encode!(document)

    refute encoded =~ "Ada Example"
    refute encoded =~ "+48-555-0100"

    [scenario] = document["contract"]["scenarios"]
    assert scenario["trigger"]["data"]["member_id"] == "member-1"
    assert scenario["trigger"]["data"]["name"] == nil
    assert hd(scenario["trigger"]["data"]["contacts"])["phone"] == nil
    assert hd(scenario["issues"])["data"]["name"] == nil
  end

  # What the compiler refuses in a contract it checks (X5, X9, S1, S3) can still reach
  # the export from one it never saw: each case is published as `null`, never verbatim.
  describe "to_data fails closed" do
    test "on a sibling that no longer declares the consumed event" do
      model =
        Map.update!(Model.fetch(PersonalConsumer), :consumes, fn [consumed] ->
          [%{consumed | events: [:ghost], renames: %{ghost: :member_registered}}]
        end)

      {redacted, _domain} = redact(model)
      [scenario] = redacted.scenarios

      assert Enum.all?(Map.values(scenario.trigger.data), &is_nil/1)
    end

    test "on a data key no field declares" do
      model =
        update_scenario(PersonalExport, 0, fn scenario ->
          put_in(scenario.trigger.data[:nickname], "Ada")
        end)

      {redacted, _domain} = redact(model)
      data = hd(redacted.scenarios).trigger.data

      assert data.nickname == nil
      assert data.member_id == "member-1"
    end

    test "on an answer whose query cannot be found" do
      model =
        update_scenario(PersonalExport, 1, fn scenario ->
          put_in(scenario.trigger.name, :ghost)
        end)

      {redacted, _domain} = redact(model)
      [row] = List.last(redacted.scenarios).answers

      assert Enum.all?(Map.values(row), &is_nil/1)
    end

    test "on a structured value's example that is not a map" do
      domain =
        Map.update!(Model.fetch(ShreddingRig.Domain), :values, fn values ->
          Enum.map(values, fn
            %{name: :contact} = contact ->
              Map.put(contact, :invariants, [
                %{violated_by: ["+48-555-0100"], satisfied_by: []}
              ])

            value ->
              value
          end)
        end)

      {_model, redacted} = EhOsContract.Model.Export.redact(Model.fetch(PersonalExport), domain)
      contact = Enum.find(redacted.values, &(&1.name == :contact))

      assert [%{violated_by: [nil]}] = contact.invariants
    end
  end

  defp redact(model),
    do: EhOsContract.Model.Export.redact(model, Model.fetch(ShreddingRig.Domain))

  defp update_scenario(contract, index, fun) do
    Map.update!(Model.fetch(contract), :scenarios, &List.update_at(&1, index, fun))
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

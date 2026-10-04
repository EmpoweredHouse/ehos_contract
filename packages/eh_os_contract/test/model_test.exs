defmodule EhOsContract.ModelTest do
  @moduledoc """
  **`EhOsContract.Model` as a reader outside the engine gets it**: a module that is
  not a contract is refused by name, and `to_data/1` names and digests a v2
  contract's model, its domain and its capabilities, with personal values redacted
  from the examples — failing closed on what the compiler would have refused.

  v2 plan, E1 pinned here that the model said what v1's generated functions said,
  for every v1 fixture; that went with v1's fixtures (plan E11a).
  """

  use ExUnit.Case, async: true

  alias EhOsContract.Model

  defmodule PersonalExport do
    @moduledoc false
    use EhOsContract.Contract, domain: ShreddingRig.Domain, context: :membership

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
    use EhOsContract.Contract, domain: ShreddingRig.Domain, context: :membership

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
      target(:welcome_registered)

      on :member_registered, %{
        profile_id: "profile-1",
        member_id: "member-1",
        name: "Ada Example",
        contacts: [%{member_id: "member-2", phone: "+48-555-0100"}]
      }

      issues :welcome, %{member_id: "member-1", name: "Ada Example"}
    end
  end

  test "a module that is not a contract is refused by name, not by a missing function" do
    error = assert_raise ArgumentError, fn -> Model.fetch(Enum) end
    assert error.message =~ "Enum is not a contract or a domain compiled from EhOsContract's DSL"
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

  test "to_data is for contracts, not domains" do
    assert_raise ArgumentError, ~r/is a domain, not a contract/, fn ->
      Model.to_data(DispatchRig.Domain)
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

    # Plan EP4: a process manager's scenario says the state its run holds, and the run's
    # fields say which are personal; a key the state does not declare is dropped.
    test "on a process manager's expected state" do
      model = Model.fetch(PersonalExport)
      [_profile_id, member_id, name, _contacts] = hd(model.events).fields

      model =
        model
        |> Map.put(:process_managers, [
          %{name: :welcome, state: %{fields: [member_id, name]}}
        ])
        |> Map.update!(:scenarios, fn [first | rest] ->
          welcome = %{
            first
            | target: %{kind: :process_manager, name: :welcome},
              expect: [],
              trigger: %{kind: :on, name: :registered, data: %{}}
          }

          [Map.put(welcome, :state, %{member_id: "member-1", name: "Ada", nickname: "A"}) | rest]
        end)

      {redacted, _domain} = redact(model)

      assert hd(redacted.scenarios).state == %{member_id: "member-1", name: nil, nickname: nil}
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
end

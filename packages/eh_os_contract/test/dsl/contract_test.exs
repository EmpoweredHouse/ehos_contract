defmodule EhOsContract.ContractTest do
  @moduledoc """
  v2 plan, E4: **a v2 contract compiles to plain data** (v2 §9), whose version does
  not see declaration order.

  The fixtures are declared inside this file on purpose: modules defined in a `.exs`
  are not in the application's module list, so the registry never sees them.
  Their domain, `EhOsContract.ContractTest.Clinic`, does not exist, and that is
  the point of one test: `domain:` records no compile dependency (v2 §8).
  """

  use EhOsContract.DslCase, async: false

  alias EhOsContract.Model

  defmodule Golden do
    @moduledoc false
    use EhOsContract.Contract,
      domain: EhOsContract.ContractTest.Clinic,
      context: :settlement,
      id: "clinic.golden"

    aggregate :visit, "Visit", source: "AGG-11" do
      identity :visit_id

      state do
        field :total, :money, optional: true
        field :payments, {:list, :money}, default: []
      end

      invariant :paid_in_full, "Paid in full"

      command :record_payment, "Recording a payment", by: :reception, emits: :payment_recorded do
        field :amount, :money
      end

      command :close, "Closing",
        by: [:reception, :manager],
        emits: :closed,
        rejects: :paid_in_full

      event :payment_recorded, "Paid" do
        field :amount, :money
      end

      event :closed, "Closed"
    end

    scenario "paid too little — closing rejected" do
      given :payment_recorded, %{amount: 100}
      command :close
      rejected :paid_in_full
    end
  end

  defmodule Reordered do
    @moduledoc false
    use EhOsContract.Contract,
      domain: EhOsContract.ContractTest.Clinic,
      context: :settlement,
      id: "clinic.golden"

    aggregate :visit, "Visit", source: "AGG-11" do
      identity :visit_id

      event :closed, "Closed"

      event :payment_recorded, "Paid" do
        field :amount, :money
      end

      command :close, "Closing",
        by: [:manager, :reception],
        emits: :closed,
        rejects: :paid_in_full

      command :record_payment, "Recording a payment", by: :reception, emits: :payment_recorded do
        field :amount, :money
      end

      invariant :paid_in_full, "Paid in full"

      state do
        field :payments, {:list, :money}, default: []
        field :total, :money, optional: true
      end
    end

    scenario "paid too little — closing rejected" do
      given :payment_recorded, %{amount: 100}
      command :close
      rejected :paid_in_full
    end
  end

  defmodule Changed do
    @moduledoc false
    use EhOsContract.Contract,
      domain: EhOsContract.ContractTest.Clinic,
      context: :settlement,
      id: "clinic.golden"

    aggregate :visit, "Visit", source: "AGG-11" do
      identity :visit_id

      state do
        field :total, :money, optional: true
        field :payments, {:list, :money}, default: []
      end

      invariant :paid_in_full, "Paid in full"

      command :record_payment, "Recording a payment", by: :reception, emits: :payment_recorded do
        field :amount, :money
      end

      command :close, "Closing",
        by: [:reception, :manager],
        emits: :closed,
        rejects: :paid_in_full

      # The only difference from `Golden`: the amount is optional.
      event :payment_recorded, "Paid" do
        field :amount, :money, optional: true
      end

      event :closed, "Closed"
    end

    scenario "paid too little — closing rejected" do
      given :payment_recorded, %{amount: 100}
      command :close
      rejected :paid_in_full
    end
  end

  @id %{name: :visit_id, type: :id, optional: false, label: nil, personal: nil, subject: nil}
  @amount %{name: :amount, type: :money, optional: false, label: nil, personal: nil, subject: nil}

  defp no_default(map), do: Map.put(map, :default, nil)

  @digests [:version, :digests, :text_digest, :text_digests]

  describe "the model" do
    test "is the golden one" do
      assert Map.drop(Model.fetch(Golden), @digests) == %{
               format: 1,
               kind: :contract,
               module: Golden,
               domain: EhOsContract.ContractTest.Clinic,
               context: :settlement,
               id: "clinic.golden",
               units: [
                 %{
                   name: :visit,
                   kind: :aggregate,
                   label: "Visit",
                   source: "AGG-11",
                   identity: [:visit_id],
                   consults: [],
                   state: %{
                     fields: [
                       no_default(@id),
                       no_default(%{@amount | name: :total, optional: true}),
                       %{@amount | name: :payments, type: {:list, :money}}
                       |> Map.put(:default, [])
                     ]
                   },
                   invariants: [%{name: :paid_in_full, label: "Paid in full", source: nil}]
                 }
               ],
               commands: [
                 %{
                   name: :record_payment,
                   unit: :visit,
                   label: "Recording a payment",
                   source: nil,
                   by: [:reception],
                   emits: [:payment_recorded],
                   rejects: [],
                   fields: [no_default(@id), no_default(@amount)]
                 },
                 %{
                   name: :close,
                   unit: :visit,
                   label: "Closing",
                   source: nil,
                   by: [:reception, :manager],
                   emits: [:closed],
                   rejects: [:paid_in_full],
                   fields: [no_default(@id)]
                 }
               ],
               events: [
                 %{
                   name: :payment_recorded,
                   unit: :visit,
                   type: "clinic.golden.payment_recorded",
                   label: "Paid",
                   recorded_by: [],
                   depends_on: nil,
                   schema_version: 1,
                   source: nil,
                   fields: [no_default(@id), no_default(@amount)]
                 },
                 %{
                   name: :closed,
                   unit: :visit,
                   type: "clinic.golden.closed",
                   label: "Closed",
                   recorded_by: [],
                   depends_on: nil,
                   schema_version: 1,
                   source: nil,
                   fields: [no_default(@id)]
                 }
               ],
               policies: [],
               effects: [],
               process_managers: [],
               read_models: [],
               queries: [],
               domain_services: [],
               consumes: [],
               publishes: [],
               scenarios: [
                 %{
                   description: "paid too little — closing rejected",
                   target: %{kind: :aggregate, name: :visit},
                   actor: nil,
                   given: [%{event: :payment_recorded, data: %{amount: 100}}],
                   trigger: %{kind: :command, name: :close, data: %{}},
                   expect: [],
                   rejected: :paid_in_full,
                   issues: [],
                   sets: [],
                   cancels: [],
                   ended: false
                 }
               ],
               grants: %{
                 reception: %{commands: [:close, :record_payment], queries: [], records: []},
                 manager: %{commands: [:close], queries: [], records: []}
               }
             }
    end

    test "has one digest per declaration, keyed by kind and name" do
      assert Model.fetch(Golden).digests |> Map.keys() |> Enum.sort() == [
               "command:close",
               "command:record_payment",
               "contract",
               "event:closed",
               "event:payment_recorded",
               "scenario:*",
               "unit:visit"
             ]

      assert Model.fetch(Golden).text_digests |> Map.keys() |> Enum.sort() ==
               Model.fetch(Golden).digests |> Map.keys() |> Enum.sort()
    end

    test "each digest is twelve hex characters, so it can be read out of a report" do
      # The contract version's shape, for the same reason: the deployment table stores
      # these, and the report names the declaration whose digest moved.
      for {_key, digest} <- Model.fetch(Golden).digests do
        assert digest =~ ~r/^[0-9a-f]{12}$/
      end
    end

    test "holds no Spark struct and no source annotation" do
      refute inspect(Model.fetch(Golden), limit: :infinity) =~
               ~r/__spark_metadata__|__struct__|Spark\./
    end

    test "names its capabilities after the domain, which has to be compiled (D14)" do
      compile("""
      defmodule EhOsContract.ContractTest.ClinicDomain do
        use EhOsContract.Domain, name: :clinic, language: :pl

        actor :reception, :human, "Reception"
        actor :manager, :human, "Manager"
        actor :registry, :system, "Registry"
      end

      defmodule EhOsContract.ContractTest.Named do
        use EhOsContract.Contract,
          domain: EhOsContract.ContractTest.ClinicDomain,
          context: :settlement, id: "clinic.named"

        subscribe "scheduling.visit.closed.v1", as: :closed_elsewhere do
          field :visit_id, :id
        end

        subscribe "scheduling.visit.opened.v1", as: :opened_elsewhere do
          field :visit_id, :id
        end

        aggregate :visit, "Visit" do
          identity :visit_id
          command :close, "Closing", by: [:reception, :manager, :registry], emits: :closed
          command :remind, "Reminder", emits: :reminded
          event :closed, "Closed"
          event :reminded, "Reminded"
          event :arrived, "Arrived", recorded_by: :reception
          event :reported, "Reported", recorded_by: :registry
        end

        policy :remind_on_close, "Reminder after closing",
          handles: [:closed, :closed_elsewhere],
          issues: :remind

        read_model :open_visits, "Open visits", projects: :closed do
          field :clinic_id, :id
        end

        query :open_for_clinic, "Open in the clinic", reads: :open_visits, by: :reception do
          param :clinic_id, :id
          scope :clinic_id
        end
      end
      """)

      # Only what a person may do is a capability, and its roles are the people's: the
      # system actor is not a role of :close, and :remind (a reaction's) and :reported
      # (the registry's) have none (plan, E9a review). Besides, the application's
      # `<name>.subscribe`, without its version, for an event a policy handles, and none
      # for :opened_elsewhere, which nothing handles and no inbox would take (E12c).
      assert Model.capabilities(EhOsContract.ContractTest.Named) == %{
               "scheduling.visit.closed.subscribe" => %{
                 kind: :subscribe,
                 name: :closed_elsewhere,
                 roles: [],
                 scope: nil
               },
               "clinic.close" => %{
                 kind: :command,
                 name: :close,
                 roles: ["clinic.manager", "clinic.reception"],
                 scope: nil
               },
               "clinic.arrived" => %{
                 kind: :record,
                 name: :arrived,
                 roles: ["clinic.reception"],
                 scope: nil
               },
               "clinic.open_for_clinic" => %{
                 kind: :query,
                 name: :open_for_clinic,
                 roles: ["clinic.reception"],
                 scope: :clinic_id
               }
             }
    end

    test "refuses capabilities for a domain that is not compiled" do
      error = assert_raise ArgumentError, fn -> Model.capabilities(Golden) end

      assert error.message =~
               "names domain EhOsContract.ContractTest.Clinic, which is not a compiled"

      # A module that exists and is no domain at all: named as the contract's domain,
      # not refused as a module without a model.
      error =
        assert_raise ArgumentError, fn ->
          Model.capabilities(%{Model.fetch(Golden) | domain: Enum})
        end

      assert error.message =~ "names domain Enum, which is not a compiled EhOsContract.Domain"
    end
  end

  describe "the version" do
    test "does not move when declarations are written in another order, nested ones included" do
      assert Model.fetch(Golden).version == Model.fetch(Reordered).version
      assert Model.fetch(Golden).digests == Model.fetch(Reordered).digests
      assert Model.fetch(Golden).text_digest == Model.fetch(Reordered).text_digest
      assert Model.fetch(Golden).text_digests == Model.fetch(Reordered).text_digests
    end

    test "moves when one declaration changes, and only that declaration's digest moves" do
      golden = Model.fetch(Golden)
      changed = Model.fetch(Changed)

      assert golden.version != changed.version
      moved = for {key, digest} <- golden.digests, changed.digests[key] != digest, do: key
      assert moved == ["event:payment_recorded"]
    end

    test "moves when the order of identity fields changes, which names another stream" do
      version = fn identity ->
        name = "Identity#{System.unique_integer([:positive])}"

        compile("""
        defmodule EhOsContract.ContractTest.#{name} do
          use EhOsContract.Contract, domain: Clinic, context: :billing, id: "clinic.compared"

          dcb :payer_period, "Payer's period" do
            identity #{inspect(identity)}
            consults :period_closed, match: :payer_id
            command :close_period, "Closing the period", by: :manager, emits: :period_closed
            event :period_closed, "Period closed"
          end
        end
        """)

        Model.fetch(Module.concat(__MODULE__, name)).version
      end

      assert version.([:payer_id, :period_id]) != version.([:period_id, :payer_id])
    end

    # Plan DD, V5 (#322): the version is what the contract allows, and its words have a
    # digest of their own. A clinic's visit, relabelled for the manager who reads it.
    defp visit(name, words, field \\ "") do
      compile("""
      defmodule EhOsContract.ContractTest.#{name} do
        use EhOsContract.Contract, domain: Clinic, context: :settlement, id: "clinic.compared"

        aggregate :visit, "#{words.unit}" do
          identity :visit_id
          command :complete_visit, "#{words.command}", by: :reception, emits: :visit_completed
          event :visit_completed, "#{words.event}", source: "#{words.source}" do
            field :room, :string
            #{field}
          end
        end

        scenario "#{words.scenario}" do
          command :complete_visit, %{visit_id: "v-1"}
          expect :visit_completed, %{visit_id: "v-1", room: "#{words.room}"}
        end
      end
      """)

      Model.fetch(Module.concat(__MODULE__, name))
    end

    @words %{
      unit: "Visit",
      command: "Complete the visit",
      event: "Visit completed",
      source: "M1 00:12:40",
      scenario: "reception completes the visit",
      room: "room 2"
    }

    test "does not move when only the words change, and the words' digest does" do
      before = visit("WordsBefore", @words)

      after_ =
        visit("WordsAfter", %{
          @words
          | unit: "A patient's visit",
            command: "The patient leaves",
            event: "The patient left the room",
            source: "M1 00:13:05",
            scenario: "the patient leaves the room"
        })

      assert before.version == after_.version
      assert before.digests == after_.digests
      refute before.text_digest == after_.text_digest

      moved =
        for {key, digest} <- before.text_digests, after_.text_digests[key] != digest, do: key

      assert Enum.sort(moved) ==
               ["command:complete_visit", "event:visit_completed", "scenario:*", "unit:visit"]
    end

    test "does not see the order of scenarios, in the version or the words" do
      scenarios = fn name, order ->
        [one, two] =
          Enum.map(["room 1", "room 2"], fn room ->
            """
              scenario "visit in: #{room}" do
                command :complete_visit, %{visit_id: "v-1"}
                expect :visit_completed, %{visit_id: "v-1", room: "#{room}"}
              end
            """
          end)

        compile("""
        defmodule EhOsContract.ContractTest.#{name} do
          use EhOsContract.Contract, domain: Clinic, context: :settlement, id: "clinic.compared"

          aggregate :visit, "Visit" do
            identity :visit_id
            command :complete_visit, "Complete the visit", by: :reception, emits: :visit_completed
            event :visit_completed, "Visit completed" do
              field :room, :string
            end
          end

        #{if order == :forward, do: one <> two, else: two <> one}
        end
        """)

        Model.fetch(Module.concat(__MODULE__, name))
      end

      forward = scenarios.("ScenariosForward", :forward)
      backward = scenarios.("ScenariosBackward", :backward)

      assert forward.digests == backward.digests
      assert forward.text_digests == backward.text_digests
    end

    test "moves when a field is added, and the words' digest does not" do
      before = visit("FieldBefore", @words)
      after_ = visit("FieldAfter", @words, "field :doctor, :string, optional: true")

      refute before.version == after_.version
      moved = for {key, digest} <- before.digests, after_.digests[key] != digest, do: key
      assert moved == ["event:visit_completed"]
      assert before.text_digest == after_.text_digest
    end

    test "moves when a scenario's data changes, a field's value not being a word" do
      before = visit("DataBefore", @words)
      after_ = visit("DataAfter", %{@words | room: "room 3"})

      refute before.version == after_.version
      assert before.text_digest == after_.text_digest
    end
  end

  describe "the domain" do
    test "is named without being compiled or even existing (v2 §8)" do
      refute Code.ensure_loaded?(EhOsContract.ContractTest.Clinic)
      assert Model.fetch(Golden).domain == EhOsContract.ContractTest.Clinic
    end
  end

  describe "options beside a do block (D13) in the contract" do
    test "an unknown one points at the declaration's line" do
      error =
        compile_error(
          """
          defmodule EhOsContract.ContractTest.UnknownOption do
            use EhOsContract.Contract, domain: Clinic, context: :settlement, id: "clinic.unknown_option"

            aggregate :visit, "Visit" do
              identity :visit_id

              command :close, "Closing", by: :reception, emit: :closed do
                field :note, :string
              end
            end
          end
          """,
          "unknown_option.ex"
        )

      assert Exception.message(error) =~ "defined in unknown_option.ex:7"
      assert Exception.message(error) =~ "unknown options [:emit]"
      assert error.location[:location] == 7
    end
  end
end

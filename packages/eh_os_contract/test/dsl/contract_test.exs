defmodule EhOsContract.Next.ContractTest do
  @moduledoc """
  v2 plan, E4: **a v2 contract compiles to plain data** (v2 §9), whose version does
  not see declaration order.

  The fixtures are declared inside this file, as in `digest_test`: modules defined in
  a `.exs` are not in the application's module list, so the registry never sees them.
  Their domain, `EhOsContract.Next.ContractTest.Clinic`, does not exist, and that is
  the point of one test: `domain:` records no compile dependency (v2 §8).
  """

  use EhOsContract.DslCase, async: false

  alias EhOsContract.Model

  defmodule Golden do
    @moduledoc false
    use EhOsContract.Next.Contract,
      domain: EhOsContract.Next.ContractTest.Clinic,
      context: :settlement

    aggregate :visit, "Wizyta", source: "AGG-03" do
      identity :visit_id

      state do
        field :total, :money, optional: true
        field :payments, {:list, :money}, default: []
      end

      invariant :paid_in_full, "Zapłacono całość"

      command :record_payment, "Przyjęcie płatności", by: :reception, emits: :payment_recorded do
        field :amount, :money
      end

      command :close, "Zamknięcie",
        by: [:reception, :manager],
        emits: :closed,
        rejects: :paid_in_full

      stage :payment do
        event :payment_recorded, "Zapłacono" do
          field :amount, :money
        end

        event :closed, "Zamknięto", terminal: true
      end
    end

    process :visit, "Wizyta" do
      correlate :visit_id
      stage :payment
    end

    scenario "zapłacono za mało — zamknięcie odrzucone" do
      given :payment_recorded, %{amount: 100}
      command :close
      rejected :paid_in_full
    end
  end

  defmodule Reordered do
    @moduledoc false
    use EhOsContract.Next.Contract,
      domain: EhOsContract.Next.ContractTest.Clinic,
      context: :settlement

    process :visit, "Wizyta" do
      correlate :visit_id
      stage :payment
    end

    aggregate :visit, "Wizyta", source: "AGG-03" do
      identity :visit_id

      stage :payment do
        event :closed, "Zamknięto", terminal: true

        event :payment_recorded, "Zapłacono" do
          field :amount, :money
        end
      end

      command :close, "Zamknięcie",
        by: [:manager, :reception],
        emits: :closed,
        rejects: :paid_in_full

      command :record_payment, "Przyjęcie płatności", by: :reception, emits: :payment_recorded do
        field :amount, :money
      end

      invariant :paid_in_full, "Zapłacono całość"

      state do
        field :payments, {:list, :money}, default: []
        field :total, :money, optional: true
      end
    end

    scenario "zapłacono za mało — zamknięcie odrzucone" do
      given :payment_recorded, %{amount: 100}
      command :close
      rejected :paid_in_full
    end
  end

  defmodule Changed do
    @moduledoc false
    use EhOsContract.Next.Contract,
      domain: EhOsContract.Next.ContractTest.Clinic,
      context: :settlement

    aggregate :visit, "Wizyta", source: "AGG-03" do
      identity :visit_id

      state do
        field :total, :money, optional: true
        field :payments, {:list, :money}, default: []
      end

      invariant :paid_in_full, "Zapłacono całość"

      command :record_payment, "Przyjęcie płatności", by: :reception, emits: :payment_recorded do
        field :amount, :money
      end

      command :close, "Zamknięcie",
        by: [:reception, :manager],
        emits: :closed,
        rejects: :paid_in_full

      stage :payment do
        # The only difference from `Golden`: the amount is optional.
        event :payment_recorded, "Zapłacono" do
          field :amount, :money, optional: true
        end

        event :closed, "Zamknięto", terminal: true
      end
    end

    process :visit, "Wizyta" do
      correlate :visit_id
      stage :payment
    end

    scenario "zapłacono za mało — zamknięcie odrzucone" do
      given :payment_recorded, %{amount: 100}
      command :close
      rejected :paid_in_full
    end
  end

  @id %{name: :visit_id, type: :id, optional: false, label: nil, personal: nil, subject: nil}
  @amount %{name: :amount, type: :money, optional: false, label: nil, personal: nil, subject: nil}

  defp no_default(map), do: Map.put(map, :default, nil)

  describe "the model" do
    test "is the golden one" do
      assert Map.drop(Model.fetch(Golden), [:version, :digests]) == %{
               format: 1,
               kind: :contract,
               module: Golden,
               domain: EhOsContract.Next.ContractTest.Clinic,
               context: :settlement,
               process: %{
                 name: :visit,
                 label: "Wizyta",
                 correlate: [:visit_id],
                 accountable: nil,
                 stages: [%{name: :payment, label: nil}],
                 includes: [],
                 cadence: nil,
                 deadline: nil,
                 promises: []
               },
               units: [
                 %{
                   name: :visit,
                   kind: :aggregate,
                   label: "Wizyta",
                   source: "AGG-03",
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
                   invariants: [%{name: :paid_in_full, label: "Zapłacono całość", source: nil}]
                 }
               ],
               commands: [
                 %{
                   name: :record_payment,
                   unit: :visit,
                   label: "Przyjęcie płatności",
                   source: nil,
                   by: [:reception],
                   emits: [:payment_recorded],
                   rejects: [],
                   fields: [no_default(@id), no_default(@amount)]
                 },
                 %{
                   name: :close,
                   unit: :visit,
                   label: "Zamknięcie",
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
                   type: "visit.payment_recorded",
                   stage: :payment,
                   label: "Zapłacono",
                   terminal: false,
                   recorded_by: [],
                   depends_on: nil,
                   schema_version: 1,
                   source: nil,
                   fields: [no_default(@id), no_default(@amount)]
                 },
                 %{
                   name: :closed,
                   unit: :visit,
                   type: "visit.closed",
                   stage: :payment,
                   label: "Zamknięto",
                   terminal: true,
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
               consumes: [],
               publishes: [],
               scenarios: [
                 %{
                   description: "zapłacono za mało — zamknięcie odrzucone",
                   scope: nil,
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
               "process:visit",
               "scenario:*",
               "unit:visit"
             ]
    end

    test "holds no Spark struct and no source annotation" do
      refute inspect(Model.fetch(Golden), limit: :infinity) =~
               ~r/__spark_metadata__|__struct__|Spark\./
    end

    test "names its capabilities after the domain, which has to be compiled (D14)" do
      compile("""
      defmodule EhOsContract.Next.ContractTest.ClinicDomain do
        use EhOsContract.Domain, name: :clinic, language: :pl
      end

      defmodule EhOsContract.Next.ContractTest.Named do
        use EhOsContract.Next.Contract,
          domain: EhOsContract.Next.ContractTest.ClinicDomain,
          context: :settlement

        aggregate :visit, "Wizyta" do
          identity :visit_id
          command :close, "Zamknięcie", by: [:reception, :manager], emits: :closed
          event :closed, "Zamknięto", terminal: true
        end

        process :visit, "Wizyta" do
          correlate :visit_id
        end

        read_model :open_visits, "Otwarte wizyty", projects: :closed do
          field :clinic_id, :id
        end

        query :open_for_clinic, "Otwarte w przychodni", reads: :open_visits, by: :reception do
          param :clinic_id, :id
          scope :clinic_id
        end
      end
      """)

      assert Model.capabilities(EhOsContract.Next.ContractTest.Named) == %{
               "clinic.close" => %{
                 kind: :command,
                 name: :close,
                 roles: ["clinic.manager", "clinic.reception"],
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

    test "refuses capabilities for a domain that is not compiled, and for a v1 contract" do
      error = assert_raise ArgumentError, fn -> Model.capabilities(Golden) end

      assert error.message =~
               "names domain EhOsContract.Next.ContractTest.Clinic, which is not a compiled"

      # A module that exists and is no domain at all: named as such, not tried as a
      # v1 contract.
      error =
        assert_raise ArgumentError, fn ->
          Model.capabilities(%{Model.fetch(Golden) | domain: Enum})
        end

      assert error.message =~ "names domain Enum, which is not a compiled EhOsContract.Domain"

      error = assert_raise ArgumentError, fn -> Model.capabilities(ProcessShapes.Bare) end

      assert error.message =~
               "ProcessShapes.Bare is a v1 contract, which declares no capabilities"
    end

    test "is refused by the v1 accessors, by name" do
      error = assert_raise ArgumentError, fn -> Model.events(Golden) end
      assert error.message =~ "EhOsContract.Next.ContractTest.Golden is a v2 contract"
      refute Model.contract?(Golden)
    end
  end

  describe "the version" do
    test "does not move when declarations are written in another order, nested ones included" do
      assert Model.fetch(Golden).version == Model.fetch(Reordered).version
      assert Model.fetch(Golden).digests == Model.fetch(Reordered).digests
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
        defmodule EhOsContract.Next.ContractTest.#{name} do
          use EhOsContract.Next.Contract, domain: Clinic, context: :billing

          dcb :payer_period, "Okres płatnika" do
            identity #{inspect(identity)}
            consults :period_closed, match: :payer_id
            command :close_period, "Zamknięcie okresu", by: :manager, emits: :period_closed
            event :period_closed, "Zamknięto okres", terminal: true
          end

          process :billing, "Rozliczenie płatnika" do
            correlate #{inspect(identity)}
          end
        end
        """)

        Model.fetch(Module.concat(__MODULE__, name)).version
      end

      assert version.([:payer_id, :period_id]) != version.([:period_id, :payer_id])
    end
  end

  describe "the domain" do
    test "is named without being compiled or even existing (v2 §8)" do
      refute Code.ensure_loaded?(EhOsContract.Next.ContractTest.Clinic)
      assert Model.fetch(Golden).domain == EhOsContract.Next.ContractTest.Clinic
    end
  end

  describe "options beside a do block (D13) in the contract" do
    test "an unknown one points at the declaration's line" do
      error =
        compile_error(
          """
          defmodule EhOsContract.Next.ContractTest.UnknownOption do
            use EhOsContract.Next.Contract, domain: Clinic, context: :settlement

            aggregate :visit, "Wizyta" do
              identity :visit_id

              command :close, "Zamknięcie", by: :reception, emit: :closed do
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

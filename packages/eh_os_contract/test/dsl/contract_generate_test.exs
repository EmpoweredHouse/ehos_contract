defmodule EhOsContract.ContractGenerateTest do
  @moduledoc """
  v2 plan, E5: **the structs a contract generates** (v2 §5) — their fields, what they
  enforce, their types, and where they say they were defined.
  """

  use EhOsContract.DslCase, async: false

  alias EhOsContract.Model

  @fixtures EhOsContract.Fixtures

  # Line 4 of generate.ex is the first line of this body.
  @body """
    consumes EhOsContract.Fixtures.Booking, [:visit_booked, :visit_moved], as: [visit_moved: :rebooked]

    consumes "clinic.visit.closed.v1", as: :visit_closed do
      field :visit_id, :id
      field :closed_at, :timestamp
      field :note, :string, optional: true
    end

    aggregate :visit, "Wizyta" do
      identity :visit_id

      state do
        field :total, :money, optional: true
        field :payments, {:list, :money}, default: []
      end

      command :record_payment, "Przyjęcie płatności", by: :reception, emits: :payment_recorded do
        field :amount, :money
        field :note, :string, optional: true
      end

      event :payment_recorded, "Zapłacono" do
        field :amount, :money
        field :method, {:enum, [card: "Karta", cash: "Gotówka"]}
      end
    end

    process :visit, "Wizyta" do
      correlate :visit_id
    end

    process_manager :chase, "Pogoń" do
      correlate :visit_id

      state do
        field :due_at, :timestamp, optional: true
      end

      starts_on :payment_recorded, sets: :later
      on :visit_booked, issues: :record_payment
      timer :later, wait: {1, :day}, issues: :record_payment
      ends_on :rebooked
    end

    read_model :payments, "Płatności", projects: :payment_recorded do
      field :visit_id, :id
      field :amount, :money
    end

    query :payments_of, "Płatności wizyty", reads: :payments, by: :reception do
      param :visit_id, :id
      param :since, :date, optional: true
    end

    policy :remind, "Przypomnij", handles: [:rebooked, :visit_closed], issues: :record_payment
    effect :notify, "Powiadom", handles: :payment_recorded, idempotency: :downstream
  """

  setup_all do
    binaries = compile(contract("Generated", @body), "generated.ex")
    %{binaries: Map.new(binaries)}
  end

  defp generated(name), do: Module.concat([@fixtures, Generated | List.wrap(name)])

  describe "commands and events" do
    test "have the identity first, their fields, and __meta__; required fields are enforced" do
      command = generated([Commands, RecordPayment])

      assert command.__struct__() |> Map.from_struct() |> Map.keys() |> Enum.sort() ==
               [:__meta__, :amount, :note, :visit_id]

      assert %{visit_id: "w-1", amount: 100, note: nil, __meta__: nil} =
               struct!(command, visit_id: "w-1", amount: 100)

      error = assert_raise ArgumentError, fn -> struct!(command, visit_id: "w-1") end
      assert error.message =~ "the following keys must also be given"
      assert error.message =~ ":amount"
      refute error.message =~ ":note"

      assert struct!(generated([Events, PaymentRecorded]),
               visit_id: "w-1",
               amount: 1,
               method: :card
             )
    end

    test "type their fields, a domain value as a remote type of the domain's Values",
         %{binaries: binaries} do
      assert type(binaries, [Commands, RecordPayment]) ==
               "%EhOsContract.Fixtures.Generated.Commands.RecordPayment{" <>
                 "__meta__: EhOsContract.Meta.t() | nil, " <>
                 "amount: Clinic.Values.money(), " <>
                 "note: String.t() | nil, " <>
                 "visit_id: String.t()}"

      assert type(binaries, [Events, PaymentRecorded]) =~ "method: :card | :cash"
    end

    test "are defined at the line of their declaration", %{binaries: binaries} do
      assert line(binaries, [Commands, RecordPayment]) == 20
      assert line(binaries, [Events, PaymentRecorded]) == 25
      assert source(generated([Events, PaymentRecorded])) =~ "generated.ex"
    end
  end

  describe "states, rows and a query's parameters" do
    test "a state starts from its defaults, with the identity; nothing is enforced" do
      assert %{visit_id: nil, total: nil, payments: []} =
               struct(generated([Aggregates, Visit, State]))

      # A process manager's run is told by its correlation, as a unit's by its identity.
      assert %{visit_id: nil, due_at: nil} = struct(generated([ProcessManagers, Chase, State]))
      refute Map.has_key?(struct(generated([Aggregates, Visit, State])), :__meta__)
    end

    test "a read model's row and a query's parameters are plain structs", %{binaries: binaries} do
      assert %{visit_id: nil, amount: nil} = struct(generated([ReadModels, Payments, Row]))
      assert %{visit_id: nil, since: nil} = struct(generated([Queries, PaymentsOf]))

      assert type(binaries, [Queries, PaymentsOf]) =~
               "since: Date.t() | nil, visit_id: String.t() | nil}"
    end
  end

  test "a process manager's correlation has the type a local event gives it" do
    # A domain value, which F8 lets a correlation be when it rests on :id (L3); the
    # domain here is not compiled, so only the generated type is under test.
    binaries =
      "Periods"
      |> contract("""
        aggregate :month, "Miesiąc" do
          identity :company_id

          command :open_month, "Otwarcie", by: :accountant, emits: :month_opened do
            field :period, :period
          end

          event :month_opened, "Otwarto" do
            field :period, :period
          end
        end

        process :month, "Miesiąc" do
          correlate :company_id
        end

        process_manager :reminders, "Przypomnienia" do
          correlate [:company_id, :period]
          starts_on :month_opened
          ends_on :month_opened
        end
      """)
      |> compile("periods.ex")
      |> Map.new()

    state = Module.concat([@fixtures, Periods, ProcessManagers, Reminders, State])
    {:ok, [{:type, t}]} = binaries |> Map.fetch!(state) |> Code.Typespec.fetch_types()
    type = t |> Code.Typespec.type_to_quoted() |> Macro.to_string()

    assert type =~ "company_id: String.t() | nil"
    assert type =~ "period: Clinic.Values.period() | nil"
  end

  describe "consumed events" do
    test "one received from another application is a struct of the fields declared for it" do
      received = generated([Received, VisitClosed])

      assert %{visit_id: "w-1", closed_at: _, note: nil, __meta__: nil} =
               struct!(received, visit_id: "w-1", closed_at: ~U[2026-09-01 09:00:00Z])

      assert Model.module_for(generated([]), :event, :visit_closed) == received
    end

    test "one from a sibling is the sibling's own struct, under its name there" do
      model = Model.fetch(generated([]))
      refute Code.ensure_loaded?(generated([Events, VisitBooked]))

      assert Model.module_for(model, :event, :visit_booked) ==
               EhOsContract.Fixtures.Booking.Events.VisitBooked

      assert Model.module_for(model, :event, :rebooked) ==
               EhOsContract.Fixtures.Booking.Events.VisitMoved
    end

    test "Model.consumed/2 says where each comes from, by the name it has here" do
      model = Model.fetch(generated([]))
      booking = EhOsContract.Fixtures.Booking

      assert Model.consumed(model, :visit_booked) == {:contract, booking, :visit_booked}
      assert Model.consumed(model, :rebooked) == {:contract, booking, :visit_moved}
      assert {:published, [%{name: :visit_id} | _]} = Model.consumed(model, :visit_closed)

      # A local event, and a sibling's under the name the rename replaced, are not consumed.
      assert Model.consumed(model, :payment_recorded) == nil
      assert Model.consumed(model, :visit_moved) == nil
    end
  end

  describe "behaviours" do
    test "a unit has one callback per command, and evolve/2 for the state it declares" do
      assert callbacks([Aggregates, Visit]) == [evolve: 2, record_payment: 2]
    end

    test "a reaction has one per event it handles, a process manager one per reaction that issues" do
      assert callbacks([Policies, Remind]) == [rebooked: 1, visit_closed: 1]
      assert callbacks([Effects, Notify]) == [payment_recorded: 1]
      assert callbacks([ProcessManagers, Chase]) == [evolve: 2, later: 1, visit_booked: 2]
      assert callbacks([ReadModels, Payments]) == [forget: 2, payment_recorded: 1, reset: 0]
    end

    test "a read model's reset/0 and forget/2 are optional, and the only optional callbacks anywhere" do
      # forget/2 from E8: optional to compile, required at boot of a read model that
      # projects personal data (`EhOsContract.Personal.check_forgetting!/1`).
      assert Enum.sort(generated([ReadModels, Payments]).behaviour_info(:optional_callbacks)) ==
               [forget: 2, reset: 0]

      for module <- [
            [Aggregates, Visit],
            [Policies, Remind],
            [Effects, Notify],
            [ProcessManagers, Chase]
          ] do
        assert generated(module).behaviour_info(:optional_callbacks) == []
      end
    end

    test "a query's callback sits with its parameters" do
      assert callbacks([Queries, PaymentsOf]) == [payments_of: 2]
    end

    test "the types name the generated structs, a sibling's own, and what a decision returns",
         %{binaries: binaries} do
      assert spec(binaries, [Aggregates, Visit], :record_payment) ==
               "record_payment(EhOsContract.Fixtures.Generated.Commands.RecordPayment.t(), " <>
                 "EhOsContract.Fixtures.Generated.Aggregates.Visit.State.t()) :: " <>
                 "{:ok, [struct()]} | {:error, EhOsContract.Rejection.t()}"

      assert spec(binaries, [ProcessManagers, Chase], :evolve) =~
               "EhOsContract.Fixtures.Generated.Events.PaymentRecorded.t() | " <>
                 "EhOsContract.Fixtures.Booking.Events.VisitBooked.t() | " <>
                 "EhOsContract.Fixtures.Booking.Events.VisitMoved.t()"

      # Another application's event only a policy takes (D12).
      assert spec(binaries, [Policies, Remind], :visit_closed) =~
               "EhOsContract.Fixtures.Generated.Received.VisitClosed.t()"

      assert spec(binaries, [Queries, PaymentsOf], :payments_of) =~
               ":: [EhOsContract.Fixtures.Generated.ReadModels.Payments.Row.t()]"
    end
  end

  describe "Model.module_for/3" do
    test "names the behaviours of units and reactions" do
      model = Model.fetch(generated([]))
      assert Model.module_for(model, :aggregate, :visit) == generated([Aggregates, Visit])

      assert Model.module_for(model, :process_manager, :chase) ==
               generated([ProcessManagers, Chase])

      assert Model.module_for(model, :read_model, :payments) == generated([ReadModels, Payments])
    end

    test "refuses what the contract does not declare" do
      error =
        assert_raise ArgumentError, fn -> Model.module_for(generated([]), :command, :close) end

      assert error.message == "#{inspect(generated([]))} declares no command :close"

      error = assert_raise ArgumentError, fn -> Model.module_for(generated([]), :dcb, :visit) end
      assert error.message =~ "declares no dcb :visit"
    end
  end

  # --- reading a binary compiled from a string ---------------------------------------

  # A map type's fields come back sorted by name: that is how Erlang stores them.
  defp type(binaries, name) do
    {:ok, [{:type, t}]} = binaries |> Map.fetch!(generated(name)) |> Code.Typespec.fetch_types()

    t
    |> Code.Typespec.type_to_quoted()
    |> Macro.to_string()
    |> String.replace(~r/\s*\n\s*/, " ")
    |> String.replace("{ ", "{")
    |> String.replace(" }", "}")
    |> String.replace_prefix("t() :: ", "")
  end

  defp callbacks(name), do: generated(name).behaviour_info(:callbacks) |> Enum.sort()

  defp spec(binaries, module, name) do
    {:ok, callbacks} =
      binaries |> Map.fetch!(generated(module)) |> Code.Typespec.fetch_callbacks()

    [spec] = for {{^name, _}, [spec]} <- callbacks, do: spec

    name
    |> Code.Typespec.spec_to_quoted(spec)
    |> Macro.to_string()
    |> String.replace(~r/\s*\n\s*/, " ")
    |> String.replace("( ", "(")
    |> String.replace(" )", ")")
  end

  # The line a module says it was defined at, which is where going to its definition
  # lands. Read from the debug chunk: a test compiles without docs.
  defp line(binaries, name) do
    {:ok, {_, [debug_info: {:debug_info_v1, :elixir_erl, {:elixir_v1, info, _}}]}} =
      binaries |> Map.fetch!(generated(name)) |> :beam_lib.chunks([:debug_info])

    :erl_anno.line(info.anno)
  end

  defp source(module), do: module.module_info(:compile)[:source] |> to_string()
end

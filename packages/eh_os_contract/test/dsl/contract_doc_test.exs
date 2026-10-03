defmodule EhOsContract.ContractDocTest do
  @moduledoc """
  Plan EP3: **the prose reaches the code.** A generated behaviour's callbacks carry
  what the contract says of them — label, source, what they may produce, the rules
  that hold there with the rung each stands on, and the scenarios they run — and its
  `@moduledoc` the declaration's label, source and rules.
  """

  use EhOsContract.DslCase, async: false

  alias EhOsContract.Contract.Doc

  @body """
    consumes "rehmed.visit.arrived.v1", as: :arrived do
      field :visit_id, :id
    end

    aggregate :visit, "Wizyta", source: "AGG-03" do
      identity :visit_id

      state do
        field :paid, :boolean, default: false
      end

      invariant :paid_in_full, "Zapłacono całość", source: "E-12"

      command :close, "Zamknięcie", by: :reception, emits: :closed, rejects: :paid_in_full,
        source: "C-04"

      command :pay, "Płatność", by: :reception, emits: :paid, rejects: :positive do
        field :amount, :integer
        constraint :positive, "Kwota jest dodatnia"
      end

      command :remind, "Przypomnienie", emits: :reminded

      event :closed, "Zamknięto", terminal: true
      event :paid, "Zapłacono" do
        field :amount, :integer
      end
      event :reminded, "Przypomniano"
    end

    policy :remind_on_arrival, "Przypomnij po przyjściu", handles: :arrived, issues: :remind,
      source: "P-01" do
      constraint :once, "Jedno przypomnienie na wizytę"
      constraint :quiet, "Nie w nocy"
    end

    effect :notify, "Powiadom", handles: :closed, idempotency: :event_id do
      constraint :limits, "Adapter trzyma limity"
    end

    process_manager :chase, "Pogoń" do
      correlate :visit_id
      starts_on :paid, sets: :due
      timer :due, wait: {1, :day}, issues: :remind
      ends_on :closed
      invariant :one_timer, "Jedno przypomnienie naraz"
    end

    read_model :visits, "Wizyty", projects: :closed do
      field :visit_id, :id
    end

    query :visits_of, "Wizyty recepcji", reads: :visits, by: :reception do
      param :visit_id, :id
      constraint :own_clinic, "Tylko swoja przychodnia"
    end

    process :visit, "Wizyta" do
      correlate :visit_id
    end

    scenario "niezapłacona — zamknięcie odrzucone" do
      command :close
      rejected :paid_in_full
    end

    scenario "zapłacona — zamknięta" do
      given :paid, %{amount: 100}
      command :close
      expect :closed
    end

    scenario "zero zł — odmowa" do
      command :pay, %{amount: 0}
      rejected :positive
    end

    scenario "przyszedł — przypomnienie", illustrates: :once do
      on :arrived, %{visit_id: "visit-anna"}
      issues :remind
    end

    scenario "przypomnienie po dniu", illustrates: :one_timer do
      on :due
      issues :remind
    end
  """

  setup_all do
    %{model: compile_contract("DocVisits", @body)}
  end

  test "a command's callback: what it emits, the rules it refuses on and where, its scenarios",
       %{model: model} do
    assert Doc.callback(model, :aggregate, :visit, :close) == """
           Decides command `close` — "Zamknięcie" (source: C-04).

           Emits, when it accepts:
           - `closed` — "Zamknięto"

           Refuses with `reject/1` on:
           - invariant `paid_in_full` — "Zapłacono całość" (source: E-12) — refused in "niezapłacona — zamknięcie odrzucone"

           Scenarios:
           - "niezapłacona — zamknięcie odrzucone": rejected on `paid_in_full`
           - "zapłacona — zamknięta": emits `closed`\
           """

    assert Doc.callback(model, :aggregate, :visit, :pay) =~
             ~s|- constraint `positive` — "Kwota jest dodatnia" — refused in "zero zł — odmowa"|
  end

  test "a policy's callback: the event, where it comes from, what it issues, each rule's rung",
       %{model: model} do
    assert Doc.callback(model, :policy, :remind_on_arrival, :arrived) == """
           Reacts to `arrived` (received from another application as `rehmed.visit.arrived.v1`), for policy `remind_on_arrival` — "Przypomnij po przyjściu" (source: P-01).

           May issue:
           - `remind` — "Przypomnienie"

           Keeps:
           - constraint `once` — "Jedno przypomnienie na wizytę" — illustrated by "przyszedł — przypomnienie"
           - constraint `quiet` — "Nie w nocy" — prose alone: no scenario shows it yet

           Scenarios:
           - "przyszedł — przypomnienie": issues `remind`\
           """
  end

  test "a process manager's timer, an effect, a read model, a query and evolve", %{model: model} do
    timer = Doc.callback(model, :process_manager, :chase, :due)
    assert timer =~ ~s|Fires on timer `due` of process manager `chase` — "Pogoń".|
    assert timer =~ ~s|- invariant `one_timer` — "Jedno przypomnienie naraz" — illustrated by|

    assert Doc.callback(model, :effect, :notify, :closed) =~
             ~s|- constraint `limits` — "Adapter trzyma limity" — prose alone: no scenario runs an effect|

    assert Doc.callback(model, :read_model, :visits, :closed) ==
             ~s|Projects `closed` — "Zamknięto" into read model `visits` — "Wizyty".|

    assert Doc.callback(model, :query, :visits_of, :visits_of) =~
             ~s|- constraint `own_clinic` — "Tylko swoja przychodnia" — prose alone: no scenario shows it yet|

    assert Doc.evolve([:closed, :paid]) ==
             "Folds an event into the state, so the next decision sees it: `closed`, `paid`."
  end

  test "a behaviour's moduledoc: the sentence, then the declaration and its rules", %{
    model: model
  } do
    assert Doc.moduledoc(model, :aggregate, :visit, "How it is bound.") == """
           How it is bound.

           Aggregate `visit` — "Wizyta" (source: AGG-03).

           Rules:
           - invariant `paid_in_full` — "Zapłacono całość" (source: E-12) — refused in "niezapłacona — zamknięcie odrzucone"\
           """
  end

  test "the generated behaviours carry the docs, compiled into the module" do
    {:docs_v1, _, _, _, %{"en" => moduledoc}, _, docs} =
      Code.fetch_docs(DispatchRig.Ledger.Aggregates.Account)

    assert moduledoc =~ "Aggregate `account`"

    callback_docs = for {{:callback, _, _}, _, _, %{"en" => doc}, _} <- docs, do: doc
    assert callback_docs != []
    assert Enum.all?(callback_docs, &(&1 =~ ~r/^(Decides command|Folds an event)/))
  end
end

defmodule EhosContract.ContractDocTest do
  @moduledoc """
  Plan EP3: **the prose reaches the code.** A generated behaviour's callbacks carry
  what the contract says of them — label, source, what they may produce, the rules
  that hold there with the rung each stands on, and the scenarios they run — and its
  `@moduledoc` the declaration's label, source and rules.
  """

  use EhosContract.DslCase, async: false

  alias EhosContract.Contract.Doc

  @body """
    subscribe "clinic.visit.arrived.v1", as: :arrived do
      field :visit_id, :id
    end

    aggregate :visit, "Visit", source: "U-04" do
      identity :visit_id

      state do
        field :paid, :boolean, default: false
      end

      invariant :paid_in_full, "Paid in full", source: "R-17"

      command :close, "Closing", by: :reception, emits: :closed, rejects: :paid_in_full,
        source: "K-09"

      command :pay, "Payment", by: :reception, emits: :paid, rejects: :positive do
        field :amount, :integer
        constraint :positive, "The amount is positive"
      end

      command :remind, "Reminder", emits: :reminded

      command :cancel, "Cancellation", by: :reception, emits: :cancelled, rejects: :paid_in_full

      event :closed, "Closed"
      event :paid, "Paid" do
        field :amount, :integer
      end
      event :reminded, "Reminded"
      event :cancelled, "Cancelled"
    end

    policy :remind_on_arrival, "Remind on arrival", handles: :arrived, issues: :remind,
      source: "S-03" do
      constraint :once, "One reminder per visit"
      constraint :quiet, "Not at night"
    end

    effect :notify, "Notify", handles: :closed, idempotency: [key: :event_id, owner: :self] do
      constraint :limits, "The adapter keeps the limits"
    end

    process_manager :chase, "Chase" do
      correlate :visit_id
      starts_on :paid, sets: :due, issues: :remind
      timer :due, "Due", wait: {1, :day}, issues: :remind, source: "W1-07"
      ends_on :closed
      invariant :one_timer, "One reminder at a time"
    end

    read_model :visits, "Visits", projects: :closed do
      field :visit_id, :id
    end

    query :visits_of, "Reception's visits", reads: :visits, by: :reception do
      param :visit_id, :id
      constraint :own_clinic, "Only one's own clinic"
    end

    domain_service :pricing, "Price list" do
      function :price, "Price" do
        argument :minutes, :integer
        returns :integer
        rule :rounded, "Rounded", examples: [{[1], 1}, {[2], 2}]
      end
    end

    scenario "unpaid — cancellation refused" do
      command :cancel
      rejected :paid_in_full
    end

    scenario "paid — closed" do
      given :paid, %{amount: 100}
      command :close
      expect :closed
    end

    scenario "zero amount — refused" do
      command :pay, %{amount: 0}
      rejected :positive
    end

    scenario "arrived — reminder", illustrates: :once do
      on :arrived, %{visit_id: "visit-anna"}
      issues :remind
    end

    scenario "payment — reminder and timer" do
      on :paid, %{amount: 100}
      sets :due
      issues :remind
    end

    scenario "reminder after a day", illustrates: :one_timer do
      on :due
      issues :remind
    end
  """

  setup_all do
    %{model: compile_contract("DocVisits", @body)}
  end

  # An invariant is shown by a scenario of any command refused on it (S8), so `close`,
  # with no rejecting scenario of its own, points at `cancel`'s (the EP3 review).
  test "a command's callback: what it emits, the rules it refuses on and where, its scenarios",
       %{model: model} do
    assert Doc.callback(model, :aggregate, :visit, :close) == """
           Decides command `close` — "Closing" (source: K-09).

           Emits, when it accepts:
           - `closed` — "Closed"

           Refuses with `reject/1` on:
           - invariant `paid_in_full` — "Paid in full" (source: R-17) — refused in "unpaid — cancellation refused"

           Scenarios:
           - "paid — closed": emits `closed`\
           """

    assert Doc.callback(model, :aggregate, :visit, :pay) =~
             ~s|- constraint `positive` — "The amount is positive" — refused in "zero amount — refused"|
  end

  # Issue #430's review: a recording is refused on a value's invariant, so one named like
  # the unit's shows nothing of the unit's.
  test "a recording refused on a name the unit's invariant shares is not where it is refused" do
    body =
      @body
      |> String.replace(
        ~s|event :cancelled, "Cancelled"|,
        ~s|event :cancelled, "Cancelled"\n      event :counted, "Counted", recorded_by: :till|
      )
      |> Kernel.<>("""

        scenario "counted below zero" do
          actor :till
          record :counted
          rejected :paid_in_full
        end
      """)

    model = compile_contract("DocRecorded", body)

    assert Doc.callback(model, :aggregate, :visit, :close) =~
             ~s|— refused in "unpaid — cancellation refused"\n|
  end

  # Issue #458: a command refused for its data is refused on a value's invariant, so one
  # named like the unit's shows nothing of the unit's either.
  test "a command refused for its data on a name the unit's invariant shares is not where it is refused" do
    body =
      @body
      |> String.replace(
        ~s|event :cancelled, "Cancelled"|,
        ~s|event :cancelled, "Cancelled"\n      command :tip, "Tip", by: :reception, emits: :paid do\n        field :amount, :tip\n      end|
      )
      |> Kernel.<>("""

        scenario "a tip that breaks a tip's own rule" do
          command :tip, %{amount: 1}
          rejected :paid_in_full
        end
      """)

    model = compile_contract("DocRefusedForData", body)

    assert Doc.callback(model, :aggregate, :visit, :close) =~
             ~s|— refused in "unpaid — cancellation refused"\n|
  end

  test "a policy's callback: the event, where it comes from, what it issues, each rule's rung",
       %{model: model} do
    assert Doc.callback(model, :policy, :remind_on_arrival, :arrived) == """
           Reacts to `arrived` (received from another application as `clinic.visit.arrived.v1`), for policy `remind_on_arrival` — "Remind on arrival" (source: S-03).

           May issue:
           - `remind` — "Reminder"

           Keeps:
           - constraint `once` — "One reminder per visit" — illustrated by "arrived — reminder"
           - constraint `quiet` — "Not at night" — prose alone: no scenario shows it yet

           Scenarios:
           - "arrived — reminder": issues `remind`\
           """
  end

  test "a process manager's timer and reaction, an effect, a read model, a query, a service and evolve",
       %{model: model} do
    assert Doc.callback(model, :process_manager, :chase, :due) == """
           Fires on timer `due` — "Due" (source: W1-07) of process manager `chase` — "Chase".

           May issue:
           - `remind` — "Reminder"

           Keeps:
           - invariant `one_timer` — "One reminder at a time" — illustrated by "reminder after a day"

           Scenarios:
           - "reminder after a day": issues `remind`\
           """

    assert Doc.callback(model, :process_manager, :chase, :paid) =~
             ~s|Reacts to `paid` — "Paid", for process manager `chase` — "Chase".\n\n| <>
               ~s|May issue:\n- `remind` — "Reminder"|

    assert Doc.callback(model, :domain_service, :pricing, :price) == """
           Function `price` — "Price" of domain service `pricing`.

           Keeps:
           - rule `rounded` — "Rounded" — 2 examples, each a test\
           """

    assert Doc.callback(model, :effect, :notify, :closed) =~
             ~s|- constraint `limits` — "The adapter keeps the limits" — prose alone: no scenario runs an effect|

    assert Doc.callback(model, :read_model, :visits, :closed) ==
             ~s|Projects `closed` — "Closed" into read model `visits` — "Visits".|

    assert Doc.callback(model, :query, :visits_of, :visits_of) =~
             ~s|- constraint `own_clinic` — "Only one's own clinic" — prose alone: no scenario shows it yet|

    assert Doc.evolve(:aggregate, [:closed, :paid]) ==
             "Folds an event into the state, so the next decision sees it: `closed`, `paid`."

    assert Doc.evolve(:process_manager, [:paid]) ==
             "Folds an event into the state, so the next reaction sees it: `paid`."
  end

  test "a behaviour's moduledoc: the sentence, then the declaration and its rules", %{
    model: model
  } do
    assert Doc.moduledoc(model, :aggregate, :visit, "How it is bound.") == """
           How it is bound.

           Aggregate `visit` — "Visit" (source: U-04).

           Rules:
           - invariant `paid_in_full` — "Paid in full" (source: R-17) — refused in "unpaid — cancellation refused"
           - constraint `positive` — "The amount is positive" — of command `pay`, refused in "zero amount — refused"\
           """
  end

  test "the generated behaviours carry the docs, compiled into the module" do
    {:docs_v1, _, _, _, %{"en" => moduledoc}, _, docs} =
      Code.fetch_docs(DispatchRig.Ledger.Aggregates.Account)

    assert moduledoc =~ "Aggregate `account`"

    callback_docs = for {{:callback, _, _}, _, _, %{"en" => doc}, _} <- docs, do: doc
    assert callback_docs != []
    assert Enum.all?(callback_docs, &(&1 =~ ~r/^(Decides command|Folds an event)/))

    # A boundary is named in words, and a query's module, which is its behaviour too,
    # says what the contract says of the query (the EP3 review).
    {:docs_v1, _, _, _, %{"en" => boundary}, _, _} =
      Code.fetch_docs(BoundaryRig.Enrolment.Dcbs.Seat)

    assert boundary =~ "Dynamic consistency boundary `seat`"

    {:docs_v1, _, _, _, %{"en" => query}, _, _} =
      Code.fetch_docs(DispatchRig.Ledger.Queries.BalancesForBranch)

    assert query =~ ~s|Query `balances_for_branch` — "Balances of one branch"|
  end
end

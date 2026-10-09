defmodule EhOsContract.Check.Catalog do
  # Every rule `mix eh_os_contract.check` reports on, under a name that does not
  # change (layer L5 of v2 §6; plan EL1).
  #
  # A rule's name is what a reader searches for, what `--format json` carries, and
  # what a test pins; its sentence may be reworded, its name may not. Where the rule
  # is one of ESDM's, the name is ESDM's, without ESDM's `esdm/<category>/` prefix:
  # the library takes ESDM's functionality, not its namespace, and a rule of ours
  # sometimes means more or less than ESDM's does — `esdm` says which of ESDM's it
  # follows and the text says where it differs. The level is fixed per rule, as in
  # ESDM, and nothing silences one: a finding goes away when the model changes.
  #
  # `docs/rules.md` is generated from this list (by `eh_os_contract.rules`, a task of
  # the package's own `dev/`, not shipped), one
  # entry per rule, and each finding links to its entry.
  #
  # The rules of the compiler — `N1`, `X2` and the rest of L2 and L3 — are not here.
  # They are errors a contract cannot compile with, they keep the codes they are
  # printed with, and v2 §6 is their reference.
  @moduledoc false

  @typedoc """
  One rule: its name, its level, the ESDM rule it follows
  (`nil` when it is the library's own), one line saying what it finds, and the
  paragraph `docs/rules.md` prints under it.
  """
  @type rule :: %{
          id: String.t(),
          level: :error | :warn | :info,
          esdm: String.t() | nil,
          summary: String.t(),
          text: String.t()
        }

  @rules [
    %{
      id: "no-contracts",
      level: :warn,
      esdm: nil,
      summary: "The applications `check` scans hold no contract.",
      text: """
      A clean report and a scan of the wrong application print the same thing, `0 errors, 0 warnings,
      0 notices`. This is the one finding that tells them apart. Set `config :eh_os_contract,
      applications: [...]` to the applications holding the contracts.
      """
    },
    %{
      id: "process-without-accountable",
      level: :warn,
      esdm: nil,
      summary: "A process names no `accountable` role.",
      text: """
      A finding about the process — a promise broken, a path never taken — has nobody to go to. Name
      the role that answers for the process with `accountable`.
      """
    },
    %{
      id: "unverified-declaration",
      level: :warn,
      esdm: nil,
      summary: "A `deadline` or a promise is marked `unverified: true`.",
      text: """
      The process owner has not confirmed the number. It is still evaluated, but it does not count
      towards the evidence report, because a metric nobody agreed to is worse than none. Remove
      `unverified: true` once the owner confirms it.
      """
    },
    %{
      id: "promise-without-within",
      level: :info,
      esdm: nil,
      summary: "A promise has no `within`.",
      text: """
      Any `eventually` after its `from` keeps it, and a run with none stays pending for ever, so the
      promise has no failing case. That is an honest thing to say when nobody agreed a number; the
      notice makes sure it is not read as a promise being kept.
      """
    },
    %{
      id: "deadline-without-terminal-event",
      level: :info,
      esdm: nil,
      summary: "A process has a `deadline` and no event of it is `terminal: true`.",
      text: """
      No run can be seen to end, so its duration cannot be measured and the deadline is never kept
      or broken. Mark the event that ends a run `terminal: true`.
      """
    },
    %{
      id: "contract-without-implementation",
      level: :info,
      esdm: nil,
      summary: "Nothing implements a contract.",
      text: """
      A contract may exist without code: nothing of it can be dispatched, and its report
      is of a process nobody runs. A unit made only of events entering through `record/3` needs no
      implementation and does not cause this notice.
      """
    },
    %{
      id: "in-transaction-policy-fan-out",
      level: :warn,
      esdm: nil,
      summary: "A scenario shows an in-transaction policy issuing more than one command.",
      text: """
      Every command is dispatched while the transaction that recorded the triggering event holds the
      store's global append lock. A scenario issuing more than one proves that the policy fans out and
      makes every other append wait for the whole list. Deliver fan-out `:at_least_once`; the ordered
      subscription gives each command its idempotent key without extending the original transaction.
      """
    },
    %{
      id: "scoped-actor-with-unscoped-command",
      level: :warn,
      esdm: nil,
      summary: "An actor with scope dimensions may issue an unscoped command.",
      text: """
      The actor's other grants can be narrowed to named dimensions, but this command's capability is
      application-wide. Declare the command's `scope` when it acts on one of those dimensions, or use
      a different actor when application-wide authority is deliberate.
      """
    },
    %{
      id: "declaration-without-implementation",
      level: :warn,
      esdm: nil,
      summary: "A contract is implemented in part.",
      text: """
      The unit, consumer, query or domain service the finding names has no implementation, so
      dispatch refuses to run it. Add a module with `use <Contract>, <kind>: <name>`.
      """
    },
    %{
      id: "value-without-implementation",
      level: :warn,
      esdm: nil,
      summary: "A value declares invariants, and no module checks them.",
      text: """
      Dispatch holds every value of the type to its invariants, so a command, an event or
      a query carrying one raises without the code that checks them. Add a module with
      `use <Domain>, value: <name>`. Said only of a domain some contract of which is implemented:
      a domain whose contracts have no code yet has nothing to run either.
      """
    },
    %{
      id: "competing-in-transaction-consumers",
      level: :warn,
      esdm: nil,
      summary: "Two or more reactions take one event inside the transaction that records it.",
      text: """
      Policies and effects delivered `:in_transaction`, of this contract or of any that consumes the
      event, run one after another in an order the contract does not state. If one depends on what
      the other does, have it react to the event the other decides, so the order is a path the
      process shows. Read models are not counted: they decide nothing.
      """
    },
    %{
      id: "in-transaction-across-contexts",
      level: :warn,
      esdm: nil,
      summary:
        "A reaction to another context's event runs inside the transaction that records it.",
      text: """
      A policy, an effect or a read model declared `delivery: :in_transaction` on an event of a
      sibling contract of another context runs in the transaction that records the event, so the
      two contexts commit together and the reaction's failure rolls the other context's fact back.
      Contexts usually agree eventually: `:at_least_once` — a policy and an effect with their
      `idempotency` (P3), a read model with none. A policy or a read model left without `delivery`
      there does not compile (X10), so for them this warning is only ever about one declared on
      purpose; say why in the pull request.
      """
    },
    %{
      id: "free-text-not-personal",
      level: :info,
      esdm: nil,
      summary: "A `:string` field of an event is not `personal:`.",
      text: """
      `:string` is text a person typed. Unless it is marked `personal:` it is not sealed with its
      subject's key and stays in the log as written after the subject is erased. A code, a
      number or a choice has a type of its own.
      """
    },
    %{
      id: "emits-never-produced",
      level: :warn,
      esdm: nil,
      summary: "A command may emit an event that no `emit/1` of its implementation names.",
      text: """
      The contract says the command can decide the event, and no path of the code does: either the
      declaration is wider than the decision, or the decision returns the event without `emit/1`,
      which nothing checks until dispatch. An `emit/1` in a helper function counts for every command
      of the unit, since nothing says which one calls it.
      """
    },
    %{
      id: "aggregate-without-events",
      level: :warn,
      esdm: "esdm/modeling/aggregate-without-events",
      summary: "A unit declares no event.",
      text: """
      A command has to emit (A1), so a unit with no event has no command either and can decide
      nothing. A boundary is held to this too. ESDM's `aggregate-without-commands` is not a rule here:
      a unit whose events are all `recorded_by:` has no command on purpose.
      """
    },
    %{
      id: "event-without-consumer",
      level: :warn,
      esdm: "esdm/modeling/event-without-consumer",
      summary: "Nothing reacts to or reads an event.",
      text: """
      No policy, effect or process manager takes it, no read model projects it, no boundary consults
      it, no contract consumes it and no `publish` sends it. Unlike ESDM, an event a promise names, one
      marked `terminal: true`, one a unit's lifecycle starts on or moves on, or one a process module
      includes, has a reader: the conformance report. The unit's own `evolve` does not count, as ESDM's aggregate does not.
      """
    },
    %{
      id: "read-model-without-query",
      level: :warn,
      esdm: "esdm/modeling/read-model-without-query",
      summary: "No query reads a read model.",
      text: """
      A read model nobody can ask is kept for nothing: every event it projects costs a write no answer
      ever reads.
      """
    },
    %{
      id: "process-manager-without-ends-on",
      level: :warn,
      esdm: "esdm/modeling/process-manager-without-ends-when",
      summary: "A process manager declares no `ends_on`.",
      text: """
      Every run it starts stays open for ever, and its state is kept for ever with it. ESDM's name for
      the same rule says `ends-when`, after its own key.
      """
    },
    %{
      id: "process-manager-without-event-reactions",
      level: :warn,
      esdm: "esdm/modeling/process-manager-without-event-reactions",
      summary: "A process manager reacts only to its own timers after it starts.",
      text: """
      It has timers and no `on` that names an event, so once it runs, what happens in the process can
      end it (`ends_on`, which is not a reaction, as ESDM's `endsWhen` is not) and not steer it: it is
      a schedule, and may be simpler as one.
      """
    },
    %{
      id: "event-name-with-aggregate-prefix",
      level: :warn,
      esdm: "esdm/modeling/event-name-with-aggregate-prefix",
      summary: "An event's name starts with the name of its unit.",
      text: """
      `visit_closed` in the unit `visit`: the unit is where the event is declared and its type carries
      the process, so the prefix says twice what the name should not have to. Name what happened.
      """
    },
    %{
      id: "reaction-without-scenario",
      level: :warn,
      esdm: "esdm/gwt/feature-without-scenarios",
      summary: "No scenario runs a policy, a process manager or a query.",
      text: """
      Its label says what it does, and nothing shows its implementation does it: a scenario on the
      event it takes, with what it `issues`, or a query with what it `answers`, is the test that would.
      ESDM asks this of a feature; here of each declaration a scenario can run. An effect is left out,
      since its outcome is outside the log and no scenario can name it (S6). A warning, where an
      invariant without a rejecting scenario is an error (S8): the scenario is the only proof an
      invariant holds, and a reaction is also checked on the log by the conformance report.
      """
    },
    %{
      id: "transition-without-scenario",
      level: :warn,
      esdm: nil,
      summary: "No scenario takes a declared transition of a unit's lifecycle.",
      text: """
      The lifecycle says the unit moves from one status to another on an event, and nothing shows the
      implementation decides that event there. A scenario of a command whose `given` leaves the unit in
      the transition's `from` status, and which expects the event, is the test that would; one with
      `rejected` decides nothing and does not count. A transition from several statuses needs a
      scenario from each. A transition on an event no command of the unit emits is left out: it is
      recorded, with no decision for a scenario to run. So is a `from` status no such command's
      `from:` admits: no scenario could start there. A warning: the dispatcher still holds every
      decision to the graph, and the conformance report counts each transition the log takes.
      """
    },
    %{
      id: "prose-without-scenario",
      level: :warn,
      esdm: nil,
      summary:
        "No scenario illustrates a constraint of a policy, a process manager or a query, or an " <>
          "invariant of a process manager.",
      text: """
      The rule is prose alone, the first rung of the contract's ladder: it tells whoever writes the
      implementation what to keep, and nothing shows the implementation keeps it. A scenario of the
      declaration that names it in `illustrates:` is the test that would. An effect's constraint is
      left out, as `reaction-without-scenario` leaves out the effect: no scenario runs an effect (S6),
      so its prose has no rung above. So is a declaration no scenario runs at all, which
      `reaction-without-scenario` reports already. A warning, not an error like S8: the prose still
      tells the implementation what to keep, and a reaction is also checked on the log by the
      conformance report.
      """
    },
    %{
      id: "consults-without-match",
      level: :warn,
      esdm: nil,
      summary: "A boundary consults an event by `where:` alone.",
      text: """
      Without `match:` the boundary reads every event of that type, whoever it is about, and any new
      one conflicts with its decision, so under load most decisions are retried or refused with
      `:conflict`. Name the identity fields that narrow it with `match:`.
      """
    },
    %{
      id: "orphan-actor",
      level: :warn,
      esdm: "esdm/modeling/orphan-actor",
      summary: "An actor of the domain is named by no contract.",
      text: """
      No command's or query's `by:`, no event's `recorded_by:` and no process's `accountable` names
      it, so no contract gives it anything to do. A scenario's `actor` does not count: it has to be
      in the command's `by:` already (S7). Either the actor is left over, or the contract that gives
      it work is not written yet.
      """
    },
    %{
      id: "orphan-external-system",
      level: :warn,
      esdm: "esdm/modeling/orphan-external-system",
      summary: "An external system of the domain is used by nothing.",
      text: """
      No actor is `backed_by:` it, no relation ends at it, no field or entity is `issued_by:` it,
      no effect `calls:` it and no event `depends_on:` it.
      """
    },
    # An external's operations: plan EP5a.
    %{
      id: "operation-never-called",
      level: :warn,
      esdm: nil,
      summary: "An operation of an external system is called by no effect.",
      text: """
      The external declares what it does (ESDM's `capabilities`), and no effect of the
      domain's contracts `calls:` this operation. Either the operation is left over, or the effect
      that asks for it is not written yet. Asked only of a system some effect calls: one no effect
      calls says nothing of its operations, and `orphan-external-system` says it when nothing else
      uses it either.
      """
    },
    %{
      id: "bounded-context-without-content",
      level: :warn,
      esdm: "esdm/modeling/bounded-context-without-content",
      summary: "A context of the domain is the `context:` of no contract.",
      text: """
      ESDM counts the aggregates, boundaries and read models in a context; here those live in
      contracts, so a context is empty when no contract belongs to it. Values and entities it owns do
      not make it less empty: nothing is decided, recorded or read there.
      """
    },
    %{
      id: "subdomain-without-bounded-context",
      level: :warn,
      esdm: "esdm/modeling/subdomain-without-bounded-context",
      summary: "No context belongs to a subdomain of the domain.",
      text: """
      The subdomain names a part of the business, and nothing of the model is in it. Either a context
      should name it with `subdomain:`, or it is left over.
      """
    },
    %{
      id: "orphan-context-mapping",
      level: :warn,
      esdm: "esdm/modeling/orphan-context-mapping",
      summary: "A relation between two contexts is crossed by no reference.",
      text: """
      No contract of one context consumes a contract of the other, and none names an entity the other
      owns (`{:id, entity}`), in either direction; for a relation to an external system, no contract
      of the context calls it, depends on it, has a field it issues or acts through an actor it backs. The relation describes
      a dependency the contracts do not have.
      """
    },
    %{
      id: "relation-against-references",
      level: :warn,
      esdm: nil,
      summary:
        "A reference between two contexts runs against the relation declared between them.",
      text: """
      A directed relation — `customer_supplier`, `conformist`, `anticorruption_layer`,
      `open_host_service`, `published_language` — says the downstream context depends on the upstream
      one, and a contract of the upstream context consumes a contract of the downstream one or names
      an entity it owns. Or the relation is `separate_ways`, which says the two do not depend on each
      other, and a reference crosses it anyway. Either the relation or the reference is wrong. Between
      contexts only: which way a call to an external system runs says nothing about who depends on
      whom.
      """
    },
    %{
      id: "label-with-avoided-term",
      level: :warn,
      esdm: nil,
      summary: "A label of a contract uses a word its context's glossary says to avoid.",
      text: """
      The glossary says `avoid "Finished"` for the term "Completed", and an event of that context is
      labelled "Visit finished": the contract says what its own language says not to. The labels read
      are every declaration's and every enum member's; a word matches whole, regardless of letter case,
      and not inside the term itself. Inflected forms are not caught: `avoid` names each form to avoid.
      The words a translation avoids are another language's, which labels are not written in.
      """
    },
    %{
      id: "external-direction-contradicted",
      level: :warn,
      esdm: nil,
      summary: "An external this application only sends to issues a value or backs an actor.",
      text: """
      A value or an entity's identity `issued_by:` a system, and an actor `backed_by:` one, bring what the system says into
      this application, so a system declared `direction: :outbound`, one the application only sends
      to, can do neither. A system that also answers is `:bidirectional`: P1 is sent a report and
      answers with its number. A call says nothing either way, since an effect calls a system to send
      and to fetch alike.
      """
    },
    %{
      id: "cross-bounded-context-reference-without-mapping",
      level: :warn,
      esdm: "esdm/modeling/cross-bounded-context-reference-without-mapping",
      summary: "A contract reaches into another context that no relation connects to its own.",
      text: """
      It consumes a contract of another context, or names an entity another context owns, and the
      domain declares no `relation` between the two. Which way the dependency runs — who is upstream,
      who conforms, who translates — is then written nowhere. One finding per reference.
      """
    },
    %{
      id: "backward-edge",
      level: :warn,
      esdm: nil,
      summary: "A reaction in a later stage publishes into an earlier one.",
      text: """
      A policy or a process manager reacting to an event of one stage issues a command whose events
      sit in an earlier one. The process goes back on itself, which the stage order says it does not.
      Either the stages are in the wrong order or the reaction is a loop the process has not declared.
      """
    }
  ]

  @by_id Map.new(@rules, &{&1.id, &1})

  @doc "Every rule, in the order `docs/rules.md` prints them."
  @spec rules() :: [rule()]
  def rules, do: @rules

  @doc "The rule named `id`. Raises for a name the catalog does not have."
  @spec fetch!(String.t()) :: rule()
  def fetch!(id) do
    case Map.fetch(@by_id, id) do
      {:ok, rule} -> rule
      :error -> raise ArgumentError, "no rule #{inspect(id)} in EhOsContract.Check.Catalog"
    end
  end

  @doc "Whether the catalog has a rule named `id`."
  @spec known?(String.t()) :: boolean()
  def known?(id), do: Map.has_key?(@by_id, id)

  @doc "The word a level is printed as in `docs/rules.md` and in `--format json`."
  @spec level_word(:error | :warn | :info) :: String.t()
  def level_word(:error), do: "error"
  def level_word(:warn), do: "warning"
  def level_word(:info), do: "notice"

  @doc "Where a rule is documented: its entry in `docs/rules.md`, as the package's docs publish it."
  @spec url(String.t()) :: String.t()
  def url(id), do: "https://hexdocs.pm/eh_os_contract/rules.html##{fetch!(id).id}"
end

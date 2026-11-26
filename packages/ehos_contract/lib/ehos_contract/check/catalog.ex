defmodule EhosContract.Check.Catalog do
  # Every rule `mix ehos_contract.check` reports on, under a name that does not
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
  # `docs/rules.md` is generated from this list (by `ehos_contract.rules`, a task of
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
      0 notices`. This is the one finding that tells them apart. Set `config :ehos_contract,
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
      id: "owner-view-without-label",
      level: :info,
      esdm: nil,
      summary: "A stage, a value or a member of a value's enum has no label.",
      text: """
      A business owner reads the model in the business's words: each declaration by its label.
      Most declarations need one to compile, and a field without one is not for the owner. A
      stage of a process module, a value of the domain and a member of its enum written as a
      bare atom may go without, and then the owner would read the name in the code,
      `departure`, where the business says "Departure of the patient". A promise has no label
      at all: it is read by its rule, the events it waits for, in their labels. The owner's
      pages (`mix ehos_contract.pages --audience owner`) and the owner's view of the graph
      (its switch "Owner") both read the model this way.
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
      a different actor when application-wide authority is deliberate. An actor of kind `:system` is
      left out, since dispatch never narrows it.
      """
    },
    %{
      id: "scoped-actor-with-unscoped-query",
      level: :warn,
      esdm: nil,
      summary: "An actor with scope dimensions may ask an unscoped query.",
      text: """
      The actor's other grants can be narrowed to named dimensions, but this query answers the rows of
      every value: a lead granted one warehouse reads the rows of all of them. Declare the query's
      `scope` when its read model has one of those dimensions, and move the actors without them to a
      query of their own. Use a different actor when reading across the application is deliberate.
      An actor of kind `:system` is left out, since dispatch never narrows it.
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
        "A consumer of another context's event runs inside the transaction that records it.",
      text: """
      A policy, an effect or a read model declared `delivery: :in_transaction` on an event of a
      sibling contract of another context runs in the transaction that records the event, so the
      two contexts commit together and a failure of the consumer rolls the other context's event back.
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
      number or a choice has a type of its own: an `:id`, an enum, or a value declared
      `code: true` whose invariants pin its form, e.g. a tax number. A code that identifies a
      person, such as a national id number, is personal all the same, and is marked `personal:`.
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
      it, no contract consumes it and no `publish` sends it. Unlike ESDM, an event a unit's lifecycle
      starts on or moves on, or one a process module includes, has a reader: the conformance report.
      The unit's own `evolve` does not count, as ESDM's aggregate does not.
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
      id: "recording-without-scenario",
      level: :warn,
      esdm: nil,
      summary: "No scenario records an event its `recorded_by:` actors record.",
      text: """
      The event is written into the log by an actor, a person or an integration, with no command to
      decide it, and the contract shows it only as a `given` of what follows. A scenario that records
      it, `record :collected, %{…}` with one of those actors, is what shows who may write it and what
      it appends; one with `rejected:` shows the data a value's invariant refuses. For an integration
      that is the part that matters most: what the outside system may write into the log. A warning,
      as `reaction-without-scenario` is: `EhosContract.record/3` still holds every recording to its
      declaration.
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
      id: "core-command-never-refuses",
      level: :info,
      esdm: nil,
      summary: "A command of a core context rejects nothing.",
      text: """
      The context belongs to a subdomain of `type: :core`, where the business's rules are meant to
      live, and the command's `rejects:` is empty, so no rule of its unit refuses a request; only its
      fields' types and values can. A command only a policy or a process manager issues, with no
      `by:`, is not reported, since it follows from an event already decided.
      Either the command has a rule the contract does not declare yet, or it only records an event, and
      an event `recorded_by:` an actor says that more plainly. Some core commands legitimately always
      succeed, so this is a notice.
      """
    },
    %{
      id: "core-unit-records-only",
      level: :warn,
      esdm: nil,
      summary: "A unit of a core context decides nothing.",
      text: """
      The unit has events and no command of it can be refused — none has `rejects:`, or it has no
      commands and its events are only `recorded_by:` — and its context belongs to a subdomain of
      `type: :core`. A command a reaction issues counts like any other: a unit whose commands only
      reactions send decides nothing either. A
      unit that only records keeps a log; the decisions the core is for are somewhere else, or the
      context is not core. Its page says "Records only" wherever it is.
      """
    },
    %{
      id: "orphan-actor",
      level: :warn,
      esdm: "esdm/modeling/orphan-actor",
      summary: "An actor of the domain is named by no contract and no process module.",
      text: """
      No command's or query's `by:`, no event's `recorded_by:` and no process module's `accountable`
      names it, so no contract or process gives it anything to do. A scenario's `actor` does not
      count: it has to be in the command's `by:` already (S7). Either the actor is left over, or the
      contract that gives it work is not written yet.
      """
    },
    %{
      id: "seed-actor-in-by",
      level: :error,
      esdm: nil,
      summary: "The domain's `:seed` actor is named in a `by:` or a `recorded_by:`.",
      text: """
      The seed may issue every command and record every event a person of the domain may, except
      what the domain's `not_seeded:` names, so no declaration names it. Named in `by:`, it shows on
      the graph as a participant of the business. Remove it from the `by:` or `recorded_by:`.
      """
    },
    %{
      id: "second-seed-actor",
      level: :error,
      esdm: nil,
      summary: "A domain declares more than one `:seed` actor.",
      text: """
      A domain has one seed, with one `not_seeded:` list that dispatch and the seed's own tests read.
      Keep one seed actor, and merge the lists.
      """
    },
    %{
      id: "not-seeded-unknown",
      level: :error,
      esdm: nil,
      summary: "The seed's `not_seeded:` names no command or recorded event of the domain.",
      text: """
      A name that is no command and no event with `recorded_by:` in the domain's contracts holds
      nothing back from the seed. It is most often a typo, or a declaration that was renamed: the
      command it meant to keep from the seed is then seeded. Correct the name, or remove it.
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
      summary: "A relation other than `:separate_ways` is crossed by no reference.",
      text: """
      No contract of one context consumes a contract of the other, names an entity or a unit the
      other owns (`{:id, name}`) or uses a value it declares (`context:`), in either direction; for a relation to an external system, no contract
      of the context calls it, depends on it, has a field it issues or acts through an actor it backs. The relation describes
      a dependency the contracts do not have.
      A `:separate_ways` relation is not checked: it says that the two contexts do not depend on
      each other, and the compiler refuses a reference across it.
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
      id: "word-without-term",
      level: :info,
      esdm: nil,
      summary: "A context names things with words its glossary has no term for.",
      text: """
      One finding per context, listing the words of the names of its units, read models and fields
      that no term of its glossary covers, the word used by the most names first. A term covers a
      word when the term's word in code — its translation into the domain's `code_language:`, or the
      term itself in a context written in that language — stands in the name: "Visit" covers
      `visit_id`, "Settlement date" covers `settlement_date` and not `date`. Names of commands and
      events are not read, since their verbs are inflected ("closed") where a term is not ("Close"),
      nor words of one or two letters (`id`, `at`), nor the words of a field that name the value of
      the domain it is typed with. The words at the top are the ones the glossary most needs, or the
      ones the code should not use.
      """
    },
    %{
      id: "term-of-another-context",
      level: :warn,
      esdm: nil,
      summary: "A name uses a term of another context that its own context's glossary lacks.",
      text: """
      A unit, a read model or a field of a contract is named with the word in code of a term another
      context declares, and no term of the contract's own context covers it. Each context has its own
      language: either the word means something here too, and the context's glossary should say what,
      or the name borrows the other context's meaning. One finding per name of a contract. A field
      typed `{:id, entity}`, or named like the identity of another context's unit (`visit_id`), is
      not read: it refers to that declaration, under its name. Nor are the words of a field that
      name the value of the domain it is typed with: `office_nip` of type `:nip` says "nip" as that
      value's word, which every context using the value shares.
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
      It consumes a contract of another context, names an entity or a unit another context owns, or
      uses a value another context declares, and the domain declares no `relation` between the two.
      Which way the dependency runs — who is upstream, who conforms, who translates — is then written
      nowhere. One finding per reference. A reference against a relation that is declared does not
      compile (X11–X13).
      """
    },
    %{
      id: "backward-edge",
      level: :warn,
      esdm: nil,
      summary: "A reaction in a later stage of a process publishes into an earlier one.",
      text: """
      A policy or a process manager reacting to an event that one stage of a process module includes
      issues a command whose events sit in an earlier stage of that module. The process goes back on
      itself, which the stage order says it does not. Either the stages are in the wrong order or
      the reaction is a loop the process has not declared.
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
      :error -> raise ArgumentError, "no rule #{inspect(id)} in EhosContract.Check.Catalog"
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
  def url(id), do: "https://hexdocs.pm/ehos_contract/rules.html##{fetch!(id).id}"
end

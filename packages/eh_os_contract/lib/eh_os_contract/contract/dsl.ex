defmodule EhOsContract.Contract.Dsl do
  @moduledoc """
  The Spark extension behind `use EhOsContract.Contract`.

  One top-level section, so every entity is written straight into the module body:
  the units that decide (aggregates and dynamic consistency boundaries) with their
  state, invariants, commands, events and stage groups; what reacts to events
  (policies, effects, process managers); what is read (read models, queries); what
  enters from elsewhere (`consumes`) and what leaves the application (`publish`);
  the one process; and scenarios. The vocabulary is closed: a contract cannot add
  extensions.

  Options may stand beside a `do` block (`EhOsContract.DslWrappers`).

  The structs below are what Spark builds from each declaration. They stay inside the
  extension: readers get plain data from `EhOsContract.Model`, never these structs.
  """

  defmodule Field do
    @moduledoc false
    defstruct [:name, :type, :label, :personal, :subject, :default, :issued_by] ++
                [optional: false, __spark_metadata__: nil]
  end

  defmodule Param do
    @moduledoc false
    defstruct [:name, :type, :label, optional: false, __spark_metadata__: nil]
  end

  defmodule State do
    @moduledoc false
    defstruct fields: [], __spark_metadata__: nil
  end

  defmodule Invariant do
    @moduledoc false
    defstruct [:name, :label, :source, __spark_metadata__: nil]
  end

  defmodule Constraint do
    @moduledoc false
    defstruct [:name, :label, :source, __spark_metadata__: nil]
  end

  defmodule Command do
    @moduledoc false
    defstruct [:name, :label, :source, :scope, by: [], emits: [], rejects: [], fields: []] ++
                [constraints: [], creates: false, __spark_metadata__: nil]
  end

  defmodule Generated do
    @moduledoc """
    `identity :booking_id, generated: :uuid` in an aggregate (plan EM3): the identity,
    and that the library gives each new aggregate one. Spark's option takes one
    argument, so this two-argument form sets the two options it stands for.
    """

    @doc "Sets the aggregate's `identity` and how a new one is `generated`."
    defmacro identity(fields, opts) do
      case opts do
        [generated: generated] ->
          quote do
            identity(unquote(fields))
            generated(unquote(generated))
          end

        _other ->
          raise CompileError,
            file: __CALLER__.file,
            line: __CALLER__.line,
            description:
              "identity takes one option beside its fields, `generated: :uuid`, and got " <>
                Macro.to_string(opts)
      end
    end
  end

  defmodule Event do
    @moduledoc false
    defstruct [:name, :label, :depends_on, :source, terminal: false, recorded_by: []] ++
                [schema_version: 1, fields: [], __spark_metadata__: nil]
  end

  defmodule Stage do
    @moduledoc false
    defstruct [:name, events: [], __spark_metadata__: nil]
  end

  defmodule Consults do
    @moduledoc false
    defstruct [:event, :where, match: [], __spark_metadata__: nil]
  end

  defmodule Unit do
    @moduledoc false
    defstruct [:kind, :name, :label, :source, :generated, identity: [], consults: [], state: []] ++
                [invariants: [], commands: [], events: [], stages: [], __spark_metadata__: nil]
  end

  defmodule Policy do
    @moduledoc false
    defstruct [:name, :label, :idempotency, :source, handles: [], issues: []] ++
                [delivery: :in_transaction, constraints: []] ++
                [__spark_metadata__: nil]
  end

  defmodule Effect do
    @moduledoc false
    defstruct [:name, :label, :idempotency, :source, handles: [], calls: []] ++
                [delivery: :at_least_once, constraints: []] ++
                [__spark_metadata__: nil]
  end

  defmodule StartsOn do
    @moduledoc false
    defstruct [:event, sets: [], issues: [], __spark_metadata__: nil]
  end

  defmodule On do
    @moduledoc false
    defstruct [:event, issues: [], sets: [], cancels: [], __spark_metadata__: nil]
  end

  defmodule Timer do
    @moduledoc false
    defstruct [:name, :wait, :at, :source, issues: [], __spark_metadata__: nil]
  end

  defmodule EndsOn do
    @moduledoc false
    defstruct [:event, __spark_metadata__: nil]
  end

  defmodule ProcessManager do
    @moduledoc false
    defstruct [:name, :label, :idempotency, :source, correlate: [], delivery: :at_least_once] ++
                [state: [], starts_on: [], on: [], timers: [], ends_on: []] ++
                [constraints: [], invariants: []] ++
                [__spark_metadata__: nil]
  end

  defmodule ReadModel do
    @moduledoc false
    defstruct [:name, :label, :source, projects: [], delivery: :in_transaction, fields: []] ++
                [__spark_metadata__: nil]
  end

  defmodule Query do
    @moduledoc false
    defstruct [:name, :label, :reads, :scope, :source, by: [], returns: :many, params: []] ++
                [constraints: [], __spark_metadata__: nil]
  end

  defmodule Argument do
    @moduledoc false
    defstruct [:name, :type, :label, optional: false, __spark_metadata__: nil]
  end

  defmodule Rule do
    @moduledoc false
    defstruct [:name, :label, :source, examples: [], __spark_metadata__: nil]
  end

  defmodule Returns do
    @moduledoc false
    defstruct [:type, optional: false, __spark_metadata__: nil]
  end

  defmodule ServiceFunction do
    @moduledoc false
    defstruct [:name, :label, :returns, arguments: [], rules: [], __spark_metadata__: nil]
  end

  defmodule DomainService do
    @moduledoc false
    defstruct [:name, :label, :source, functions: [], __spark_metadata__: nil]
  end

  defmodule Consumes do
    @moduledoc false
    defstruct [:from, :as, events: [], fields: [], __spark_metadata__: nil]
  end

  defmodule Publish do
    @moduledoc false
    defstruct [:name, :as, :from, fields: [], idempotent_on: [], __spark_metadata__: nil]
  end

  defmodule Include do
    @moduledoc false
    defstruct [:event, terminal: false, __spark_metadata__: nil]
  end

  defmodule ProcessStage do
    @moduledoc false
    defstruct [:name, :label, includes: [], __spark_metadata__: nil]
  end

  defmodule Cadence do
    @moduledoc false
    defstruct [:every, unverified: false, __spark_metadata__: nil]
  end

  defmodule Deadline do
    @moduledoc false
    defstruct [:within, unverified: false, __spark_metadata__: nil]
  end

  defmodule Promise do
    @moduledoc false
    defstruct [:name, :from, :eventually, :within, :or_else, :source, unverified: false] ++
                [__spark_metadata__: nil]
  end

  defmodule ProcessDeclaration do
    @moduledoc false
    defstruct [:name, :label, :accountable, :source, correlate: [], stages: [], includes: []] ++
                [cadence: [], deadline: [], promises: [], __spark_metadata__: nil]
  end

  defmodule Given do
    @moduledoc false
    defstruct [:event, data: %{}, __spark_metadata__: nil]
  end

  defmodule Trigger do
    @moduledoc false
    defstruct [:kind, :name, data: %{}, __spark_metadata__: nil]
  end

  defmodule Expect do
    @moduledoc false
    defstruct [:event, data: %{}, __spark_metadata__: nil]
  end

  defmodule Answers do
    @moduledoc false
    defstruct [:rows, __spark_metadata__: nil]
  end

  defmodule ExpectedState do
    @moduledoc false
    defstruct [:data, __spark_metadata__: nil]
  end

  defmodule Issues do
    @moduledoc false
    defstruct [:command, data: %{}, __spark_metadata__: nil]
  end

  defmodule TimerRef do
    @moduledoc false
    defstruct [:kind, :timer, __spark_metadata__: nil]
  end

  defmodule Scenario do
    @moduledoc false
    defstruct [:description, :scope, :actor, :rejected, ended: false, given: [], trigger: []] ++
                [illustrates: []] ++
                [
                  expect: [],
                  issues: [],
                  sets: [],
                  cancels: [],
                  answers: [],
                  state: [],
                  __spark_metadata__: nil
                ]
  end

  # --- fields --------------------------------------------------------------------

  @field %Spark.Dsl.Entity{
    name: :field,
    describe: "One field of a state, a command, an event or a read model's row.",
    target: Field,
    args: [:name, :type],
    schema: [
      name: [type: :atom, required: true, doc: "The field's name."],
      type: [type: :any, required: true, doc: "A built-in type or a value of the domain."],
      optional: [type: :boolean, default: false, doc: "Whether the field may be absent."],
      label: [type: :string, doc: "What the business calls it."],
      personal: [type: :atom, doc: "The field holding the identifier of whose data this is."],
      subject: [type: :atom, doc: "The domain subject this identifier field identifies."],
      default: [type: :any, doc: "The initial value; only in a state."],
      issued_by: [
        type: :atom,
        doc: "The domain external that gives this value, e.g. a number another system assigns."
      ]
    ]
  }

  @param %Spark.Dsl.Entity{
    name: :param,
    describe: "One parameter of a query.",
    target: Param,
    args: [:name, :type],
    schema: [
      name: [type: :atom, required: true, doc: "The parameter's name."],
      type: [type: :any, required: true, doc: "A built-in type or a value of the domain."],
      optional: [type: :boolean, default: false, doc: "Whether it may be left out."],
      label: [type: :string, doc: "What the business calls it."]
    ]
  }

  @state %Spark.Dsl.Entity{
    name: :state,
    describe: "What a unit or a process manager remembers between decisions.",
    target: State,
    entities: [fields: [@field]]
  }

  # --- the units that decide ------------------------------------------------------

  @invariant %Spark.Dsl.Entity{
    name: :invariant,
    describe: "What must stay true under every command of the unit.",
    target: Invariant,
    args: [:name, :label],
    schema: [
      name: [type: :atom, required: true, doc: "The invariant's name."],
      label: [type: :string, required: true, doc: "The rule, as the business states it."],
      source: [type: :string, doc: "Where the rule comes from in the material."]
    ]
  }

  # A process manager's invariant (plan EP2, ESDM's): what holds of every run. It
  # refuses nothing, so a scenario that `illustrates:` it is what shows it holds.
  @manager_invariant %{
    @invariant
    | describe: "What must stay true of every run of the process manager."
  }

  # ESDM's constraint (plan EL2): a named rule prose states. A command's is checked
  # as an invariant is — it is in `rejects:`, the implementation `reject/1`s on it, and
  # a scenario refuses the command on it — but it is about the command's data alone.
  # A query's, a policy's and a process manager's is shown by a scenario that
  # `illustrates:` it (plan EP2); an effect's is prose alone, since no scenario runs one.
  @constraint %Spark.Dsl.Entity{
    name: :constraint,
    describe: "A rule a command's data, a query or a reaction keeps, as the business states it.",
    target: Constraint,
    args: [:name, :label],
    schema: [
      name: [type: :atom, required: true, doc: "The constraint's name."],
      label: [type: :string, required: true, doc: "The rule, as the business states it."],
      source: [type: :string, doc: "Where the rule comes from in the material."]
    ]
  }

  @command %Spark.Dsl.Entity{
    name: :command,
    describe: "An intention an actor or a reaction issues to a unit.",
    target: Command,
    args: [:name, :label],
    entities: [fields: [@field], constraints: [@constraint]],
    schema: [
      name: [type: :atom, required: true, doc: "The command's name."],
      label: [type: :string, required: true, doc: "What the business calls it."],
      by: [type: {:wrap_list, :atom}, default: [], doc: "The actors who may issue it."],
      emits: [
        type: {:wrap_list, :atom},
        required: true,
        doc: "The events of this unit it may produce."
      ],
      rejects: [
        type: {:wrap_list, :atom},
        default: [],
        doc: "The invariants of this unit, and the constraints of this command, it may refuse on."
      ],
      creates: [
        type: :boolean,
        default: false,
        doc:
          "Whether it creates the aggregate, which the library then gives its generated identity."
      ],
      scope: [
        type: :atom,
        doc:
          "The field a grant narrows it to: a field of the command, and a scope of every actor in `by:`."
      ],
      source: [type: :string, doc: "Where the command comes from in the material."]
    ]
  }

  @event %Spark.Dsl.Entity{
    name: :event,
    describe: "A fact the unit records.",
    target: Event,
    args: [:name, :label],
    entities: [fields: [@field]],
    schema: [
      name: [type: :atom, required: true, doc: "The event's name."],
      label: [type: :string, required: true, doc: "The fact, as the business states it."],
      terminal: [type: :boolean, default: false, doc: "Whether it ends a run of the process."],
      depends_on: [type: :atom, doc: "The external system the fact depends on."],
      recorded_by: [
        type: {:wrap_list, :atom},
        default: [],
        doc: "The actors who record it as an observation, when no command decides it."
      ],
      schema_version: [
        type: :pos_integer,
        default: 1,
        doc: "The version of its fields, raised with an upcaster when history exists."
      ],
      source: [type: :string, doc: "Where the event comes from in the material."]
    ]
  }

  @stage %Spark.Dsl.Entity{
    name: :stage,
    describe: "Groups the unit's events into one stage of the process.",
    target: Stage,
    args: [:name],
    entities: [events: [@event]],
    schema: [name: [type: :atom, required: true, doc: "A stage the process declares."]]
  }

  @consults %Spark.Dsl.Entity{
    name: :consults,
    describe: "An event a dynamic consistency boundary reads before it decides.",
    target: Consults,
    args: [:event],
    schema: [
      event: [type: :atom, required: true, doc: "The event read."],
      match: [
        type: {:wrap_list, :atom},
        default: [],
        doc: "Identity fields the event must carry with the boundary's values."
      ],
      where: [type: :string, doc: "The criterion in prose, when fields cannot say it."]
    ]
  }

  @unit_entities [
    state: [@state],
    invariants: [@invariant],
    commands: [@command],
    events: [@event],
    stages: [@stage]
  ]

  @aggregate %Spark.Dsl.Entity{
    name: :aggregate,
    describe: "A unit that decides over one stream, identified by its identity.",
    target: Unit,
    args: [:name, :label],
    auto_set_fields: [kind: :aggregate],
    entities: @unit_entities,
    imports: [Generated],
    schema: [
      name: [type: :atom, required: true, doc: "The aggregate's name."],
      label: [type: :string, required: true, doc: "What the business calls it."],
      identity: [
        type: {:wrap_list, :atom},
        required: true,
        doc:
          "The fields that identify one aggregate; injected into its state, commands and events."
      ],
      generated: [
        type: {:one_of, [:uuid]},
        doc:
          "That the library gives a new aggregate its identity, a UUIDv7, when a command that " <>
            "`creates:` it arrives without one; written `identity :booking_id, generated: :uuid`."
      ],
      source: [type: :string, doc: "Where the aggregate comes from in the material."]
    ]
  }

  @dcb %Spark.Dsl.Entity{
    name: :dcb,
    describe: "A dynamic consistency boundary: a unit that decides over the events it consults.",
    target: Unit,
    args: [:name, :label],
    auto_set_fields: [kind: :dcb],
    entities: [consults: [@consults]] ++ @unit_entities,
    schema: [
      name: [type: :atom, required: true, doc: "The boundary's name."],
      label: [type: :string, required: true, doc: "What the business calls it."],
      identity: [
        type: {:wrap_list, :atom},
        required: true,
        doc:
          "The fields that identify one boundary; injected into its state, commands and events."
      ],
      source: [type: :string, doc: "Where the boundary comes from in the material."]
    ]
  }

  # --- what reacts to events -----------------------------------------------------

  @delivery {:one_of, [:in_transaction, :at_least_once]}

  # Plan EP4: what makes a second delivery harmless, and who keeps it so — ESDM's
  # `idempotency` with its `owner`. The owner is a difference in the reaction's code:
  # a key the called system dedups on has to be passed to it.
  @idempotency {:keyword_list,
                [
                  key: [
                    type: :atom,
                    required: true,
                    doc: "What tells a second delivery from a first: `:event_id` or a field."
                  ],
                  owner: [
                    type: {:one_of, [:self, :downstream, :infrastructure]},
                    required: true,
                    doc:
                      "Who keeps a second delivery harmless: the reaction's own code " <>
                        "(`:self`), the system it calls, given the key (`:downstream`), or " <>
                        "the engine, with no code (`:infrastructure`)."
                  ]
                ]}
  @idempotency_doc "What makes a second delivery harmless, and who keeps it so: " <>
                     "`[key: :event_id, owner: :self]`."

  @policy %Spark.Dsl.Entity{
    name: :policy,
    describe: "Whenever an event happens, issue a command.",
    target: Policy,
    args: [:name, :label],
    entities: [constraints: [@constraint]],
    schema: [
      name: [type: :atom, required: true, doc: "The policy's name."],
      label: [type: :string, required: true, doc: "The rule, as the business states it."],
      handles: [type: {:wrap_list, :atom}, required: true, doc: "The events it reacts to."],
      issues: [type: {:wrap_list, :atom}, required: true, doc: "The commands it may issue."],
      delivery: [type: @delivery, default: :in_transaction, doc: "When it runs."],
      idempotency: [type: @idempotency, doc: @idempotency_doc],
      source: [type: :string, doc: "Where the policy comes from in the material."]
    ]
  }

  @effect %Spark.Dsl.Entity{
    name: :effect,
    describe: "A side effect on an event, outside the log.",
    target: Effect,
    args: [:name, :label],
    entities: [constraints: [@constraint]],
    schema: [
      name: [type: :atom, required: true, doc: "The effect's name."],
      label: [type: :string, required: true, doc: "What it does, as the business states it."],
      handles: [type: {:wrap_list, :atom}, required: true, doc: "The events it reacts to."],
      calls: [type: {:wrap_list, :atom}, default: [], doc: "The external systems it calls."],
      delivery: [type: @delivery, default: :at_least_once, doc: "When it runs."],
      idempotency: [type: @idempotency, doc: @idempotency_doc],
      source: [type: :string, doc: "Where the effect comes from in the material."]
    ]
  }

  @starts_on %Spark.Dsl.Entity{
    name: :starts_on,
    describe: "The event that starts one process manager.",
    target: StartsOn,
    args: [:event],
    schema: [
      event: [type: :atom, required: true, doc: "The event."],
      sets: [type: {:wrap_list, :atom}, default: [], doc: "Timers it sets."],
      issues: [type: {:wrap_list, :atom}, default: [], doc: "Commands it issues."]
    ]
  }

  @on %Spark.Dsl.Entity{
    name: :on,
    describe: "A reaction of a running process manager to an event or its own timer.",
    target: On,
    args: [:event],
    schema: [
      event: [type: :atom, required: true, doc: "The event, or the name of its own timer."],
      issues: [type: {:wrap_list, :atom}, default: [], doc: "Commands it issues."],
      sets: [type: {:wrap_list, :atom}, default: [], doc: "Timers it sets."],
      cancels: [type: {:wrap_list, :atom}, default: [], doc: "Timers it cancels."]
    ]
  }

  @timer %Spark.Dsl.Entity{
    name: :timer,
    describe: "A timer of a process manager: after a wait, or at a time in its state.",
    target: Timer,
    args: [:name],
    schema: [
      name: [type: :atom, required: true, doc: "The timer's name."],
      wait: [type: :any, doc: "How long after it is set it fires, `{n, unit}`."],
      at: [type: :atom, doc: "The `:timestamp` field of the state it fires at."],
      issues: [type: {:wrap_list, :atom}, default: [], doc: "Commands it issues when it fires."],
      source: [type: :string, doc: "Where the timer comes from in the material."]
    ]
  }

  @ends_on %Spark.Dsl.Entity{
    name: :ends_on,
    describe: "An event that ends one process manager.",
    target: EndsOn,
    args: [:event],
    schema: [event: [type: :atom, required: true, doc: "The event."]]
  }

  @process_manager %Spark.Dsl.Entity{
    name: :process_manager,
    describe: "Steers a run: starts on an event, reacts, sets timers, ends.",
    target: ProcessManager,
    args: [:name, :label],
    entities: [
      state: [@state],
      starts_on: [@starts_on],
      on: [@on],
      timers: [@timer],
      ends_on: [@ends_on],
      invariants: [@manager_invariant],
      constraints: [@constraint]
    ],
    schema: [
      name: [type: :atom, required: true, doc: "The process manager's name."],
      label: [type: :string, required: true, doc: "What it steers, as the business says it."],
      correlate: [
        type: {:wrap_list, :atom},
        required: true,
        doc: "The fields that tell which run an event belongs to."
      ],
      delivery: [type: @delivery, default: :at_least_once, doc: "When it runs."],
      idempotency: [type: @idempotency, doc: @idempotency_doc],
      source: [type: :string, doc: "Where the process manager comes from in the material."]
    ]
  }

  # --- what is read --------------------------------------------------------------

  @read_model %Spark.Dsl.Entity{
    name: :read_model,
    describe: "Rows projected from events, for queries to read.",
    target: ReadModel,
    args: [:name, :label],
    entities: [fields: [@field]],
    schema: [
      name: [type: :atom, required: true, doc: "The read model's name."],
      label: [type: :string, required: true, doc: "What the business calls it."],
      projects: [type: {:wrap_list, :atom}, required: true, doc: "The events it projects."],
      delivery: [type: @delivery, default: :in_transaction, doc: "When it is updated."],
      source: [type: :string, doc: "Where the read model comes from in the material."]
    ]
  }

  @query %Spark.Dsl.Entity{
    name: :query,
    describe: "A question an actor may ask of a read model; a capability, like a command.",
    target: Query,
    args: [:name, :label],
    entities: [params: [@param], constraints: [@constraint]],
    schema: [
      name: [type: :atom, required: true, doc: "The query's name."],
      label: [type: :string, required: true, doc: "What the business calls it."],
      reads: [type: :atom, required: true, doc: "The read model it reads."],
      by: [type: {:wrap_list, :atom}, default: [], doc: "The actors who may ask it."],
      returns: [type: {:one_of, [:many, :one]}, default: :many, doc: "Rows or one row."],
      scope: [
        type: :atom,
        doc:
          "The row field a grant narrows the answer to: a parameter and a scope of every actor."
      ],
      source: [type: :string, doc: "Where the query comes from in the material."]
    ]
  }

  # --- what crosses a boundary ---------------------------------------------------

  @argument %Spark.Dsl.Entity{
    name: :argument,
    describe: "One argument of a domain service's function, in the order it is passed.",
    target: Argument,
    args: [:name, :type],
    schema: [
      name: [type: :atom, required: true, doc: "The argument's name."],
      type: [type: :any, required: true, doc: "A built-in type or a value of the domain."],
      optional: [type: :boolean, default: false, doc: "Whether it may be nil."],
      label: [type: :string, doc: "What the business calls it."]
    ]
  }

  # A rule is shown on examples, each a test of the function (plan EL2b; required,
  # the user's choice of 28 September 2026).
  @rule %Spark.Dsl.Entity{
    name: :rule,
    describe: "A rule the function follows, as the business states it, with examples of it.",
    target: Rule,
    args: [:name, :label],
    schema: [
      name: [type: :atom, required: true, doc: "The rule's name."],
      label: [type: :string, required: true, doc: "The rule, as the business states it."],
      examples: [
        type: {:list, :any},
        required: true,
        doc:
          "Calls that show the rule, `{[argument, …], result}`, as plain data: each is a test " <>
            "that the function returns that result."
      ],
      source: [type: :string, doc: "Where the rule comes from in the material."]
    ]
  }

  @returns %Spark.Dsl.Entity{
    name: :returns,
    describe: "What a domain service's function returns.",
    target: Returns,
    args: [:type],
    schema: [
      type: [type: :any, required: true, doc: "A built-in type or a value of the domain."],
      optional: [type: :boolean, default: false, doc: "Whether it may return nil."]
    ]
  }

  @function %Spark.Dsl.Entity{
    name: :function,
    describe: "A pure function of a domain service: arguments in, a result out, nothing written.",
    target: ServiceFunction,
    args: [:name, :label],
    entities: [arguments: [@argument], rules: [@rule], returns: [@returns]],
    singleton_entity_keys: [:returns],
    schema: [
      name: [type: :atom, required: true, doc: "The function's name."],
      label: [type: :string, required: true, doc: "What it computes, as the business says it."]
    ]
  }

  @domain_service %Spark.Dsl.Entity{
    name: :domain_service,
    describe:
      "Domain logic that belongs to no unit (ESDM's domain service): pure functions a decision " <>
        "calls through the module the contract generates, which holds them to their types.",
    target: DomainService,
    args: [:name, :label],
    entities: [functions: [@function]],
    schema: [
      name: [type: :atom, required: true, doc: "The service's name."],
      label: [type: :string, required: true, doc: "What the business calls it."],
      source: [type: :string, doc: "Where the service comes from in the material."]
    ]
  }

  @consumes %Spark.Dsl.Entity{
    name: :consumes,
    describe:
      "Events born elsewhere: a sibling contract's (a module), or another application's " <>
        "published event (its name, with the fields read).",
    target: Consumes,
    args: [:from, {:optional, :events}],
    no_depend_modules: [:from],
    entities: [fields: [@field]],
    schema: [
      from: [
        type: {:or, [:atom, :string]},
        required: true,
        doc:
          "The sibling contract, or the published name, versioned as `publish as:` is, " <>
            "like `\"my-shop.entry.recorded.v1\"`."
      ],
      events: [type: {:wrap_list, :atom}, default: [], doc: "The sibling contract's events."],
      as: [
        type: {:or, [:atom, :keyword_list]},
        doc: "A published event's local name, or renames of a sibling's events, `[old: :new]`."
      ]
    ]
  }

  @publish %Spark.Dsl.Entity{
    name: :publish,
    describe: "An integration event: the one way an event leaves the application.",
    target: Publish,
    args: [:name],
    schema: [
      name: [type: :atom, required: true, doc: "The publication's name."],
      as: [
        type: :string,
        required: true,
        doc:
          "The versioned name, under the domain's `name:`, like `\"my-shop.entry.recorded.v1\"`; " <>
            "only that first segment may hold a dash."
      ],
      from: [type: :atom, required: true, doc: "The local event it is built from."],
      fields: [
        type: {:wrap_list, :atom},
        required: true,
        doc: "The fields of that event it carries."
      ],
      idempotent_on: [
        type: {:wrap_list, :atom},
        default: [],
        doc: "The fields that make two deliveries the same fact."
      ]
    ]
  }

  # --- the process ---------------------------------------------------------------

  @include %Spark.Dsl.Entity{
    name: :include,
    describe: "Places a consumed event in the process.",
    target: Include,
    args: [:event],
    schema: [
      event: [type: :atom, required: true, doc: "The consumed event."],
      terminal: [type: :boolean, default: false, doc: "Whether it ends a run."]
    ]
  }

  @process_stage %Spark.Dsl.Entity{
    name: :stage,
    describe: "One stage of the process, in order; consumed events are placed with `include`.",
    target: ProcessStage,
    args: [:name, {:optional, :label}],
    entities: [includes: [@include]],
    schema: [
      name: [type: :atom, required: true, doc: "The stage's name."],
      label: [type: :string, doc: "What the business calls it."]
    ]
  }

  @cadence %Spark.Dsl.Entity{
    name: :cadence,
    describe: "How often a run is due; calendar units allowed.",
    target: Cadence,
    args: [:every],
    schema: [
      every: [type: :any, required: true, doc: "`{n, unit}`."],
      unverified: [type: :boolean, default: false, doc: "Not confirmed by the process owner."]
    ]
  }

  @deadline %Spark.Dsl.Entity{
    name: :deadline,
    describe: "How long a run may take, from its first event to a terminal one.",
    target: Deadline,
    args: [:within],
    schema: [
      within: [type: :any, required: true, doc: "`{n, unit}`, in a fixed unit."],
      unverified: [type: :boolean, default: false, doc: "Not confirmed by the process owner."]
    ]
  }

  @promise %Spark.Dsl.Entity{
    name: :promise,
    describe: "After one event of a run, another eventually follows.",
    target: Promise,
    args: [:name],
    schema: [
      name: [type: :atom, required: true, doc: "The promise's name."],
      from: [type: :atom, required: true, doc: "The event that opens the promise."],
      eventually: [type: :atom, required: true, doc: "The event that keeps it."],
      within: [type: :any, doc: "`{n, unit}`, in a fixed unit."],
      or_else: [type: :atom, doc: "An event that keeps it the other way."],
      unverified: [type: :boolean, default: false, doc: "Not confirmed by the process owner."],
      source: [type: :string, doc: "Where the promise comes from."]
    ]
  }

  @process %Spark.Dsl.Entity{
    name: :process,
    describe: "The one process the contract describes: its runs, stages and promises.",
    target: ProcessDeclaration,
    args: [:name, :label],
    entities: [
      stages: [@process_stage],
      includes: [@include],
      cadence: [@cadence],
      deadline: [@deadline],
      promises: [@promise]
    ],
    schema: [
      name: [
        type: :atom,
        required: true,
        doc: "The process's name, the prefix of its event types."
      ],
      label: [type: :string, required: true, doc: "What the business calls it."],
      correlate: [
        type: {:wrap_list, :atom},
        required: true,
        doc: "The fields that tell which run an event belongs to."
      ],
      accountable: [type: :atom, doc: "The actor a finding about the process is addressed to."],
      source: [type: :string, doc: "Where the process comes from in the material."]
    ]
  }

  # --- scenarios -----------------------------------------------------------------

  @given %Spark.Dsl.Entity{
    name: :given,
    describe: "An event that already happened.",
    target: Given,
    args: [:event, {:optional, :data}],
    schema: [
      event: [type: :atom, required: true, doc: "The event."],
      data: [type: :map, default: %{}, doc: "Its fields."]
    ]
  }

  @trigger_schema [
    name: [type: :atom, required: true, doc: "What is triggered."],
    data: [type: :map, default: %{}, doc: "Its fields."]
  ]

  @scenario_command %Spark.Dsl.Entity{
    name: :command,
    describe: "The command the scenario issues.",
    target: Trigger,
    args: [:name, {:optional, :data}],
    auto_set_fields: [kind: :command],
    schema: @trigger_schema
  }

  @scenario_on %Spark.Dsl.Entity{
    name: :on,
    describe: "The event the scenario delivers to a reaction.",
    target: Trigger,
    args: [:name, {:optional, :data}],
    auto_set_fields: [kind: :on],
    schema: @trigger_schema
  }

  @scenario_query %Spark.Dsl.Entity{
    name: :query,
    describe: "The query the scenario asks.",
    target: Trigger,
    args: [:name, {:optional, :data}],
    auto_set_fields: [kind: :query],
    schema: @trigger_schema
  }

  @expect %Spark.Dsl.Entity{
    name: :expect,
    describe: "An event the trigger produces.",
    target: Expect,
    args: [:event, {:optional, :data}],
    schema: [
      event: [type: :atom, required: true, doc: "The event."],
      data: [type: :map, default: %{}, doc: "Fields it must carry."]
    ]
  }

  @issues %Spark.Dsl.Entity{
    name: :issues,
    describe: "A command the reaction issues.",
    target: Issues,
    args: [:command, {:optional, :data}],
    schema: [
      command: [type: :atom, required: true, doc: "The command."],
      data: [type: :map, default: %{}, doc: "Fields it must carry."]
    ]
  }

  @sets %Spark.Dsl.Entity{
    name: :sets,
    describe: "A timer the process manager sets.",
    target: TimerRef,
    args: [:timer],
    auto_set_fields: [kind: :sets],
    schema: [timer: [type: :atom, required: true, doc: "The timer."]]
  }

  @cancels %Spark.Dsl.Entity{
    name: :cancels,
    describe: "A timer the process manager cancels.",
    target: TimerRef,
    args: [:timer],
    auto_set_fields: [kind: :cancels],
    schema: [timer: [type: :atom, required: true, doc: "The timer."]]
  }

  @answers %Spark.Dsl.Entity{
    name: :answers,
    describe:
      "What the query answers: the rows, or for a query that returns one, the row or nil " <>
        "(ESDM's result).",
    target: Answers,
    args: [:rows],
    schema: [
      rows: [
        type: :any,
        required: true,
        doc: "Rows as maps of the fields they must carry; exactly as many as answered."
      ]
    ]
  }

  @expected_state %Spark.Dsl.Entity{
    name: :state,
    describe:
      "What the process manager's run holds after the trigger: the givens and the " <>
        "delivered event folded, compared on the fields named (plan EP4).",
    target: ExpectedState,
    args: [:data],
    schema: [data: [type: :map, required: true, doc: "Fields of the state it must hold."]]
  }

  @scenario %Spark.Dsl.Entity{
    name: :scenario,
    describe: "Given events, a trigger, and what follows: an example the process owner reads.",
    target: Scenario,
    args: [:description],
    entities: [
      given: [@given],
      trigger: [@scenario_command, @scenario_on, @scenario_query],
      expect: [@expect],
      issues: [@issues],
      sets: [@sets],
      cancels: [@cancels],
      answers: [@answers],
      state: [@expected_state]
    ],
    schema: [
      description: [type: :string, required: true, doc: "The case, in the owner's words."],
      scope: [type: :atom, doc: "The unit, when the trigger does not say it."],
      actor: [type: :atom, doc: "The actor who issues the command."],
      rejected: [type: :atom, doc: "The invariant the command is refused on."],
      illustrates: [
        type: {:wrap_list, :atom},
        default: [],
        doc:
          "The rules this case shows: a constraint of the policy, process manager or query, " <>
            "or an invariant of the process manager."
      ],
      ended: [type: :boolean, default: false, doc: "Whether the process manager ends."]
    ]
  }

  @contract EhOsContract.DslWrappers.attach(
              %Spark.Dsl.Section{
                name: :contract,
                top_level?: true,
                describe: "One process, and everything born in it.",
                entities: [
                  @aggregate,
                  @dcb,
                  @policy,
                  @effect,
                  @process_manager,
                  @read_model,
                  @query,
                  @domain_service,
                  @consumes,
                  @publish,
                  @process,
                  @scenario
                ]
              },
              __MODULE__
            )

  use Spark.Dsl.Extension,
    sections: [@contract],
    transformers: [
      EhOsContract.Contract.Rules,
      EhOsContract.Contract.Build,
      EhOsContract.Contract.Generate
    ]
end

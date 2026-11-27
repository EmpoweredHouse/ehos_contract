defmodule EhosContract.Contract.Dsl do
  @moduledoc """
  The Spark extension behind `use EhosContract.Contract`.

  One top-level section, so every entity is written straight into the module body:
  the units that decide (aggregates and dynamic consistency boundaries) with their
  state, invariants, commands and events; what reacts to events (policies, effects,
  process managers); what is read (read models, queries); what enters from elsewhere
  (`consumes` from a sibling contract, `subscribe` from another application) and what
  leaves the application (`publish`); and scenarios. A process, its runs, stages and
  promises, is a module of its own (`EhosContract.Process`). The vocabulary is closed:
  a contract cannot add extensions.

  Options may stand beside a `do` block, as in `command :record_payment, "…", by:
  :reception do … end`.

  The structs this module defines are what Spark builds from each declaration. They stay inside the
  extension: readers get plain data from `EhosContract.Model`, never these structs.
  """

  defmodule Field do
    @moduledoc false
    defstruct [:name, :type, :label, :personal, :subject, :default, :issued_by, :supplied_by] ++
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
    defstruct [:name, :label, :source, :scope, :or_rejects, by: [], emits: [], rejects: []] ++
                [fields: [], constraints: [], creates: false, from: [], reads: []] ++
                [actor_is: [], __spark_metadata__: nil]
  end

  defmodule ActorIs do
    @moduledoc false
    defstruct [:field, :or_rejects, __spark_metadata__: nil]
  end

  defmodule Generated do
    # `identity :booking_id, generated: :uuid` in an aggregate (plan EM3): the identity,
    # and that the library gives each new aggregate one. Spark's option takes one
    # argument, so this two-argument form sets the two options it stands for.
    @moduledoc false

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
                Macro.to_string(opts) <>
                "; a field of it typed as another unit's or an entity's number, or by a domain " <>
                "value, is written in the list of its fields: `identity visit_id: {:id, :visit}`, " <>
                "`identity [:company_id, period_id: :period]`"
      end
    end
  end

  defmodule Event do
    @moduledoc false
    defstruct [:name, :label, :depends_on, :source, recorded_by: []] ++
                [schema_version: 1, fields: [], upcasts: [], __spark_metadata__: nil]
  end

  defmodule Upcast do
    @moduledoc false
    defstruct [:from, :function, rename: [], default: [], __spark_metadata__: nil]
  end

  defmodule Consults do
    @moduledoc false
    defstruct [:event, :where, match: [], __spark_metadata__: nil]
  end

  defmodule Status do
    @moduledoc false
    defstruct [:name, :label, :source, final: false, __spark_metadata__: nil]
  end

  defmodule Initial do
    @moduledoc false
    defstruct [:status, :on, :source, __spark_metadata__: nil]
  end

  defmodule Transition do
    @moduledoc false
    defstruct [:event, :to, :source, from: [], __spark_metadata__: nil]
  end

  defmodule Lifecycle do
    @moduledoc false
    defstruct statuses: [], initials: [], transitions: [], __spark_metadata__: nil
  end

  defmodule Unit do
    @moduledoc false
    defstruct [:kind, :name, :label, :source, :generated, identity: [], consults: [], state: []] ++
                [invariants: [], commands: [], events: [], lifecycle: []] ++
                [identity_types: %{}, __spark_metadata__: nil]

    # `identity [:period_id, company_id: {:id, :client}]` (plan DD, L3 (#286)): an identity
    # field may be typed, as another unit's or an entity's number, or, since #435, by a
    # domain value resting on `:id`, whose invariants then hold the key. The names stay a
    # list in `identity`, which everything reads, and the types go to `identity_types`,
    # which only the build and the rules about types read.
    @doc false
    @spec split_identity(%__MODULE__{}) :: {:ok, %__MODULE__{}}
    def split_identity(%__MODULE__{identity: identity} = unit) do
      {names, types} =
        Enum.map_reduce(identity, %{}, fn
          {name, type}, types -> {name, Map.put(types, name, type)}
          name, types -> {name, types}
        end)

      {:ok, %{unit | identity: names, identity_types: types}}
    end
  end

  defmodule Policy do
    @moduledoc false
    defstruct [:name, :label, :idempotency, :source, :delivery, handles: [], issues: []] ++
                [constraints: []] ++
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
    defstruct [:name, :label, :wait, :at, :source, issues: [], __spark_metadata__: nil]
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
    defstruct [:name, :label, :source, :delivery, :table, projects: [], fields: [], key: []] ++
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
    defstruct [:from, :as, :key, via: :consumes, events: [], fields: [], __spark_metadata__: nil]

    # #697: a subscriber names a published event by its parts, `{namespace, publication,
    # version}`, and the rules read the name they stand for, as a publisher's library
    # builds it. A string, the form before, is kept as written for D11 to refuse with
    # the key to write.
    @doc false
    @spec published_key(%__MODULE__{}) :: {:ok, %__MODULE__{}}
    def published_key(%__MODULE__{from: {_, _, _} = key} = subscribe),
      do: {:ok, %{subscribe | from: EhosContract.Contract.Published.of_key(key), key: key}}

    def published_key(%__MODULE__{} = subscribe), do: {:ok, subscribe}
  end

  defmodule Publish do
    @moduledoc false
    # `as` is what a contract wrote, which D11 refuses (#697); `published_as` the name
    # the library builds, set where the rules read the declarations.
    defstruct [:name, :as, :from, :published_as, version: 1, fields: [], idempotent_on: []] ++
                [__spark_metadata__: nil]
  end

  defmodule Promise do
    @moduledoc false
    defstruct [:name, :from, :eventually, :within, :or_else, :source, unverified: false] ++
                [waits_on: [], __spark_metadata__: nil]
  end

  defmodule Given do
    @moduledoc false
    defstruct [:event, :at, data: %{}, __spark_metadata__: nil]
  end

  defmodule GivenEntity do
    @moduledoc false
    defstruct [:entity, data: %{}, __spark_metadata__: nil]
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
    defstruct [
                :description,
                :target,
                :actor,
                :as,
                :rejected,
                ended: false,
                given: [],
                trigger: []
              ] ++
                [given_entities: []] ++
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
      ],
      supplied_by: [
        type: {:in, [:host]},
        doc:
          "Who gives this field's value instead of the caller: `:host`, through " <>
            "`EhosContract.Supplier`, for a value a decision depends on that a request could " <>
            "otherwise forge. Only on a command's field, or a recorded event's (F10)."
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

  # Plan DD, A1 (#247): the person who must issue the command, as a field of the unit's
  # state names them.
  @actor_is %Spark.Dsl.Entity{
    name: :actor_is,
    describe:
      "The person who must issue the command: the one a field of the unit's state names. " <>
        "Anyone else with the credential is refused on the invariant.",
    target: ActorIs,
    args: [:field],
    schema: [
      field: [
        type: :atom,
        required: true,
        doc:
          "The field of the unit's state, a non-personal `:id` an earlier event fills, that names the person."
      ],
      or_rejects: [
        type: :atom,
        required: true,
        doc: "The invariant of the unit, in the command's `rejects:`, it is refused on otherwise."
      ]
    ]
  }

  @command %Spark.Dsl.Entity{
    name: :command,
    describe: "An intention an actor or a reaction issues to a unit.",
    target: Command,
    args: [:name, :label],
    entities: [fields: [@field], constraints: [@constraint], actor_is: [@actor_is]],
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
      # Plan DD, T2a (#240): what the decision reads besides the command and the
      # unit's history, an entity the application keeps, asked of the host.
      reads: [
        type: :keyword_list,
        default: [],
        doc:
          "The entities the decision reads, `[service: :service_id]`: the name each row arrives " <>
            "under in the decision's third argument, and the command's field, typed " <>
            "`{:id, entity}`, that names it."
      ],
      source: [type: :string, doc: "Where the command comes from in the material."]
    ]
  }

  # Plan LC1: an aggregate's command may name the statuses of its lifecycle it is issued
  # in. A boundary's may not: it has no lifecycle, and a word it has only to be refused
  # would stand in its reference as if it meant something there.
  @aggregate_command %{
    @command
    | schema:
        @command.schema ++
          [
            from: [
              type: {:wrap_list, :atom},
              default: [],
              doc:
                "The statuses of its aggregate's lifecycle it may be issued in; dispatch " <>
                  "refuses it in any other, before the decision, on `or_rejects:`."
            ],
            or_rejects: [
              type: :atom,
              doc: "The invariant of the unit it is refused on outside the statuses in `from:`."
            ]
          ]
  }

  # Plan DD, V1 (#333): how a row written with an older version of the event's fields
  # reads in the current one, a step per version, so that the log is never rewritten.
  @upcast %Spark.Dsl.Entity{
    name: :upcast,
    describe: """
    How a row written with an older version of the event's fields reads in the next
    version: fields renamed, and fields that version did not have given a value. One per
    version below `schema_version`; a row is read through each from its own version up.
    """,
    examples: [
      "upcast from: 1, rename: [reason: :demand_reason], default: [priority: \"normal\"]",
      "upcast from: 1, function: :amount_from_minor"
    ],
    target: Upcast,
    schema: [
      from: [type: :pos_integer, required: true, doc: "The version this step reads."],
      rename: [
        type: :keyword_list,
        default: [],
        doc: "Each field of that version under its name in the next, as `old: :new`."
      ],
      default: [
        type: :keyword_list,
        default: [],
        doc:
          "A value for each field the next version has and that one did not; a row that " <>
            "holds the field keeps its own."
      ],
      function: [
        type: :atom,
        doc:
          "A function of the unit's implementation that takes a row of that version, as " <>
            "the log stores it, and gives the next version's, for a change a rename and a " <>
            "default cannot say; a step on its own, without `rename:` or `default:`."
      ]
    ]
  }

  @event %Spark.Dsl.Entity{
    name: :event,
    describe:
      "Something that occurred in the business, which the unit decides or an actor records.",
    target: Event,
    args: [:name, :label],
    entities: [fields: [@field], upcasts: [@upcast]],
    schema: [
      name: [type: :atom, required: true, doc: "The event's name."],
      label: [type: :string, required: true, doc: "The event, as the business states it."],
      depends_on: [type: :atom, doc: "The external system the event depends on."],
      recorded_by: [
        type: {:wrap_list, :atom},
        default: [],
        doc: "The actors who record it as an observation, when no command decides it."
      ],
      schema_version: [
        type: :pos_integer,
        default: 1,
        doc:
          "The version of its fields, raised with an `upcast` from each version below it " <>
            "when history exists; written into each row, and a row of a newer version than " <>
            "the code declares is not read."
      ],
      source: [type: :string, doc: "Where the event comes from in the material."]
    ]
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

  # Plan LC1 (#99): an aggregate's lifecycle — the statuses its decisions depend on,
  # in the client's words, and the events that move it between them. The engine
  # computes the status from the stream's event types alone, so a transition has no
  # condition on an event's fields: a rule about data is a decision's, or another
  # aggregate's. A boundary has none, since it spans streams and has no one thing
  # whose status it would be.
  @status %Spark.Dsl.Entity{
    name: :status,
    describe: "One status of the aggregate's lifecycle.",
    target: Status,
    args: [:name, :label],
    schema: [
      name: [type: :atom, required: true, doc: "The status's name."],
      label: [type: :string, required: true, doc: "What the business calls it."],
      final: [
        type: :boolean,
        default: false,
        doc: "Whether the aggregate's life ends in it: no transition leaves it."
      ],
      source: [type: :string, doc: "Where the status comes from in the material."]
    ]
  }

  @initial %Spark.Dsl.Entity{
    name: :initial,
    describe: "The status a new aggregate takes with the first event of its stream.",
    target: Initial,
    args: [:status],
    schema: [
      status: [type: :atom, required: true, doc: "The status it starts in."],
      on: [type: :atom, required: true, doc: "The event that starts it there."],
      source: [type: :string, doc: "Where the start comes from in the material."]
    ]
  }

  @transition %Spark.Dsl.Entity{
    name: :transition,
    describe: "An event that moves the aggregate from one status to another.",
    target: Transition,
    args: [:from, :event, :to],
    schema: [
      from: [type: {:wrap_list, :atom}, required: true, doc: "The statuses it leaves."],
      event: [type: :atom, required: true, doc: "The event of the aggregate that moves it."],
      to: [type: :atom, required: true, doc: "The status it enters."],
      source: [type: :string, doc: "Where the transition comes from in the material."]
    ]
  }

  @lifecycle %Spark.Dsl.Entity{
    name: :lifecycle,
    describe: "The aggregate's statuses and the events that move it between them.",
    target: Lifecycle,
    entities: [statuses: [@status], initials: [@initial], transitions: [@transition]]
  }

  @unit_entities [
    state: [@state],
    invariants: [@invariant],
    commands: [@command],
    events: [@event]
  ]

  @aggregate %Spark.Dsl.Entity{
    name: :aggregate,
    describe: "A unit that decides over one stream, identified by its identity.",
    target: Unit,
    args: [:name, :label],
    auto_set_fields: [kind: :aggregate],
    transform: {Unit, :split_identity, []},
    entities:
      Keyword.put(@unit_entities, :commands, [@aggregate_command]) ++ [lifecycle: [@lifecycle]],
    imports: [Generated],
    schema: [
      name: [type: :atom, required: true, doc: "The aggregate's name."],
      label: [type: :string, required: true, doc: "What the business calls it."],
      identity: [
        type: {:wrap_list, {:or, [:atom, {:tuple, [:atom, :any]}]}},
        required: true,
        doc:
          "The fields that identify one aggregate; injected into its state, commands and events. " <>
            "Each is an `:id`, or another unit's or an entity's when typed, or a domain value " <>
            "resting on `:id`, whose invariants dispatch holds the key to: " <>
            "`identity visit_id: {:id, :visit}`."
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
    transform: {Unit, :split_identity, []},
    entities: [consults: [@consults]] ++ @unit_entities,
    schema: [
      name: [type: :atom, required: true, doc: "The boundary's name."],
      label: [type: :string, required: true, doc: "What the business calls it."],
      identity: [
        type: {:wrap_list, {:or, [:atom, {:tuple, [:atom, :any]}]}},
        required: true,
        doc:
          "The fields that identify one boundary; injected into its state, commands and events. " <>
            "Each is an `:id`, or another unit's or an entity's when typed, or a domain value " <>
            "resting on `:id`, whose invariants dispatch holds the key to: " <>
            "`identity [company_id: {:id, :client}, period_id: :period]`."
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
  # Plan DD, X1: a policy and a read model left without `delivery` run inside the
  # transaction that records the event, which a reaction to another context's event
  # has to say out loud (X10), so the default is applied by `Build`, not here. A
  # declaration therefore holds `nil` for one left out: a rule asking how a policy or a
  # read model is delivered reads the model, where `Build` has resolved it.
  @undeclared_delivery "; `:in_transaction` when left out, which a reaction to an event of " <>
                         "another context has to state (X10)."

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
      delivery: [type: @delivery, doc: "When it runs" <> @undeclared_delivery],
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
      calls: [
        type: {:wrap_list, {:or, [:atom, {:tuple, [:atom, :atom]}]}},
        default: [],
        doc:
          "The external systems it calls: `:p1`, or `{:p1, :submit_report}` naming one of the " <>
            "system's operations, which a system that declares operations requires."
      ],
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
    args: [:name, :label],
    schema: [
      name: [type: :atom, required: true, doc: "The timer's name."],
      # Plan N3, the user's decision: required, and it names what the timer is for,
      # "Documentation due", not how long it waits, which `wait:` or `at:` says.
      label: [
        type: :string,
        required: true,
        doc: "What the timer is for, as the business says it; `wait:` or `at:` says when."
      ],
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
      delivery: [type: @delivery, doc: "When it is updated" <> @undeclared_delivery],
      table: [
        type: :string,
        doc:
          "The table its rows are kept in, which the application's migration creates; its " <>
            "`Row` is then an Ecto schema of that table."
      ],
      key: [
        type: {:wrap_list, :atom},
        default: [],
        doc:
          "The row fields that make a row unique, its table's primary key: required with " <>
            "`table:`, and only with it."
      ],
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

  # Plan N2: two mechanisms, two words. `consumes` reads a sibling contract's events
  # from this log; `subscribe` takes another application's published event into an
  # inbox (D12). Both build a `Consumes`, so the rules and the model, which already
  # told them apart by `from`, read one collection as before.
  @consumes %Spark.Dsl.Entity{
    name: :consumes,
    describe: "A sibling contract's events, read from this log.",
    target: Consumes,
    args: [:from, {:optional, :events}],
    no_depend_modules: [:from],
    # A published name, fields and an atom `as:` are refused by K1, which says why and
    # what to write instead, rather than by the schema, which could only say that the
    # value is not a module or that `field` is undefined.
    entities: [fields: [@field]],
    schema: [
      from: [
        type: {:or, [:atom, :string]},
        required: true,
        doc: "The sibling contract; a published name is `subscribe`d to."
      ],
      events: [type: {:wrap_list, :atom}, default: [], doc: "The sibling contract's events."],
      as: [
        type: {:or, [:atom, :keyword_list]},
        doc: "Renames of the sibling's events, `[old: :new]`."
      ]
    ]
  }

  @subscribe %Spark.Dsl.Entity{
    name: :subscribe,
    describe:
      "Another application's published event, taken into an inbox by a policy, with the " <>
        "fields this contract reads.",
    target: Consumes,
    args: [:from],
    auto_set_fields: [via: :subscribe],
    transform: {Consumes, :published_key, []},
    entities: [fields: [@field]],
    schema: [
      # A string is let through for D11 to refuse with the key to write (#697).
      from: [
        type: {:or, [{:tuple, [:atom, :atom, :pos_integer]}, :string]},
        required: true,
        doc:
          "The published event, by the publisher's namespace, its publication and its " <>
            "version, like `{:\"my-shop\", :entry_recorded, 1}`, for " <>
            "`\"my-shop.entry_recorded.v1\"`."
      ],
      as: [type: :atom, doc: "The event's name in this contract."]
    ]
  }

  @publish %Spark.Dsl.Entity{
    name: :publish,
    describe: "An integration event: the one way an event leaves the application.",
    target: Publish,
    args: [:name],
    schema: [
      name: [
        type: :atom,
        required: true,
        doc:
          "The publication's name, unique in the application. The published name is the " <>
            "domain's `name:`, this name and the version, like `\"my-shop.entry_recorded.v1\"`."
      ],
      version: [
        type: :pos_integer,
        default: 1,
        doc:
          "The version of what it carries. Raise it to remove a field or change its type; " <>
            "`mix ehos_contract.schema` refuses either at the same version."
      ],
      # Removed (#697): the library builds the name. Kept in the schema so that D11 can
      # refuse it with the line to write, rather than Spark with an unknown option.
      as: [
        type: :any,
        doc: "Removed: the library builds the name. A contract that names it does not compile."
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
        doc: "The fields that make two deliveries the same event."
      ]
    ]
  }

  # --- the promise, which a process module declares -------------------------------

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
      waits_on: [
        type: {:wrap_list, :atom},
        default: [],
        doc:
          "External systems of the domain it waits on through an earlier step: an outage " <>
            "of one inside its window excuses it."
      ],
      unverified: [type: :boolean, default: false, doc: "Not confirmed by the process owner."],
      source: [type: :string, doc: "Where the promise comes from."]
    ]
  }

  @doc false
  # The promise, as a process module writes it too (plan DD, P2b, #205): one shape in
  # both places, so a promise moved out of a contract is written as it was.
  @spec promise() :: Spark.Dsl.Entity.t()
  def promise, do: @promise

  # --- scenarios -----------------------------------------------------------------

  @given %Spark.Dsl.Entity{
    name: :given,
    describe: "An event that already happened.",
    target: Given,
    args: [:event, {:optional, :data}],
    schema: [
      event: [type: :atom, required: true, doc: "The event."],
      data: [type: :map, default: %{}, doc: "Its fields."],
      at: [
        type: :string,
        doc:
          "When it happened, an ISO 8601 timestamp with an offset; by default a minute " <>
            "after the given before it."
      ]
    ]
  }

  @doc false
  # The given, as a process module's scenario writes it too (plan DD, S2, #251).
  @spec given() :: Spark.Dsl.Entity.t()
  def given, do: @given

  # Plan DD, T2a (#240): the row of an entity a command reads, as the application keeps it
  # when the command arrives.
  @given_entity %Spark.Dsl.Entity{
    name: :given_entity,
    describe: "The row of an entity the scenario's command reads, as the application keeps it.",
    target: GivenEntity,
    args: [:entity, {:optional, :data}],
    schema: [
      entity: [type: :atom, required: true, doc: "The entity of the domain."],
      data: [type: :map, default: %{}, doc: "Its fields, its identity among them."]
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

  # Issue #430: what an actor of `recorded_by:` writes into the log, without a decision.
  @scenario_record %Spark.Dsl.Entity{
    name: :record,
    describe: "The event the scenario's actor records, as `EhosContract.record/3` does.",
    target: Trigger,
    args: [:name, {:optional, :data}],
    auto_set_fields: [kind: :record],
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

  # A process manager's state in a scenario: plan EP4.
  @expected_state %Spark.Dsl.Entity{
    name: :state,
    describe:
      "What the process manager's run holds after the trigger: the givens and the " <>
        "delivered event folded, compared on the fields named.",
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
      given_entities: [@given_entity],
      trigger: [@scenario_command, @scenario_on, @scenario_query, @scenario_record],
      expect: [@expect],
      issues: [@issues],
      sets: [@sets],
      cancels: [@cancels],
      answers: [@answers],
      state: [@expected_state]
    ],
    schema: [
      description: [type: :string, required: true, doc: "The case, in the owner's words."],
      target: [
        type: :atom,
        doc: "The unit or reaction the case is about, when the trigger does not say which."
      ],
      actor: [type: :atom, doc: "The actor who issues the command, or records the event."],
      as: [
        type: :string,
        doc:
          "The person issuing the command, as their credential's subject; beside `actor:`, for a " <>
            "command whose `actor_is` names who must issue it."
      ],
      rejected: [
        type: :atom,
        doc:
          "The invariant the command is refused on, or the invariant of a domain value its " <>
            "data breaks, which refuses it before any decision; for a recording, the invariant " <>
            "of a domain value its data breaks."
      ],
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

  @contract EhosContract.DslWrappers.attach(
              %Spark.Dsl.Section{
                name: :contract,
                top_level?: true,
                describe: "Everything born in the contract.",
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
                  @subscribe,
                  @publish,
                  @scenario
                ]
              },
              __MODULE__
            )

  use Spark.Dsl.Extension,
    sections: [@contract],
    transformers: [
      EhosContract.Contract.Rules,
      EhosContract.Contract.Build,
      EhosContract.Contract.Generate
    ]
end

defmodule EhOsContract.Domain.Dsl do
  @moduledoc """
  The Spark extension behind `use EhOsContract.Domain`.

  One top-level section, so every entity is written straight into the module body:
  subdomains, contexts with their glossary, actors, subjects of personal data, value types,
  entities, external systems and the relations between contexts. The vocabulary is closed:
  a domain module cannot add extensions.

  The structs below are what Spark builds from each declaration. They are the
  extension's own data and stay inside it: readers get plain data from
  `EhOsContract.Model`, never these structs.
  """

  defmodule Translation do
    @moduledoc false
    defstruct [:language, :text, :definition, avoid: [], __spark_metadata__: nil]
  end

  defmodule Avoid do
    @moduledoc false
    defstruct [:text, :reason, __spark_metadata__: nil]
  end

  defmodule Term do
    @moduledoc false
    defstruct [:text, :definition, :source, translations: [], avoid: [], __spark_metadata__: nil]
  end

  defmodule Subdomain do
    @moduledoc false
    defstruct [:name, :label, :type, :source, __spark_metadata__: nil]
  end

  defmodule Context do
    @moduledoc false
    defstruct [:name, :label, :subdomain, :language, :source, terms: [], __spark_metadata__: nil]
  end

  defmodule Actor do
    @moduledoc false
    defstruct [:name, :kind, :label, :backed_by, :context, :source, scope: []] ++
                [responsibilities: [], __spark_metadata__: nil]
  end

  defmodule Responsibility do
    @moduledoc false
    defstruct [:name, :label, :source, __spark_metadata__: nil]
  end

  defmodule Subject do
    @moduledoc false
    defstruct [:name, :label, :source, __spark_metadata__: nil]
  end

  defmodule Field do
    @moduledoc false
    defstruct [
      :name,
      :type,
      :label,
      :personal,
      :subject,
      :default,
      :issued_by,
      optional: false,
      __spark_metadata__: nil
    ]
  end

  defmodule ValueInvariant do
    @moduledoc false
    defstruct [:name, :label, :source, violated_by: [], satisfied_by: [], __spark_metadata__: nil]
  end

  defmodule Value do
    @moduledoc false
    defstruct [
      :name,
      :type,
      :unit,
      :label,
      :context,
      :source,
      fields: [],
      invariants: [],
      __spark_metadata__: nil
    ]
  end

  defmodule Entity do
    @moduledoc false
    defstruct [
      :name,
      :label,
      :context,
      :identified_by,
      :source,
      fields: [],
      __spark_metadata__: nil
    ]
  end

  defmodule External do
    @moduledoc false
    defstruct [
      :name,
      :label,
      :direction,
      :unavailable_looks_like,
      :expected_latency,
      :source,
      operations: [],
      __spark_metadata__: nil
    ]
  end

  defmodule Operation do
    @moduledoc false
    defstruct [:name, :label, :source, __spark_metadata__: nil]
  end

  defmodule Relation do
    @moduledoc false
    defstruct [:type, :upstream, :downstream, :source, between: [], terms: []] ++
                [__spark_metadata__: nil]
  end

  # The eight context-mapping patterns. Three are symmetric and are written
  # `between: [a, b]`; five have an upstream and a downstream (D5).
  @symmetric_relations [:partnership, :shared_kernel, :separate_ways]
  @directed_relations [
    :customer_supplier,
    :conformist,
    :anticorruption_layer,
    :open_host_service,
    :published_language
  ]

  @doc false
  @spec symmetric_relations() :: [atom()]
  def symmetric_relations, do: @symmetric_relations

  @doc false
  @spec directed_relations() :: [atom()]
  def directed_relations, do: @directed_relations

  @avoid %Spark.Dsl.Entity{
    name: :avoid,
    describe: "A word that must not be used for this term, and why.",
    target: Avoid,
    args: [:text],
    schema: [
      text: [type: :string, required: true, doc: "The word to avoid."],
      reason: [type: :string, doc: "Why it must not be used."]
    ]
  }

  @translation %Spark.Dsl.Entity{
    name: :translation,
    describe: "The term in another language, with what it means there, as in ESDM.",
    target: Translation,
    args: [:language, :text],
    entities: [avoid: [@avoid]],
    schema: [
      language: [type: :atom, required: true, doc: "The language, e.g. `:en`."],
      text: [type: :string, required: true, doc: "The term in that language."],
      definition: [type: :string, required: true, doc: "What it means, in that language."]
    ]
  }

  @term %Spark.Dsl.Entity{
    name: :term,
    describe: "One entry of a context's glossary.",
    target: Term,
    args: [:text],
    entities: [translations: [@translation], avoid: [@avoid]],
    schema: [
      text: [type: :string, required: true, doc: "The term, in the context's language."],
      definition: [type: :string, required: true, doc: "What it means in this context."],
      source: [type: :string, doc: "Where the definition comes from."]
    ]
  }

  @subdomain %Spark.Dsl.Entity{
    name: :subdomain,
    describe: "A part of the business the domain covers, named, with its kind.",
    target: Subdomain,
    args: [:name, :label],
    schema: [
      name: [type: :atom, required: true, doc: "The subdomain's name."],
      label: [type: :string, required: true, doc: "What the business calls it."],
      type: [
        type: {:one_of, [:core, :supporting, :generic]},
        required: true,
        doc: "The kind of subdomain."
      ],
      source: [type: :string, doc: "Where the subdomain comes from in the material."]
    ]
  }

  @context %Spark.Dsl.Entity{
    name: :context,
    describe: "A bounded context: a part of the domain with its own language.",
    target: Context,
    args: [:name, :label],
    entities: [terms: [@term]],
    schema: [
      name: [type: :atom, required: true, doc: "The context's name."],
      label: [type: :string, required: true, doc: "What the business calls it."],
      subdomain: [type: :atom, required: true, doc: "The subdomain the context belongs to."],
      language: [type: :atom, doc: "The context's language, when it differs from the domain's."],
      source: [type: :string, doc: "Where the context comes from in the material."]
    ]
  }

  # Plan EP5b: named prose, rung 0 of the ladder — what the material says the actor
  # answers for. Nothing runs it; a page and the glossary read it.
  @responsibility %Spark.Dsl.Entity{
    name: :responsibility,
    describe: "What the actor answers for, as the material says it: named prose.",
    target: Responsibility,
    args: [:name, :label],
    schema: [
      name: [type: :atom, required: true, doc: "The responsibility's name."],
      label: [type: :string, required: true, doc: "What the actor answers for."],
      source: [type: :string, doc: "Where it comes from in the material."]
    ]
  }

  @actor %Spark.Dsl.Entity{
    name: :actor,
    describe: "Who issues commands: a kind of person, or a system.",
    target: Actor,
    args: [:name, :kind, :label],
    entities: [responsibilities: [@responsibility]],
    schema: [
      name: [type: :atom, required: true, doc: "The actor's name."],
      kind: [type: {:one_of, [:human, :system]}, required: true, doc: "A person or a system."],
      label: [type: :string, required: true, doc: "What the business calls it."],
      backed_by: [type: :atom, doc: "The external system a system actor stands for."],
      context: [type: :atom, doc: "The context the actor belongs to."],
      scope: [
        type: {:wrap_list, :atom},
        default: [],
        doc: "The fields a grant to this actor narrows query answers by."
      ],
      source: [type: :string, doc: "Where the actor comes from in the material."]
    ]
  }

  @subject %Spark.Dsl.Entity{
    name: :subject,
    describe: "A kind of person whose personal data may be erased.",
    target: Subject,
    args: [:name, :label],
    schema: [
      name: [type: :atom, required: true, doc: "The subject's name."],
      label: [type: :string, required: true, doc: "What the business calls them."],
      source: [type: :string, doc: "Where the subject comes from in the material."]
    ]
  }

  @field %Spark.Dsl.Entity{
    name: :field,
    describe: "One field of a value with fields.",
    target: Field,
    args: [:name, :type],
    schema: [
      name: [type: :atom, required: true, doc: "The field's name."],
      type: [type: :any, required: true, doc: "A built-in type or a value of this domain."],
      optional: [type: :boolean, default: false, doc: "Whether the field may be absent."],
      label: [type: :string, doc: "What the business calls it."],
      personal: [type: :atom, doc: "The field holding the identifier of whose data this is."],
      subject: [type: :atom, doc: "The subject this identifier field identifies."],
      default: [type: :any, doc: "Only in a contract's state."],
      issued_by: [
        type: :atom,
        doc: "The external of this domain that gives this value."
      ]
    ]
  }

  # A value's invariant is checked (plan EL2b): the implementation of the value
  # defines one function per invariant, dispatch holds every value of the type to
  # them, and each example becomes a test. Examples are plain data, as a scenario's
  # are (`EhOsContract.Contract.Data`).
  @value_invariant %Spark.Dsl.Entity{
    name: :invariant,
    describe: "What is true of every value of the type, with values that break it and keep it.",
    target: ValueInvariant,
    args: [:name, :label],
    schema: [
      name: [
        type: :atom,
        required: true,
        doc: "The invariant's name, and the name of the function that checks it."
      ],
      label: [type: :string, required: true, doc: "The rule, as the business states it."],
      violated_by: [
        type: {:list, :any},
        required: true,
        doc: "Values that break it, as plain data: each is a test that the check refuses it."
      ],
      satisfied_by: [
        type: {:list, :any},
        required: true,
        doc: "Values that keep it, as plain data: each is a test that the check lets it through."
      ],
      source: [type: :string, doc: "Where the rule comes from in the material."]
    ]
  }

  @value %Spark.Dsl.Entity{
    name: :value,
    describe: "A value type: one built-in type with an optional unit, or a set of fields.",
    target: Value,
    args: [:name, {:optional, :type}],
    entities: [fields: [@field], invariants: [@value_invariant]],
    schema: [
      name: [type: :atom, required: true, doc: "The value's name, used as a field type."],
      type: [type: :any, doc: "The built-in type, when the value is not a set of fields."],
      unit: [type: :atom, doc: "What a number counts, e.g. `:grosze`."],
      label: [type: :string, doc: "What the business calls it."],
      context: [type: :atom, doc: "The context the value belongs to."],
      source: [type: :string, doc: "Where the value comes from in the material."]
    ]
  }

  @entity %Spark.Dsl.Entity{
    name: :entity,
    describe:
      "Reference data with an identity that no event of this log changes: a period, an item of " <>
        "a catalogue. Its rows are the application's; a field names one as `{:id, entity}`.",
    target: Entity,
    args: [:name, :label],
    entities: [fields: [@field]],
    schema: [
      name: [type: :atom, required: true, doc: "The entity's name."],
      label: [type: :string, required: true, doc: "What the business calls it."],
      context: [type: :atom, required: true, doc: "The context that owns it."],
      identified_by: [type: :atom, required: true, doc: "The field that identifies it."],
      source: [type: :string, doc: "Where the entity comes from in the material."]
    ]
  }

  # Plan EP5a: what a system does when an effect calls it, ESDM's `capabilities`. Not
  # named so here: a capability is what EHOS grants an actor (`EhOsContract.Capability`).
  @operation %Spark.Dsl.Entity{
    name: :operation,
    describe:
      "What the system does when an effect calls it; once a system declares one, every " <>
        "`calls:` to it names one, `calls: {:p1, :submit_report}`.",
    target: Operation,
    args: [:name, :label],
    schema: [
      name: [type: :atom, required: true, doc: "The operation's name."],
      label: [type: :string, required: true, doc: "What it does, as the business says it."],
      source: [type: :string, doc: "Where the operation comes from in the material."]
    ]
  }

  @external %Spark.Dsl.Entity{
    name: :external,
    describe: "An external system, named after the business fact rather than the vendor.",
    target: External,
    args: [:name, :label],
    entities: [operations: [@operation]],
    schema: [
      name: [type: :atom, required: true, doc: "The external's name."],
      label: [type: :string, required: true, doc: "What the business calls it."],
      direction: [
        type: {:one_of, [:inbound, :outbound, :bidirectional]},
        required: true,
        doc: "Which way data flows."
      ],
      unavailable_looks_like: [type: :string, doc: "How an outage shows to the business."],
      expected_latency: [type: :any, doc: "How long an answer usually takes, `{n, unit}`."],
      source: [type: :string, doc: "Where the external comes from in the material."]
    ]
  }

  @relation %Spark.Dsl.Entity{
    name: :relation,
    describe: "How two contexts relate: one of the eight context-mapping patterns.",
    target: Relation,
    args: [:type],
    schema: [
      type: [
        type: {:one_of, @symmetric_relations ++ @directed_relations},
        required: true,
        doc: "The mapping pattern."
      ],
      upstream: [type: :atom, doc: "The upstream context of a directed relation."],
      downstream: [type: :atom, doc: "The downstream context of a directed relation."],
      between: [
        type: {:list, :atom},
        default: [],
        doc: "The two contexts of a symmetric relation."
      ],
      terms: [
        type: {:list, {:tuple, [:string, :string]}},
        default: [],
        doc:
          "Terms the relation translates, as pairs: the word of the first end, upstream or " <>
            "the first of `between:`, and the word of the second, each a term of its " <>
            "context's glossary. `{\"Wizyta\", \"Wizyta\"}`."
      ],
      source: [type: :string, doc: "Where the relation comes from in the material."]
    ]
  }

  # `context`, `term`, `value` and `entity` take a block, so they also take their options
  # beside it (v2 §16, D13).
  @domain EhOsContract.DslWrappers.attach(
            %Spark.Dsl.Section{
              name: :domain,
              top_level?: true,
              describe: "The vocabulary contracts share.",
              entities: [
                @subdomain,
                @context,
                @actor,
                @subject,
                @value,
                @entity,
                @external,
                @relation
              ]
            },
            __MODULE__
          )

  use Spark.Dsl.Extension,
    sections: [@domain],
    transformers: [EhOsContract.Domain.Rules, EhOsContract.Domain.Build]
end

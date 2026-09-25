defmodule EhOsContract.Domain.Dsl do
  @moduledoc """
  The Spark extension behind `use EhOsContract.Domain` (v2 §4.1–4.3).

  One top-level section, so every entity is written straight into the module body:
  contexts with their glossary, actors, subjects of personal data, value types,
  external systems and the relations between contexts. The vocabulary is closed:
  a domain module cannot add extensions.

  The structs below are what Spark builds from each declaration. They are the
  extension's own data and stay inside it: readers get plain data from
  `EhOsContract.Model`, never these structs.
  """

  defmodule Translation do
    @moduledoc false
    defstruct [:language, :text, __spark_metadata__: nil]
  end

  defmodule Avoid do
    @moduledoc false
    defstruct [:text, __spark_metadata__: nil]
  end

  defmodule Term do
    @moduledoc false
    defstruct [:text, :definition, :source, translations: [], avoid: [], __spark_metadata__: nil]
  end

  defmodule Context do
    @moduledoc false
    defstruct [:name, :label, :subdomain, :language, :source, terms: [], __spark_metadata__: nil]
  end

  defmodule Actor do
    @moduledoc false
    defstruct [:name, :kind, :label, :backed_by, :context, scope: [], __spark_metadata__: nil]
  end

  defmodule Subject do
    @moduledoc false
    defstruct [:name, :label, __spark_metadata__: nil]
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
      optional: false,
      __spark_metadata__: nil
    ]
  end

  defmodule Value do
    @moduledoc false
    defstruct [:name, :type, :unit, :label, :context, fields: [], __spark_metadata__: nil]
  end

  defmodule External do
    @moduledoc false
    defstruct [
      :name,
      :label,
      :direction,
      :unavailable_looks_like,
      :expected_latency,
      __spark_metadata__: nil
    ]
  end

  defmodule Relation do
    @moduledoc false
    defstruct [:type, :upstream, :downstream, between: [], terms: [], __spark_metadata__: nil]
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

  @translation %Spark.Dsl.Entity{
    name: :translation,
    describe: "The term in another language.",
    target: Translation,
    args: [:language, :text],
    schema: [
      language: [type: :atom, required: true, doc: "The language, e.g. `:en`."],
      text: [type: :string, required: true, doc: "The term in that language."]
    ]
  }

  @avoid %Spark.Dsl.Entity{
    name: :avoid,
    describe: "A word that must not be used for this term.",
    target: Avoid,
    args: [:text],
    schema: [text: [type: :string, required: true, doc: "The word to avoid."]]
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

  @context %Spark.Dsl.Entity{
    name: :context,
    describe: "A bounded context: a part of the domain with its own language.",
    target: Context,
    args: [:name, :label],
    entities: [terms: [@term]],
    schema: [
      name: [type: :atom, required: true, doc: "The context's name."],
      label: [type: :string, required: true, doc: "What the business calls it."],
      subdomain: [
        type: {:one_of, [:core, :supporting, :generic]},
        required: true,
        doc: "The kind of subdomain."
      ],
      language: [type: :atom, doc: "The context's language, when it differs from the domain's."],
      source: [type: :string, doc: "Where the context comes from in the material."]
    ]
  }

  @actor %Spark.Dsl.Entity{
    name: :actor,
    describe: "Who issues commands: a kind of person, or a system.",
    target: Actor,
    args: [:name, :kind, :label],
    schema: [
      name: [type: :atom, required: true, doc: "The actor's name."],
      kind: [type: {:one_of, [:human, :system]}, required: true, doc: "A person or a system."],
      label: [type: :string, required: true, doc: "What the business calls it."],
      backed_by: [type: :atom, doc: "The external system a system actor stands for."],
      context: [type: :atom, doc: "The context the actor belongs to."],
      scope: [
        type: {:wrap_list, :atom},
        default: [],
        doc: "The fields a grant to this actor narrows query answers by (D10)."
      ]
    ]
  }

  @subject %Spark.Dsl.Entity{
    name: :subject,
    describe: "A kind of person whose personal data may be erased (v2 §14).",
    target: Subject,
    args: [:name, :label],
    schema: [
      name: [type: :atom, required: true, doc: "The subject's name."],
      label: [type: :string, required: true, doc: "What the business calls them."]
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
      default: [type: :any, doc: "Only in a contract's state."]
    ]
  }

  @value %Spark.Dsl.Entity{
    name: :value,
    describe: "A value type: one built-in type with an optional unit, or a set of fields.",
    target: Value,
    args: [:name, {:optional, :type}],
    entities: [fields: [@field]],
    schema: [
      name: [type: :atom, required: true, doc: "The value's name, used as a field type."],
      type: [type: :any, doc: "The built-in type, when the value is not a set of fields."],
      unit: [type: :atom, doc: "What a number counts, e.g. `:grosze`."],
      label: [type: :string, doc: "What the business calls it."],
      context: [type: :atom, doc: "The context the value belongs to."]
    ]
  }

  @external %Spark.Dsl.Entity{
    name: :external,
    describe: "An external system, named after the business fact rather than the vendor.",
    target: External,
    args: [:name, :label],
    schema: [
      name: [type: :atom, required: true, doc: "The external's name."],
      label: [type: :string, required: true, doc: "What the business calls it."],
      direction: [
        type: {:one_of, [:inbound, :outbound, :bidirectional]},
        required: true,
        doc: "Which way data flows."
      ],
      unavailable_looks_like: [type: :string, doc: "How an outage shows to the business."],
      expected_latency: [type: :any, doc: "How long an answer usually takes, `{n, unit}`."]
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
        type: {:list, :string},
        default: [],
        doc: "Terms the relation shares or translates."
      ]
    ]
  }

  # `context`, `term` and `value` take a block, so they also take their options
  # beside it (v2 §16, D13).
  @domain EhOsContract.DslWrappers.attach(
            %Spark.Dsl.Section{
              name: :domain,
              top_level?: true,
              describe: "The vocabulary contracts share.",
              entities: [@context, @actor, @subject, @value, @external, @relation]
            },
            __MODULE__
          )

  use Spark.Dsl.Extension,
    sections: [@domain],
    transformers: [EhOsContract.Domain.Rules, EhOsContract.Domain.Build]
end

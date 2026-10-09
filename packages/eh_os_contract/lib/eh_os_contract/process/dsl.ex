defmodule EhOsContract.Process.Dsl do
  @moduledoc """
  The Spark extension behind `use EhOsContract.Process`.

  One top-level section, so every entity is written straight into the module body:
  what tells one run from another (`correlate`), the stages and the events of the
  contracts each one includes, the events that end a run (`ends_on`), the promises
  and the deadline. The vocabulary is closed: a process module cannot add
  extensions.

  A stage's `include:` names contract modules without a compile dependency, as
  `consumes` does (`no_depend_modules`): a change to a contract recompiles no
  process that names it. A promise is the contract's own entity, so it is written
  alike in both.

  A scenario shows a promise judged: the events that happened and
  when, the moments an external system was seen unavailable, and the verdict the
  promise gets at a moment. Its `given` is the contract's.

  The structs below are what Spark builds from each declaration. They stay inside the
  extension: readers get plain data from `EhOsContract.Model`, never these structs.
  """

  defmodule Correlate do
    @moduledoc false
    defstruct fields: [], __spark_metadata__: nil
  end

  defmodule Stage do
    @moduledoc false
    defstruct [:name, :label, include: [], __spark_metadata__: nil]
  end

  defmodule EndsOn do
    @moduledoc false
    defstruct events: [], __spark_metadata__: nil
  end

  defmodule Deadline do
    @moduledoc false
    defstruct [:within, unverified: false, __spark_metadata__: nil]
  end

  # Plan DD, S2 (#251): a scenario of a promise.
  defmodule Scenario do
    @moduledoc false
    defstruct [
      :description,
      :verdict,
      :via,
      given: [],
      outages: [],
      trigger: [],
      __spark_metadata__: nil
    ]
  end

  defmodule Outage do
    @moduledoc false
    defstruct [:external, :at, __spark_metadata__: nil]
  end

  defmodule Judged do
    @moduledoc false
    defstruct [:name, :at, __spark_metadata__: nil]
  end

  @correlate %Spark.Dsl.Entity{
    name: :correlate,
    describe: "The fields that tell which run an event belongs to, in order.",
    target: Correlate,
    args: [:fields],
    schema: [
      fields: [
        type: {:wrap_list, :atom},
        required: true,
        doc: "One field, or a list of them; every included event carries each."
      ]
    ]
  }

  @stage %Spark.Dsl.Entity{
    name: :stage,
    describe: "One stage of the process, in order, with the contracts' events it includes.",
    target: Stage,
    args: [:name, {:optional, :label}],
    no_depend_modules: [:include],
    schema: [
      name: [type: :atom, required: true, doc: "The stage's name."],
      label: [type: :string, doc: "What the business calls it."],
      include: [
        type: {:list, {:tuple, [:atom, {:wrap_list, :atom}]}},
        default: [],
        doc:
          "The events it includes, `{Contract, :event}` or `{Contract, [:event, …]}`; the " <>
            "contract is named without a compile dependency."
      ]
    ]
  }

  @ends_on %Spark.Dsl.Entity{
    name: :ends_on,
    describe: "The included events that end a run.",
    target: EndsOn,
    args: [:events],
    schema: [
      events: [type: {:wrap_list, :atom}, required: true, doc: "Included events, by name."]
    ]
  }

  @deadline %Spark.Dsl.Entity{
    name: :deadline,
    describe: "How long a run may take, from its first event to one it `ends_on`.",
    target: Deadline,
    args: [:within],
    schema: [
      within: [type: :any, required: true, doc: "`{n, unit}`, in a fixed unit."],
      unverified: [type: :boolean, default: false, doc: "Not confirmed by the process owner."]
    ]
  }

  @outage %Spark.Dsl.Entity{
    name: :outage,
    describe: "A moment an external system was seen unavailable.",
    target: Outage,
    args: [:external],
    schema: [
      external: [type: :atom, required: true, doc: "An external system of the domain."],
      at: [
        type: :string,
        required: true,
        doc: "When, an ISO 8601 timestamp with an offset."
      ]
    ]
  }

  @judged %Spark.Dsl.Entity{
    name: :promise,
    describe: "The promise the scenario judges, and the moment it is judged.",
    target: Judged,
    args: [:name],
    schema: [
      name: [type: :atom, required: true, doc: "A promise of the process."],
      at: [
        type: :string,
        required: true,
        doc: "The moment of judgement, an ISO 8601 timestamp with an offset."
      ]
    ]
  }

  @scenario %Spark.Dsl.Entity{
    name: :scenario,
    describe:
      "Given events and when they happened, the moments a system was down, and the verdict " <>
        "a promise gets: an example the process owner reads.",
    target: Scenario,
    args: [:description],
    entities: [
      given: [EhOsContract.Contract.Dsl.given()],
      outages: [@outage],
      trigger: [@judged]
    ],
    schema: [
      description: [type: :string, required: true, doc: "The case, in the owner's words."],
      verdict: [
        type: :atom,
        doc: "What the promise gets: `:satisfied`, `:violated`, `:pending` or `:suspended`."
      ],
      via: [
        type: :atom,
        doc: "For `:satisfied`, the route that kept it: `:eventually` or `:or_else`."
      ]
    ]
  }

  @process EhOsContract.DslWrappers.attach(
             %Spark.Dsl.Section{
               name: :process,
               top_level?: true,
               describe:
                 "A process across contracts: its runs, stages, end, promises, deadline and scenarios.",
               entities: [
                 @correlate,
                 @stage,
                 @ends_on,
                 EhOsContract.Contract.Dsl.promise(),
                 @deadline,
                 @scenario
               ]
             },
             __MODULE__
           )

  use Spark.Dsl.Extension,
    sections: [@process],
    transformers: [EhOsContract.Process.Rules, EhOsContract.Process.Build]
end

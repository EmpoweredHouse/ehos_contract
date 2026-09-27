defmodule EhOsContract.ScenarioCase do
  @moduledoc """
  One test per scenario of a v2 contract, run against its implementation (v2 §4.5):

      defmodule Rehmed.VisitSettlementScenariosTest do
        use EhOsContract.ScenarioCase, contract: Rehmed.Contracts.VisitSettlement
      end

  The successor of `EhOsContract.ContractExample`, and in `lib/` for the reason that
  one is: a consumer's suite has to be able to call it.

  **What a scenario runs.** For a command to a unit, the unit's state starts from
  its defaults and folds every `given` through `evolve/2`; the command's callback
  then decides. For an event delivered to a policy, its callback is called with the
  event; to a process manager, its state folds the givens and the reaction's
  callback, or the timer's, is called with it. `sets`, `cancels` and `ended` are the
  declaration's, which S6 has already compared with the scenario when the contract
  compiled; what runs is what the code decides.

  **What it asserts keeps `ContractExample`'s semantics.** The events a scenario
  expects, and the commands it says are issued, **appear among those produced, in
  that order — a subsequence, not equality**; each with the fields its data names,
  and any others. Pinning every event made an example of one rule break whenever
  the flow grew by one event. `rejected` asserts the rejection on exactly that
  invariant. Whatever a decision returns is also held to its declaration: an event
  the command does not emit fails the scenario, whatever it expects.

  **A query's scenario** (ESDM's read model scenario) projects every `given`
  through the implementation of the read model the query reads, asks the query with
  the trigger's data as its parameters, and compares what it answers with
  `answers`: **exactly as many rows, each matching a different row on the fields it
  names**, in any order. Unlike events, extra rows fail: an answer is wholly
  determined by the givens, and "the other clinic's visit is not in it" is often
  what the scenario is about. The projection writes the host's tables, so this runs
  in a transaction of `config :eh_os_contract, :repo` that is rolled back, and a
  test module with a query's scenario checks out an Ecto sandbox connection when the
  repo's pool is the sandbox.

  **Data.** Scenario data is plain data (`EhOsContract.Next.Contract.Data`): an ISO
  8601 string becomes the `DateTime` or `Date` of a `:timestamp` or `:date` field
  here, and a digit string or an integer the `Decimal` of a `:decimal`, including
  inside a domain value. The unit's identity is the scenario's own: the value a
  scenario gives it anywhere, or `"scenario"`. Every given, and then the trigger,
  gets `__meta__` with `occurred_at` a minute after the one before, from
  2026-01-01 09:00 UTC, and the command its scenario's `actor`. A given also has an
  `id` and a `position`, 1, 2, … in the order listed, as an event read back from the
  log has.

  **A domain's examples** (plan EL2b). `use EhOsContract.ScenarioCase, domain:
  Rehmed.Domain` writes one test per example of every value's invariant, against the
  module bound with `use Rehmed.Domain, value: :name`: the invariant's function
  answers `false` for each of its `violated_by:`, and every invariant of the value
  answers `true` for each of its `satisfied_by:`, since a value that keeps one
  invariant and breaks another is no example of a value. An example is plain data,
  cast as a scenario's is.

  **A domain service's rules** (plan EL2b). Every example of a rule,
  `examples: [{[1, 3], 0}]`, is a test too: the function, called through the module
  the contract generates, returns the example's result — compared as values, so a
  decimal `2.50` is `2.5`.

  **Which implementation.** The one module of the contract's application whose
  `__eh_os_implementation__/0` names the scenario's target; `implementations:` names
  them instead, for contracts compiled outside an application. A target without
  one fails its scenario with that reason: a contract without code is legal (D3), and
  a scenario test of one is not.
  """

  import ExUnit.Assertions

  alias EhOsContract.{Meta, Model, Rejection}
  alias EhOsContract.Next.Contract.{Callbacks, Data}

  @epoch ~U[2026-01-01 09:00:00Z]
  @built_in EhOsContract.Domain.Rules.built_in_types()

  # The identity of a scenario's stream when the scenario gives none: it is one stream.
  @stream "scenario"

  @doc false
  defmacro __using__(opts) do
    if Keyword.has_key?(opts, :domain), do: domain_case(opts), else: contract_case(opts)
  end

  defp domain_case(opts) do
    domain = Keyword.fetch!(opts, :domain)
    implementations = Keyword.get(opts, :implementations)
    async = Keyword.get(opts, :async, true)

    quote do
      use ExUnit.Case, async: unquote(async)

      for example <- EhOsContract.ScenarioCase.examples(unquote(domain)) do
        @eh_os_contract_example example
        test EhOsContract.ScenarioCase.describe(example) do
          EhOsContract.ScenarioCase.run_example(
            unquote(domain),
            @eh_os_contract_example,
            unquote(implementations)
          )
        end
      end
    end
  end

  defp contract_case(opts) do
    contract = Keyword.fetch!(opts, :contract)
    implementations = Keyword.get(opts, :implementations)
    async = Keyword.get(opts, :async, true)

    quote do
      use ExUnit.Case, async: unquote(async)

      if Enum.any?(
           EhOsContract.Model.fetch(unquote(contract)).scenarios,
           &(&1.target.kind == :query)
         ) do
        setup do
          EhOsContract.ScenarioCase.checkout()
        end
      end

      for scenario <- EhOsContract.Model.fetch(unquote(contract)).scenarios do
        @eh_os_contract_scenario scenario
        test "scenario: #{scenario.description}" do
          EhOsContract.ScenarioCase.run(
            unquote(contract),
            @eh_os_contract_scenario,
            unquote(implementations)
          )
        end
      end

      for example <- EhOsContract.ScenarioCase.rule_examples(unquote(contract)) do
        @eh_os_contract_rule_example example
        test EhOsContract.ScenarioCase.describe(@eh_os_contract_rule_example) do
          EhOsContract.ScenarioCase.run_rule_example(
            unquote(contract),
            @eh_os_contract_rule_example,
            unquote(implementations)
          )
        end
      end
    end
  end

  @typedoc "One example of a domain service's rule, as a test runs it."
  @type rule_example :: %{
          service: atom(),
          function: atom(),
          rule: atom(),
          arguments: [term()],
          result: term()
        }

  @doc "Every example of every rule of `contract`'s domain services, in declaration order."
  @spec rule_examples(module()) :: [rule_example()]
  def rule_examples(contract) do
    for service <- Model.fetch(contract).domain_services,
        function <- service.functions,
        rule <- function.rules,
        {arguments, result} <- rule.examples do
      %{
        service: service.name,
        function: function.name,
        rule: rule.name,
        arguments: arguments,
        result: result
      }
    end
  end

  @doc """
  Runs one example of a domain service's rule of `contract`: calls the function
  through the module the contract generates — so its arguments and result are held
  to their types and invariants, as a decision's call is — with the implementation
  found as a scenario's is, and asserts it returns the example's result.
  """
  @spec run_rule_example(module(), rule_example(), [module()] | nil) :: true
  def run_rule_example(contract, example, implementations \\ nil) do
    model = Model.fetch(contract)

    implementation =
      implementation!(model, %{kind: :domain_service, name: example.service}, implementations)

    service = Enum.find(model.domain_services, &(&1.name == example.service))
    function = Enum.find(service.functions, &(&1.name == example.function))
    domain = domain(model)

    {arguments, expected} =
      try do
        {Enum.zip_with(function.arguments, example.arguments, &cast(&1.type, &2, domain)),
         cast(function.returns.type, example.result, domain)}
      catch
        {:unfit, problem} -> flunk("example of #{describe(example)}: #{problem}")
      end

    returned =
      EhOsContract.DomainService.call(
        model.module,
        example.service,
        example.function,
        arguments,
        implementation
      )

    assert same?(returned, expected),
           "#{call(example)} returned #{shown(returned)}, and rule #{inspect(example.rule)} " <>
             "gives #{shown(expected)}"
  end

  defp call(example),
    do: "#{example.function}(#{Enum.map_join(example.arguments, ", ", &shown/1)})"

  # A list of small integers is a list here, never a charlist.
  defp shown(term), do: inspect(term, charlists: :as_lists)

  # What a decimal is, not how many digits it was written with: 2.50 is 2.5.
  defp same?(%Decimal{} = a, %Decimal{} = b), do: Decimal.equal?(a, b)

  defp same?(a, b) when is_list(a) and is_list(b),
    do: length(a) == length(b) and Enum.all?(Enum.zip(a, b), fn {x, y} -> same?(x, y) end)

  defp same?(%{} = a, %{} = b) when not is_struct(a) and not is_struct(b),
    do: Map.keys(a) == Map.keys(b) and Enum.all?(a, fn {k, v} -> same?(v, Map.fetch!(b, k)) end)

  defp same?(a, b), do: a == b

  @typedoc "One example of a value's invariant, as a test runs it."
  @type example :: %{
          value: atom(),
          invariant: atom(),
          kind: :violated_by | :satisfied_by,
          data: term()
        }

  @doc "Every example of every invariant of `domain`'s values, in declaration order."
  @spec examples(module()) :: [example()]
  def examples(domain) do
    for value <- Model.fetch(domain).values,
        invariant <- value.invariants,
        kind <- [:violated_by, :satisfied_by],
        data <- Map.fetch!(invariant, kind),
        do: %{value: value.name, invariant: invariant.name, kind: kind, data: data}
  end

  @doc "The name of an example's test: a value's invariant's, or a rule's."
  @spec describe(example() | rule_example()) :: String.t()
  def describe(%{rule: rule} = example) do
    "rule #{inspect(rule)} of #{example.service}.#{example.function}: #{call(example)} returns " <>
      shown(example.result)
  end

  def describe(%{kind: kind} = example) do
    verb = if kind == :violated_by, do: "breaks", else: "keeps"

    "invariant #{inspect(example.invariant)} of value #{inspect(example.value)}: " <>
      "#{shown(example.data)} #{verb} it"
  end

  @doc """
  Runs one example of a value's invariant of `domain` against the value's
  implementation. `implementations`, when given, is where it is looked for instead
  of the domain's application.
  """
  @spec run_example(module(), example(), [module()] | nil) :: true
  def run_example(domain, example, implementations \\ nil) do
    model = Model.fetch(domain)
    implementation = implementation!(model, %{kind: :value, name: example.value}, implementations)
    value = Enum.find(model.values, &(&1.name == example.value))
    data = cast_example(example, Map.new(model.values, &{&1.name, &1}))

    checked =
      case example.kind do
        :violated_by -> [example.invariant]
        :satisfied_by -> Enum.map(value.invariants, & &1.name)
      end

    for invariant <- checked do
      answer = apply(implementation, invariant, [data])
      expected = example.kind == :satisfied_by

      assert is_boolean(answer),
             "#{inspect(implementation)}.#{invariant}/1 answered #{inspect(answer)}; the check " <>
               "of an invariant answers true or false"

      assert answer == expected,
             if(expected,
               do:
                 "#{inspect(example.data)} is given as a value of #{inspect(example.value)} " <>
                   "that keeps #{inspect(example.invariant)}, and " <>
                   "#{inspect(implementation)}.#{invariant}/1 answers that it breaks " <>
                   "#{inspect(invariant)}",
               else:
                 "#{inspect(example.data)} breaks invariant #{inspect(invariant)} of value " <>
                   "#{inspect(example.value)}, and #{inspect(implementation)}.#{invariant}/1 " <>
                   "lets it through"
             )
    end

    true
  end

  defp cast_example(example, domain) do
    cast(example.value, example.data, domain)
  catch
    {:unfit, problem} -> flunk("example of #{describe(example)}: #{problem}")
  end

  @doc """
  Checks out an Ecto sandbox connection of `config :eh_os_contract, :repo` for the
  test, when that repo's pool is the sandbox: a query's scenario projects into the
  host's tables.
  """
  @spec checkout() :: :ok
  def checkout do
    with repo when repo != nil <- Application.get_env(:eh_os_contract, :repo),
         Ecto.Adapters.SQL.Sandbox <- repo.config()[:pool] do
      owner = Ecto.Adapters.SQL.Sandbox.start_owner!(repo, shared: false)
      ExUnit.Callbacks.on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)
    end

    :ok
  end

  @doc """
  Runs one scenario of `contract` against its implementation, and asserts what the
  scenario says. `implementations`, when given, is where the implementation is
  looked for instead of the contract's application.
  """
  @spec run(module(), map(), [module()] | nil) :: true
  def run(contract, scenario, implementations \\ nil) do
    model = Model.fetch(contract)
    implementation = implementation!(model, scenario.target, implementations)
    identity = identity(scenario)
    times = Stream.iterate(@epoch, &DateTime.add(&1, 60)) |> Enum.take(length(scenario.given) + 1)
    {given_times, [now]} = Enum.split(times, length(scenario.given))

    # A given is an event read back from a log, as dispatch hands one to its consumers:
    # with an id and a position, in the order the scenario lists them.
    givens =
      for {{given, at}, position} <- Enum.with_index(Enum.zip(scenario.given, given_times), 1) do
        event = message(model, :event, given.event, given.data, identity, at, nil)
        %{event | __meta__: %{event.__meta__ | id: Ecto.UUID.generate(), position: position}}
      end

    run(model, scenario, implementation, identity, givens, now, implementations)
  end

  defp run(model, %{target: %{kind: :query}} = scenario, impl, _identity, givens, _now, found) do
    query = Enum.find(model.queries, &(&1.name == scenario.target.name))
    read_model = Enum.find(model.read_models, &(&1.name == query.reads))
    projection = implementation!(model, %{kind: :read_model, name: read_model.name}, found)
    domain = domain(model)
    repo = Application.fetch_env!(:eh_os_contract, :repo)

    params =
      struct!(
        Model.module_for(model, :query, query.name),
        cast_data(query.params, scenario.trigger.data, domain)
      )

    {:error, {:answered, answer}} =
      repo.transaction(fn ->
        for {given, event} <- Enum.zip(scenario.given, givens) do
          assert apply(projection, given.event, [event]) == :ok,
                 "read model #{inspect(read_model.name)} returned something other than :ok " <>
                   "for #{inspect(given.event)}"
        end

        repo.rollback({:answered, apply(impl, query.name, [params, %{actor: nil}])})
      end)

    row = Module.concat(Model.module_for(model, :read_model, read_model.name), Row)

    answered =
      case {query.returns, answer} do
        {:one, nil} -> []
        {:one, %{__struct__: _} = one} -> [one]
        {:one, _other} -> :unfit
        {:many, many} -> many
      end

    assert is_list(answered) and Enum.all?(answered, &is_struct(&1, row)),
           "query #{inspect(query.name)} answered #{inspect(answer)}, and it answers " <>
             if(query.returns == :one,
               do: "one %#{inspect(row)}{} or nil",
               else: "a list of them"
             )

    expected = Enum.map(scenario.answers, &cast_data(read_model.fields, &1, domain))

    assert length(expected) == length(answered) and matched?(expected, answered),
           """
           the scenario requires the query to answer exactly these rows, in any order:
             #{Enum.map_join(expected, "\n  ", &inspect/1)}
           and it answered:
             #{Enum.map_join(answered, "\n  ", &inspect(Map.from_struct(&1)))}
           """
  end

  defp run(model, scenario, impl, identity, givens, now, _found),
    do: run(model, scenario, impl, identity, givens, now)

  # Every expected row matches a different answered row, trying each pairing: a row
  # that names fewer fields may match several, and the first fit need not be the one
  # that lets the others fit.
  defp matched?([], _answered), do: true

  defp matched?([expected | rest], answered) do
    answered
    |> Enum.with_index()
    |> Enum.any?(fn {row, index} ->
      matches?(expected, row) and matched?(rest, List.delete_at(answered, index))
    end)
  end

  defp run(model, %{target: %{kind: kind, name: name}} = scenario, impl, identity, givens, now)
       when kind in [:aggregate, :dcb] do
    unit = Enum.find(model.units, &(&1.name == name))
    initial = Map.new(unit.identity, &{&1, identity.(&1) || @stream})

    state =
      fold(
        impl,
        struct(Module.concat(Model.module_for(model, kind, name), State), initial),
        givens
      )

    command = scenario.trigger.name

    decided =
      message(model, :command, command, scenario.trigger.data, identity, now, scenario.actor)

    result = apply(impl, command, [decided, state])
    emits = Enum.find(model.commands, &(&1.name == command)).emits

    case {scenario.rejected, result} do
      {nil, {:ok, events}} ->
        produced = within!(model, :event, events, emits, "command #{inspect(command)} emits")
        subsequence!(expected(model, :event, scenario.expect, & &1.event), :event, produced)

      {nil, other} ->
        flunk(
          "expected command #{inspect(command)} to emit events, and it returned #{inspect(other)}"
        )

      # The same variable twice: the invariant rejected on is the one expected.
      {invariant, {:error, %Rejection{invariant: invariant}}} ->
        true

      {invariant, other} ->
        flunk(
          "expected command #{inspect(command)} to be rejected on #{inspect(invariant)}, " <>
            "and it returned #{inspect(other)}"
        )
    end
  end

  defp run(model, %{target: %{kind: kind, name: name}} = scenario, impl, identity, givens, now)
       when kind in [:policy, :process_manager] do
    trigger = scenario.trigger.name
    %{callbacks: callbacks} = Callbacks.of(model, kind, name)
    callback = Enum.find(callbacks, &(&1.name == trigger))

    state =
      if kind == :process_manager do
        pm = Enum.find(model.process_managers, &(&1.name == name))

        domain = domain(model)

        run =
          for f <- pm.state.fields,
              f.name in pm.correlate,
              into: %{},
              do: {f.name, correlated(f, identity, domain)}

        fold(impl, struct(Module.concat(Model.module_for(model, kind, name), State), run), givens)
      end

    issued =
      case {callback, kind} do
        {nil, _} ->
          []

        {%{arity: 1}, :process_manager} ->
          unwrap!(apply(impl, trigger, [state]), trigger)

        {%{arity: 1}, :policy} ->
          event = message(model, :event, trigger, scenario.trigger.data, identity, now, nil)
          unwrap!(apply(impl, trigger, [event]), trigger)

        {%{arity: 2}, _} ->
          event = message(model, :event, trigger, scenario.trigger.data, identity, now, nil)
          unwrap!(apply(impl, trigger, [event, state]), trigger)
      end

    allowed = if callback, do: callback.issues, else: []

    produced =
      within!(model, :command, issued, allowed, "the reaction to #{inspect(trigger)} issues")

    subsequence!(expected(model, :command, scenario.issues, & &1.command), :command, produced)
  end

  # What a scenario expects, with its data cast as the struct's would be.
  defp expected(model, kind, declarations, name) do
    domain = domain(model)

    for declaration <- declarations do
      {_module, fields, _identity} = shape(model, kind, name.(declaration))
      %{event: name.(declaration), data: cast_data(fields, declaration.data, domain)}
    end
  end

  # What the scenario gives a correlation field, cast to its type. One it does not
  # give is "scenario" when it is an :id, as an identity is; any other type has no
  # value a runner could make up.
  defp correlated(%{name: name, type: type}, identity, domain) do
    case {identity.(name), type} do
      {nil, :id} -> @stream
      {value, _} -> cast(type, value, domain)
    end
  end

  defp unwrap!({:ok, commands}, _trigger) when is_list(commands), do: commands

  defp unwrap!(other, trigger),
    do:
      flunk(
        "expected the reaction to #{inspect(trigger)} to issue, and it returned #{inspect(other)}"
      )

  defp fold(impl, state, givens) do
    if function_exported?(impl, :evolve, 2),
      do: Enum.reduce(givens, state, &impl.evolve(&2, &1)),
      else: state
  end

  # Every struct produced is one the declaration allows: the backstop v2 §5 keeps at
  # run time, since a decision can build a struct the macros never saw.
  defp within!(model, kind, structs, allowed, what) do
    modules = Map.new(allowed, &{Model.module_for(model, kind, &1), &1})

    for struct <- structs do
      assert is_struct(struct),
             "#{what} structs, and the code produced #{inspect(struct)}, which is not one"

      name = Map.get(modules, struct.__struct__)

      assert name,
             "#{inspect(struct.__struct__)} is not among what #{what}, #{inspect(allowed)}"

      {name, struct}
    end
  end

  # `expected` in `produced`, in that order, not necessarily adjacent: each with the
  # fields its data names.
  defp subsequence!(expected, kind, produced) do
    names = Enum.map(produced, &elem(&1, 0))

    assert subsequence?(expected, produced),
           """
           the scenario requires these #{kind}s to appear among those produced, in this order:
             #{Enum.map_join(expected, "\n  ", &"#{inspect(&1.event)} #{inspect(&1.data)}")}
           and the code produced:
             #{Enum.map_join(Enum.zip(names, produced), "\n  ", fn {n, {_, s}} -> "#{inspect(n)} #{inspect(Map.drop(Map.from_struct(s), [:__meta__]))}" end)}
           """
  end

  defp subsequence?([], _produced), do: true
  defp subsequence?(_expected, []), do: false

  defp subsequence?([%{event: name, data: data} | rest] = expected, [{name, struct} | more]) do
    if matches?(data, struct),
      do: subsequence?(rest, more),
      else: subsequence?(expected, more)
  end

  defp subsequence?(expected, [_ | more]), do: subsequence?(expected, more)

  defp matches?(data, struct) do
    Enum.all?(data, fn {key, value} -> Map.get(struct, key) == value end)
  end

  # --- building structs from scenario data ------------------------------------------

  # The value a scenario gives a field of its stream anywhere, or nil.
  defp identity(scenario) do
    data =
      Enum.map(scenario.given, & &1.data) ++
        [scenario.trigger.data] ++
        Enum.map(scenario.expect, & &1.data) ++ Enum.map(scenario.issues, & &1.data)

    fn field -> Enum.find_value(data, &Map.get(&1, field)) end
  end

  # A struct from scenario data: its fields cast to their types, the identity its
  # unit injects filled in where the data leaves it out, and `__meta__`.
  defp message(model, kind, name, data, identity, at, actor) do
    {module, fields, injected} = shape(model, kind, name)

    ids =
      for field <- injected,
          not Map.has_key?(data, field),
          into: %{},
          do: {field, identity.(field) || @stream}

    values = cast_data(fields, Map.merge(ids, data), domain(model))
    struct!(module, Map.put(values, :__meta__, %Meta{occurred_at: at, actor: actor}))
  end

  # Data S3 could not check — a domain value's, a sibling event's — may not fit, and a
  # scenario then fails naming the field rather than crashing in a parser.
  defp cast_data(fields, data, domain) do
    types = Map.new(fields, &{&1.name, &1.type})

    for {key, value} <- data, Map.has_key?(types, key), into: %{} do
      try do
        {key, cast(Map.fetch!(types, key), value, domain)}
      catch
        {:unfit, problem} -> flunk("scenario data, field #{inspect(key)}: #{problem}")
      end
    end
  end

  # The struct, its fields, and the identity its unit injects: a local declaration's,
  # a sibling's event under its name there, or a received event's as this contract
  # declares it.
  defp shape(model, :command, name) do
    command = Enum.find(model.commands, &(&1.name == name))

    {Model.module_for(model, :command, name), command.fields, injected(model, command.unit)}
  end

  defp shape(model, :event, name) do
    module = Model.module_for(model, :event, name)

    case Enum.find(model.events, &(&1.name == name)) do
      %{fields: fields, unit: unit} ->
        {module, fields, injected(model, unit)}

      nil ->
        {fields, injected} = consumed_fields(model, name)
        {module, fields, injected}
    end
  end

  defp injected(model, unit), do: Enum.find(model.units, &(&1.name == unit)).identity

  defp consumed_fields(model, name) do
    case Model.consumed(model, name) do
      {:published, fields} ->
        {fields, []}

      {:contract, from, original} ->
        sibling = Model.fetch(from)
        event = Enum.find(sibling.events, &(&1.name == original))
        {event.fields, injected(sibling, event.unit)}
    end
  end

  defp domain(model) do
    if Code.ensure_loaded?(model.domain) and
         function_exported?(model.domain, :__eh_os_contract_model__, 0),
       do: Map.new(model.domain.__eh_os_contract_model__().values, &{&1.name, &1}),
       else: %{}
  end

  defp cast(_type, nil, _domain), do: nil

  defp cast(type, value, domain)
       when type in @built_in or (is_tuple(type) and elem(type, 0) == :enum) do
    case Data.problems(type, value) do
      [] -> built_in(type, value, domain)
      [problem | _] -> throw({:unfit, problem})
    end
  end

  defp cast({:list, inner}, values, domain) when is_list(values),
    do: Enum.map(values, &cast(inner, &1, domain))

  defp cast(type, value, domain) when is_atom(type) and is_map_key(domain, type) do
    case Map.fetch!(domain, type) do
      %{type: nil, fields: fields} when is_map(value) ->
        types = Map.new(fields, &{&1.name, &1.type})
        Map.new(value, fn {key, v} -> {key, cast(Map.get(types, key), v, domain)} end)

      %{type: nil} ->
        throw({:unfit, "#{inspect(value)} is not a map of the fields of #{inspect(type)}"})

      %{type: inner} ->
        cast(inner, value, domain)
    end
  end

  defp cast(_type, value, _domain), do: value

  defp built_in(:timestamp, value, _domain) when is_binary(value) do
    {:ok, at, _offset} = DateTime.from_iso8601(value)
    at
  end

  defp built_in(:date, value, _domain) when is_binary(value), do: Date.from_iso8601!(value)

  defp built_in(:decimal, value, _domain) when is_binary(value) or is_integer(value),
    do: Decimal.new(value)

  defp built_in(_type, value, _domain), do: value

  # --- finding the implementation ---------------------------------------------------

  defp implementation!(model, %{kind: kind, name: name}, implementations) do
    candidates = implementations || modules(model.module)

    found =
      for module <- candidates,
          Code.ensure_loaded?(module),
          function_exported?(module, :__eh_os_implementation__, 0),
          match?(
            %{contract: c, kind: ^kind, name: ^name} when c == model.module,
            module.__eh_os_implementation__()
          ),
          do: module

    case found do
      [one] ->
        one

      [] ->
        flunk(
          "no module implements #{kind} #{inspect(name)} of #{inspect(model.module)}, so its " <>
            "scenario has nothing to run; bind one with `use #{inspect(model.module)}, " <>
            "#{kind}: #{inspect(name)}`"
        )

      many ->
        flunk(
          "#{kind} #{inspect(name)} of #{inspect(model.module)} has #{length(many)} implementations: #{inspect(many)}"
        )
    end
  end

  defp modules(contract) do
    case Application.get_application(contract) do
      nil -> []
      app -> Application.spec(app, :modules) || []
    end
  end
end

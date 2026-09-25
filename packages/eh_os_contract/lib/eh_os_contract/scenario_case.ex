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

  **Data.** Scenario data is plain data (`EhOsContract.Next.Contract.Data`): an ISO
  8601 string becomes the `DateTime` or `Date` of a `:timestamp` or `:date` field
  here, and a digit string or an integer the `Decimal` of a `:decimal`, including
  inside a domain value. The unit's identity is the scenario's own: the value a
  scenario gives it anywhere, or `"scenario"`. Every given, and then the trigger,
  gets `__meta__` with `occurred_at` a minute after the one before, from
  2026-01-01 09:00 UTC, and the command its scenario's `actor`.

  **Which implementation.** The one module of the contract's application whose
  `__eh_os_implementation__/0` names the scenario's target; `implementations:` names
  them instead, for contracts compiled outside an application. A target without
  one fails its scenario with that reason: a contract without code is legal (D3), and
  a scenario test of one is not.
  """

  import ExUnit.Assertions

  alias EhOsContract.{Meta, Model, Rejection}
  alias EhOsContract.Next.Contract.Callbacks

  @epoch ~U[2026-01-01 09:00:00Z]

  @doc false
  defmacro __using__(opts) do
    contract = Keyword.fetch!(opts, :contract)
    implementations = Keyword.get(opts, :implementations)
    async = Keyword.get(opts, :async, true)

    quote do
      use ExUnit.Case, async: unquote(async)

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
    end
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

    givens =
      for {given, at} <- Enum.zip(scenario.given, given_times),
          do: message(model, :event, given.event, given.data, identity, at, nil)

    run(model, scenario, implementation, identity, givens, now)
  end

  defp run(model, %{target: %{kind: kind, name: name}} = scenario, impl, identity, givens, now)
       when kind in [:aggregate, :dcb] do
    unit = Enum.find(model.units, &(&1.name == name))
    initial = Map.new(unit.identity, &{&1, identity.(&1)})

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
        run = Map.new(pm.correlate, &{&1, identity.(&1)})
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

  # The value a scenario gives an identity field anywhere, or "scenario": one stream.
  defp identity(scenario) do
    data =
      Enum.map(scenario.given, & &1.data) ++
        [scenario.trigger.data] ++
        Enum.map(scenario.expect, & &1.data) ++ Enum.map(scenario.issues, & &1.data)

    fn field -> Enum.find_value(data, "scenario", &Map.get(&1, field)) end
  end

  # A struct from scenario data: its fields cast to their types, the identity its
  # unit injects filled in where the data leaves it out, and `__meta__`.
  defp message(model, kind, name, data, identity, at, actor) do
    {module, fields, injected} = shape(model, kind, name)

    ids =
      for field <- injected,
          not Map.has_key?(data, field),
          into: %{},
          do: {field, identity.(field)}

    values = cast_data(fields, Map.merge(ids, data), domain(model))
    struct!(module, Map.put(values, :__meta__, %Meta{occurred_at: at, actor: actor}))
  end

  defp cast_data(fields, data, domain) do
    types = Map.new(fields, &{&1.name, &1.type})

    for {key, value} <- data,
        Map.has_key?(types, key),
        into: %{},
        do: {key, cast(Map.fetch!(types, key), value, domain)}
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
    Enum.find_value(model.consumes, fn
      %{kind: :published, as: ^name, fields: fields} ->
        {fields, []}

      %{kind: :contract, from: from, events: events, renames: renames} ->
        original = Enum.find(events, &(Map.get(renames, &1, &1) == name))

        if original do
          sibling = Model.fetch(from)
          event = Enum.find(sibling.events, &(&1.name == original))
          {event.fields, injected(sibling, event.unit)}
        end

      _ ->
        nil
    end)
  end

  defp domain(model) do
    if Code.ensure_loaded?(model.domain) and
         function_exported?(model.domain, :__eh_os_contract_model__, 0),
       do: Map.new(model.domain.__eh_os_contract_model__().values, &{&1.name, &1}),
       else: %{}
  end

  defp cast(_type, nil, _domain), do: nil

  defp cast(:timestamp, value, _domain) when is_binary(value) do
    {:ok, at, _offset} = DateTime.from_iso8601(value)
    at
  end

  defp cast(:date, value, _domain) when is_binary(value), do: Date.from_iso8601!(value)

  defp cast(:decimal, value, _domain) when is_binary(value) or is_integer(value),
    do: Decimal.new(value)

  defp cast({:list, inner}, values, domain) when is_list(values),
    do: Enum.map(values, &cast(inner, &1, domain))

  defp cast(type, value, domain) when is_atom(type) and is_map_key(domain, type) do
    case Map.fetch!(domain, type) do
      %{type: nil, fields: fields} when is_map(value) ->
        types = Map.new(fields, &{&1.name, &1.type})
        Map.new(value, fn {key, v} -> {key, cast(Map.get(types, key), v, domain)} end)

      %{type: inner} ->
        cast(inner, value, domain)
    end
  end

  defp cast(_type, value, _domain), do: value

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

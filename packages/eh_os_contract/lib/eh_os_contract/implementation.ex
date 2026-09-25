defmodule EhOsContract.Implementation do
  @moduledoc """
  How code binds to a v2 contract, and what the contract checks in it while it
  compiles (v2 §5, layer L4).

      defmodule Rehmed.Settlement.VisitSettlement do
        use Rehmed.Contracts.VisitSettlement, aggregate: :visit_settlement

        @impl true
        def record_payment(%RecordPayment{visit_id: id, amount: a}, _state),
          do: emit(%PaymentRecorded{visit_id: id, amount: a})
      end

  `use C, aggregate: :name` — or `dcb:`, `policy:`, `effect:`, `process_manager:`,
  `read_model:`, `query:` — names exactly one declaration of the contract `C`, and
  brings in:

  - `@behaviour` of the module `C` generated for it (`EhOsContract.Next.Contract.Callbacks`
    says which callbacks);
  - aliases for the structs it touches: a unit's commands, events and `State`; a
    reaction's events and the commands it issues; a read model's events and `Row`; a
    query's parameters and rows. An event consumed from a sibling under a new name
    is aliased under that name;
  - `emit/1`, `reject/1` and `issue/1`, which check at the call site what they are
    given;
  - a check, before the module compiles, that every callback is defined and that
    `evolve/2` handles every event its state is kept from.

  The dependency runs one way: the implementation compiles against the contract and
  the structs it expands, and the contract names no implementation (v2 §8).

  **The rules** (v2 §6, L4), each a `CompileError` at the call site, or at the
  `use` line for the ones checked before the module compiles:

  - **I1.** `use C, …` names one declaration that exists; a misspelling gets a
    did-you-mean.
  - **I2.** Every callback of the behaviour is defined, and the error shows the
    clause to add.
  - **I3.** `evolve/2` has a clause for every event, or a catch-all: an unguarded
    variable. It reads struct patterns, not guards, so a clause written
    `when is_struct(event, A)` covers nothing; write `%A{}` instead.
  - **I4.** `emit/1` takes struct literals — `%E{}`, a list of them, or a `for`
    producing them — of events allowed where it is called: inside a command's
    callback, that command's `emits:`; anywhere else in the module, those of any
    command of the unit.
  - **I5.** `reject/1` takes an atom literal among the command's `rejects:`, with
    the same reading of where.
  - **I6.** `issue/1` takes command struct literals the reaction's `issues:` names.
  - **I7.** `emit/1` and `reject/1` only in an aggregate or a boundary, `issue/1`
    only in a policy or a process manager, and none of them in an effect, a read
    model or a query.

  What stays at run time (v2 §5): field values against their types, capabilities,
  and the backstop that what a decision returns is within its declaration.
  """

  alias EhOsContract.Model
  alias EhOsContract.Next.Contract.Callbacks

  @kinds [:aggregate, :dcb, :policy, :effect, :process_manager, :read_model, :query]

  @typedoc "What `__eh_os_implementation__/0` says about an implementation."
  @type t :: %{
          contract: module(),
          kind: atom(),
          name: atom(),
          emitted: %{{atom(), arity()} => [atom()]}
        }

  # --- binding ----------------------------------------------------------------------

  @doc false
  @spec bind(module(), keyword(), Macro.Env.t()) :: Macro.t()
  def bind(contract, opts, caller) do
    model = contract.__eh_os_contract_model__()
    {kind, name} = declaration!(model, opts, caller)

    aliases =
      for {module, as} <- aliases(model, kind, name) do
        quote do: alias(unquote(module), as: unquote(as), warn: false)
      end

    quote do
      @behaviour unquote(Model.module_for(model, kind, name))
      @eh_os_contract_implementation %{
        contract: unquote(contract),
        kind: unquote(kind),
        name: unquote(name),
        line: unquote(caller.line)
      }
      Module.register_attribute(__MODULE__, :eh_os_contract_emitted, accumulate: true)
      import EhOsContract.Implementation, only: [emit: 1, reject: 1, issue: 1], warn: false
      unquote_splicing(aliases)
      @before_compile EhOsContract.Implementation
    end
  end

  # I1: exactly one kind, naming a declaration that exists.
  defp declaration!(model, opts, caller) do
    where = "use #{inspect(model.module)}"
    unknown = Keyword.keys(opts) -- @kinds

    if unknown != [] do
      refuse!(
        caller,
        "I1: #{where} takes one of #{inspect(@kinds)}; #{inspect(unknown)} is not among them"
      )
    end

    case Keyword.take(opts, @kinds) do
      [{kind, name}] ->
        names = names(model, kind)

        if name in names do
          {kind, name}
        else
          refuse!(caller, "I1: #{where}: #{unknown_name(model, kind, name, names)}")
        end

      [] ->
        refuse!(caller, "I1: #{where} names no declaration; write `#{where}, aggregate: :name`")

      many ->
        refuse!(caller, "I1: #{where} names #{inspect(many)}; an implementation binds to one")
    end
  end

  defp unknown_name(model, kind, name, names) do
    elsewhere = for other <- @kinds, other != kind, name in names(model, other), do: other

    cond do
      elsewhere != [] ->
        "#{inspect(name)} is not #{a(kind)} but #{Enum.map_join(elsewhere, " and ", &a/1)}"

      suggestion = closest(name, names) ->
        "there is no #{human(kind)} #{inspect(name)}; did you mean #{inspect(suggestion)}?"

      true ->
        "there is no #{human(kind)} #{inspect(name)}; the contract declares #{inspect(names)}"
    end
  end

  defp names(model, kind) when kind in [:aggregate, :dcb],
    do: for(u <- model.units, u.kind == kind, do: u.name)

  defp names(model, kind) do
    key =
      Map.fetch!(
        %{
          policy: :policies,
          effect: :effects,
          process_manager: :process_managers,
          read_model: :read_models,
          query: :queries
        },
        kind
      )

    Enum.map(Map.fetch!(model, key), & &1.name)
  end

  defp closest(name, names) do
    names
    |> Enum.map(&{&1, String.jaro_distance(Atom.to_string(name), Atom.to_string(&1))})
    |> Enum.filter(fn {_, distance} -> distance > 0.8 end)
    |> Enum.max_by(fn {_, distance} -> distance end, fn -> {nil, 0} end)
    |> elem(0)
  end

  defp human(kind), do: kind |> Atom.to_string() |> String.replace("_", " ")

  defp a(kind) when kind in [:aggregate, :effect], do: "an #{human(kind)}"
  defp a(kind), do: "a #{human(kind)}"

  @doc """
  The structs an implementation of the declaration touches, each with the alias it
  gets: `{module, alias}`.
  """
  @spec aliases(map(), atom(), atom()) :: [{module(), module()}]
  def aliases(model, kind, name) do
    behaviour = Model.module_for(model, kind, name)
    event = &{Model.module_for(model, :event, &1), camel(&1)}
    command = &{Model.module_for(model, :command, &1), camel(&1)}

    pairs =
      case kind do
        unit when unit in [:aggregate, :dcb] ->
          declared = Enum.find(model.units, &(&1.name == name))

          Enum.concat([
            for(c <- model.commands, c.unit == name, do: command.(c.name)),
            for(e <- model.events, e.unit == name, do: event.(e.name)),
            for(c <- declared.consults, do: event.(c.event)),
            [{Module.concat(behaviour, State), State}]
          ])

        :policy ->
          policy = Enum.find(model.policies, &(&1.name == name))
          Enum.map(policy.handles, event) ++ Enum.map(policy.issues, command)

        :effect ->
          Enum.map(Enum.find(model.effects, &(&1.name == name)).handles, event)

        :process_manager ->
          %{evolve: evolve, callbacks: callbacks} = Callbacks.of(model, kind, name)
          triggers = if evolve, do: evolve.events, else: []
          handled = for c <- callbacks, c.arity == 2, do: c.name

          Enum.concat([
            Enum.map(Enum.uniq(triggers ++ handled), event),
            callbacks |> Enum.flat_map(& &1.issues) |> Enum.uniq() |> Enum.map(command),
            [{Module.concat(behaviour, State), State}]
          ])

        :read_model ->
          read_model = Enum.find(model.read_models, &(&1.name == name))
          Enum.map(read_model.projects, event) ++ [{Module.concat(behaviour, Row), Row}]

        :query ->
          query = Enum.find(model.queries, &(&1.name == name))
          reads = Model.module_for(model, :read_model, query.reads)
          [{behaviour, camel(name)}, {Module.concat(reads, Row), Row}]
      end

    Enum.uniq(pairs)
  end

  defp camel(name), do: Module.concat([name |> Atom.to_string() |> Macro.camelize()])

  # --- the macros -------------------------------------------------------------------

  @doc """
  The events a decision produces: `{:ok, [event]}`. Takes struct literals of events
  allowed where it is called (I4, I7).
  """
  defmacro emit(events) do
    impl = implementation!(__CALLER__, "emit/1")
    only!(impl, [:aggregate, :dcb], "emit/1", "an aggregate or a dcb", __CALLER__)
    model = impl.contract.__eh_os_contract_model__()
    {allowed, where} = allowed(model, impl, __CALLER__.function, :emits)

    names =
      for module <- literal_structs!(events, "emit/1", __CALLER__) do
        name =
          Enum.find(allowed, &(Model.module_for(model, :event, &1) == module)) ||
            refuse!(
              __CALLER__,
              "I4: emit/1 gets %#{inspect(module)}{}, which is not among the events #{where} " <>
                "emits, #{inspect(allowed)}"
            )

        name
      end

    Module.put_attribute(__CALLER__.module, :eh_os_contract_emitted, {__CALLER__.function, names})
    quote do: {:ok, List.wrap(unquote(events))}
  end

  @doc """
  A command refused on an invariant: `{:error, %EhOsContract.Rejection{}}`. Takes an
  atom literal among the invariants the command rejects on (I5, I7).
  """
  defmacro reject(invariant) do
    impl = implementation!(__CALLER__, "reject/1")
    only!(impl, [:aggregate, :dcb], "reject/1", "an aggregate or a dcb", __CALLER__)
    model = impl.contract.__eh_os_contract_model__()
    {allowed, where} = allowed(model, impl, __CALLER__.function, :rejects)

    cond do
      not is_atom(invariant) ->
        refuse!(
          __CALLER__,
          "I5: reject/1 takes the invariant as an atom literal, so it is known at compile " <>
            "time; got #{Macro.to_string(invariant)}"
        )

      invariant not in allowed ->
        refuse!(
          __CALLER__,
          "I5: reject/1 gets #{inspect(invariant)}, which is not among the invariants #{where} " <>
            "rejects on, #{inspect(allowed)}"
        )

      true ->
        quote do: {:error, %EhOsContract.Rejection{invariant: unquote(invariant)}}
    end
  end

  @doc """
  The commands a reaction issues: `{:ok, [command]}`. Takes struct literals of
  commands its declaration issues (I6, I7).
  """
  defmacro issue(commands) do
    impl = implementation!(__CALLER__, "issue/1")

    only!(
      impl,
      [:policy, :process_manager],
      "issue/1",
      "a policy or a process manager",
      __CALLER__
    )

    model = impl.contract.__eh_os_contract_model__()
    {allowed, where} = allowed(model, impl, __CALLER__.function, :issues)

    for module <- literal_structs!(commands, "issue/1", __CALLER__),
        not Enum.any?(allowed, &(Model.module_for(model, :command, &1) == module)) do
      refuse!(
        __CALLER__,
        "I6: issue/1 gets %#{inspect(module)}{}, which is not among the commands #{where} " <>
          "issues, #{inspect(allowed)}"
      )
    end

    quote do: {:ok, List.wrap(unquote(commands))}
  end

  defp implementation!(caller, macro) do
    Module.get_attribute(caller.module, :eh_os_contract_implementation) ||
      refuse!(caller, "#{macro} is used in a module that binds to no contract; `use` one first")
  end

  # I7.
  defp only!(impl, kinds, macro, what, caller) do
    unless impl.kind in kinds do
      refuse!(
        caller,
        "I7: #{macro} belongs in #{what}, and this module implements #{human(impl.kind)} " <>
          "#{inspect(impl.name)}"
      )
    end
  end

  # What may be produced where the macro is called: in a callback, what that callback
  # may produce; anywhere else in the module, what any of them may.
  defp allowed(model, impl, function, key) do
    %{callbacks: callbacks} = Callbacks.of(model, impl.kind, impl.name)

    case Enum.find(callbacks, &({&1.name, &1.arity} == function)) do
      nil ->
        union = callbacks |> Enum.flat_map(&Map.fetch!(&1, key)) |> Enum.uniq()
        {union, "#{human(impl.kind)} #{inspect(impl.name)}"}

      callback ->
        {Map.fetch!(callback, key), describe(impl.kind, callback)}
    end
  end

  defp describe(kind, callback) when kind in [:aggregate, :dcb],
    do: "command #{inspect(callback.name)}"

  defp describe(_kind, %{arity: 1} = callback), do: "#{inspect(callback.name)}"
  defp describe(_kind, callback), do: "the reaction to #{inspect(callback.name)}"

  # `%M{}`, a list of them, or a `for` whose body ends in one.
  defp literal_structs!(ast, macro, caller) do
    case structs(ast, caller) do
      {:ok, modules} ->
        modules

      :error ->
        refuse!(
          caller,
          "I4: #{macro} takes struct literals — %Name{}, a list of them, or a for producing " <>
            "them — so what it produces is known at compile time; got #{Macro.to_string(ast)}"
        )
    end
  end

  defp structs({:%, _, [module, {:%{}, _, _}]}, caller) do
    case Macro.expand(module, caller) do
      module when is_atom(module) -> {:ok, [module]}
      _ -> :error
    end
  end

  defp structs(list, caller) when is_list(list) do
    Enum.reduce_while(list, {:ok, []}, fn item, {:ok, acc} ->
      case structs(item, caller) do
        {:ok, [module]} -> {:cont, {:ok, acc ++ [module]}}
        _ -> {:halt, :error}
      end
    end)
  end

  defp structs({:for, _, args}, caller) when is_list(args) do
    case List.last(args) do
      [do: {:__block__, _, [_ | _] = body}] -> structs(List.last(body), caller)
      [do: body] -> structs(body, caller)
      _ -> :error
    end
  end

  defp structs(_ast, _caller), do: :error

  # --- before the module compiles ---------------------------------------------------

  @doc false
  defmacro __before_compile__(env) do
    impl = Module.get_attribute(env.module, :eh_os_contract_implementation)
    model = impl.contract.__eh_os_contract_model__()
    %{callbacks: callbacks, evolve: evolve} = Callbacks.of(model, impl.kind, impl.name)
    aliases = Map.new(aliases(model, impl.kind, impl.name))
    where = "#{human(impl.kind)} #{inspect(impl.name)} of #{inspect(impl.contract)}"
    at = %{env | line: impl.line}

    expected = callbacks ++ if(evolve, do: [evolve.callback], else: [])

    case Enum.reject(expected, &Module.defines?(env.module, {&1.name, &1.arity}, :def)) do
      [] ->
        :ok

      missing ->
        clauses = Enum.map_join(missing, "\n\n", &clause(&1, aliases))

        refuse!(
          at,
          "I2: #{inspect(env.module)} does not define " <>
            "#{Enum.map_join(missing, ", ", &"#{&1.name}/#{&1.arity}")}, which #{where} " <>
            "expects. Add:\n\n#{clauses}"
        )
    end

    if evolve, do: covered!(env, at, model, evolve, aliases)

    emitted =
      env.module
      |> Module.get_attribute(:eh_os_contract_emitted)
      |> Enum.reverse()
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Map.new(fn {function, names} -> {function, names |> List.flatten() |> Enum.uniq()} end)

    description = %{
      contract: impl.contract,
      kind: impl.kind,
      name: impl.name,
      emitted: emitted
    }

    quote do
      @doc false
      def __eh_os_implementation__, do: unquote(Macro.escape(description))
    end
  end

  # I3: every event the state is kept from has a clause, unless one catches all.
  defp covered!(env, at, model, evolve, aliases) do
    {:v1, _kind, _meta, clauses} = Module.get_definition(env.module, {:evolve, 2})

    patterns =
      Enum.map(clauses, fn {_meta, [_state, event], guards, _body} -> {event, guards} end)

    # A variable catches every event only without a guard: `when is_struct(e, A)` is a
    # clause for A, not for all.
    catch_all = Enum.any?(patterns, fn {event, guards} -> guards == [] and catch_all?(event) end)
    patterns = Enum.map(patterns, &elem(&1, 0))

    unless catch_all do
      handled = MapSet.new(Enum.flat_map(patterns, &struct_modules/1))

      missing =
        for event <- evolve.events,
            module = Model.module_for(model, :event, event),
            not MapSet.member?(handled, module),
            do: module

      if missing != [] do
        refuse!(
          at,
          "I3: #{inspect(env.module)}.evolve/2 has no clause for " <>
            "#{Enum.map_join(missing, ", ", &"%#{inspect(Map.get(aliases, &1, &1))}{}")}. Add " <>
            "one for each, or a catch-all: `def evolve(state, _event), do: state`"
        )
      end
    end
  end

  defp catch_all?({name, _meta, context}) when is_atom(name) and is_atom(context), do: true
  defp catch_all?({:=, _, [left, right]}), do: catch_all?(left) and catch_all?(right)
  defp catch_all?(_), do: false

  defp struct_modules({:%, _, [module, _]}) when is_atom(module), do: [module]

  defp struct_modules({:=, _, [left, right]}),
    do: struct_modules(left) ++ struct_modules(right)

  defp struct_modules(_), do: []

  # The clause I2 shows: the callback's head, with the aliases the module has.
  defp clause(callback, aliases) do
    args =
      Enum.map(callback.args, fn
        {{:., _, [module, :t]}, _, []} when is_atom(module) ->
          alias = Map.get(aliases, module, module)
          "%#{inspect(alias)}{} = #{var(alias)}"

        _other ->
          "ctx"
      end)

    "    @impl true\n    def #{callback.name}(#{Enum.join(args, ", ")}) do\n      …\n    end"
  end

  defp var(alias) do
    case alias |> Module.split() |> List.last() do
      "State" -> "state"
      "Row" -> "row"
      name -> Macro.underscore(name)
    end
  end

  defp refuse!(env, message) do
    raise CompileError, file: env.file, line: env.line, description: message
  end
end

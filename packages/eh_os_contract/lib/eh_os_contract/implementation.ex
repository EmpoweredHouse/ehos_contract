defmodule EhOsContract.Implementation do
  # The implementation layer, L4 (v2 §5, §6); a domain's value bound as plan EL2b has it.
  @moduledoc """
  How code binds to a contract, and what the contract checks in it while it
  compiles.

      defmodule Rehmed.Settlement.VisitSettlement do
        use Rehmed.Contracts.VisitSettlement, aggregate: :visit_settlement

        @impl true
        def record_payment(%RecordPayment{visit_id: id, amount: a}, _state),
          do: emit(%PaymentRecorded{visit_id: id, amount: a})
      end

  `use C, aggregate: :name` — or `dcb:`, `policy:`, `effect:`, `process_manager:`,
  `read_model:`, `query:`, `domain_service:` — names exactly one declaration of the
  contract `C`, and brings in:

  - `@behaviour` of the module `C` generated for it, whose callbacks are listed
    below;
  - aliases for the structs it touches: a unit's commands, events and `State`; a
    reaction's events and the commands it issues; a read model's events and `Row`; a
    query's parameters and rows. An event consumed from a sibling under a new name
    is aliased under that name;
  - `emit/1`, `reject/1` and `issue/1`, which check at the call site what they are
    given;
  - a check, before the module compiles, that every callback is defined and that
    `evolve/2` handles every event its state is kept from.

  The dependency runs one way: the implementation compiles against the contract and
  the structs it expands, and the contract names no implementation.

  ## The callbacks

  | Kind | Callbacks |
  | --- | --- |
  | aggregate, dcb | one per command, `(command, state) :: decision`, or `(command, state, reads) :: decision` for a command that `reads:` entities; `evolve/2` when the unit declares a state |
  | policy | one per handled event, `(event) :: issued` |
  | effect | one per handled event, `(event) :: :ok \\| {:error, term}` |
  | process manager | one per starting or running reaction that issues, `(event, state) :: issued`; one per timer that issues, `(state) :: issued`; `evolve/2` when it declares a state |
  | read model | one per projected event, `(event) :: :ok` |
  | query | one, named after it, `(params, ctx) :: rows` |
  | domain service | one per function, `(arguments…) :: result`, typed as declared |
  | value, of a domain | one per invariant, `(value) :: boolean` |

  `reads` holds each entity the command reads under the name its `reads:` gives it,
  as the host's `EhOsContract.Entities` returned it: `%{service: %{service_id: "s-1",
  p1_reported: true}}`.

  A decision is `{:ok, [event]}` or `{:error, %EhOsContract.Rejection{}}`; what is
  issued is `{:ok, [command]}`. `evolve/2` folds the events a state is kept from: a
  unit's own, a boundary's consulted ones too, and a process manager's triggers.

  **A domain's value** is bound the same way, `use Rehmed.Domain, value: :money`:
  the behaviour is `Rehmed.Domain.Values.Money`, with one function per
  invariant the value declares, and I1 and I2 hold as they do for a contract. There
  is nothing to alias and nothing to emit.

      defmodule Rehmed.Money do
        use Rehmed.Domain, value: :money

        @impl true
        def not_negative(amount), do: amount >= 0
      end

  **The rules**, each a `CompileError` at the call site, or at the
  `use` line for the ones checked before the module compiles:

  - **I1.** `use C, …` names one declaration that exists; a misspelling gets a
    did-you-mean. A module binds once.
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

  What stays at run time: field values against their types, capabilities,
  and the backstop that what a decision returns is within its declaration.
  """

  alias EhOsContract.DslRules
  alias EhOsContract.Model
  alias EhOsContract.Contract.Callbacks

  @kinds [
    :aggregate,
    :dcb,
    :policy,
    :effect,
    :process_manager,
    :read_model,
    :query,
    :domain_service
  ]

  # What a domain's `use` binds (plan EL2b).
  @domain_kinds [:value]

  @typedoc """
  What `__eh_os_implementation__/0` says about an implementation. `contract` is the
  module bound to: a contract, or a domain for a `:value`.
  """
  @type t :: %{
          contract: module(),
          kind: atom(),
          name: atom(),
          emitted: %{{atom(), arity()} => [atom()]},
          file: String.t(),
          line: pos_integer()
        }

  # --- binding ----------------------------------------------------------------------

  @doc false
  @spec bind(module(), keyword(), Macro.Env.t()) :: Macro.t()
  def bind(contract, opts, caller) do
    model = contract.__eh_os_contract_model__()
    {kind, name} = declaration!(model, opts, caller)

    # One module, one declaration: a second binding would replace the first, and the
    # first's callbacks would never be checked. The attribute is set here, while `use`
    # expands, because the module body is expanded before any of it runs: set in the
    # quote below, a second `use` would not see it yet.
    case Module.get_attribute(caller.module, :eh_os_contract_implementation) do
      nil ->
        :ok

      bound ->
        refuse!(
          caller,
          "I1: #{inspect(caller.module)} already implements #{human(bound.kind)} " <>
            "#{inspect(bound.name)} of #{inspect(bound.contract)}; one module implements one " <>
            "declaration"
        )
    end

    Module.put_attribute(caller.module, :eh_os_contract_implementation, %{
      contract: contract,
      kind: kind,
      name: name,
      line: caller.line
    })

    aliases =
      for {module, as} <- aliases(model, kind, name) do
        quote do: alias(unquote(module), as: unquote(as), warn: false)
      end

    # A declaration with nothing to define — a process manager whose reactions and
    # timers issue nothing and whose state is its correlation — generates a module
    # with no callback, which Elixir does not take as a behaviour.
    behaviour =
      if behaviour?(model, kind, name),
        do: quote(do: @behaviour(unquote(Model.module_for(model, kind, name))))

    quote do
      unquote(behaviour)
      Module.register_attribute(__MODULE__, :eh_os_contract_emitted, accumulate: true)
      import EhOsContract.Implementation, only: [emit: 1, reject: 1, issue: 1], warn: false
      unquote_splicing(aliases)
      @before_compile EhOsContract.Implementation
    end
  end

  defp behaviour?(_model, :read_model, _name), do: true

  defp behaviour?(model, kind, name) do
    %{callbacks: callbacks, evolve: evolve} = Callbacks.of(model, kind, name)
    callbacks != [] or evolve != nil
  end

  # I1: exactly one kind, naming a declaration that exists.
  defp declaration!(model, opts, caller) do
    where = "use #{inspect(model.module)}"
    kinds = kinds(model)
    unknown = Keyword.keys(opts) -- kinds

    if unknown != [] do
      refuse!(
        caller,
        "I1: #{where} takes one of #{inspect(kinds)}; #{inspect(unknown)} is not among them"
      )
    end

    case Keyword.take(opts, kinds) do
      [{kind, name}] ->
        names = names(model, kind)

        if name in names do
          {kind, name}
        else
          refuse!(caller, "I1: #{where}: #{unknown_name(model, kind, name, names)}")
        end

      [] ->
        refuse!(
          caller,
          "I1: #{where} names no declaration; write `#{where}, #{hd(kinds)}: :name`"
        )

      many ->
        refuse!(caller, "I1: #{where} names #{inspect(many)}; an implementation binds to one")
    end
  end

  defp kinds(%{kind: :domain}), do: @domain_kinds
  defp kinds(_contract), do: @kinds

  defp unknown_name(model, kind, name, names) do
    elsewhere =
      for other <- kinds(model), other != kind, name in names(model, other), do: other

    cond do
      # A value without invariants has nothing to check, and so nothing to implement.
      kind == :value and Enum.any?(model.values, &(&1.name == name)) ->
        "value #{inspect(name)} declares no invariant, so there is nothing to implement"

      elsewhere != [] ->
        "#{inspect(name)} is not #{a(kind)} but #{Enum.map_join(elsewhere, " and ", &a/1)}"

      suggestion = DslRules.closest(name, names) ->
        "there is no #{human(kind)} #{inspect(name)}; did you mean #{inspect(suggestion)}?"

      true ->
        "there is no #{human(kind)} #{inspect(name)}; the #{model.kind} declares " <>
          inspect(names)
    end
  end

  defp names(model, :value), do: for(%{invariants: [_ | _]} = v <- model.values, do: v.name)

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
          query: :queries,
          domain_service: :domain_services
        },
        kind
      )

    Enum.map(Map.fetch!(model, key), & &1.name)
  end

  defp human(kind), do: kind |> Atom.to_string() |> String.replace("_", " ")

  defp a(kind) when kind in [:aggregate, :effect], do: "an #{human(kind)}"
  defp a(kind), do: "a #{human(kind)}"

  # The structs an implementation of the declaration touches, each with the alias it
  # gets: `{module, alias}`.
  @doc false
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

        kind when kind in [:domain_service, :value] ->
          []
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
  A command refused on an invariant, or on one of its constraints:
  `{:error, %EhOsContract.Rejection{}}`. Takes an atom literal among what the command
  rejects on (I5, I7).
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
          "I5: reject/1 takes the invariant or constraint as an atom literal, so it is known " <>
            "at compile " <>
            "time; got #{Macro.to_string(invariant)}"
        )

      invariant not in allowed ->
        refuse!(
          __CALLER__,
          "I5: reject/1 gets #{inspect(invariant)}, which is not among the invariants and " <>
            "constraints #{where} rejects on, #{inspect(allowed)}"
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

  # `uniq:` keeps it a list of the same structs; `into:` and `reduce:` make it
  # something else, so they are not literals.
  defp structs({:for, _, args}, caller) when is_list(args) do
    with opts when is_list(opts) <- List.last(args),
         true <- Keyword.keyword?(opts) and Keyword.keys(opts) -- [:do, :uniq] == [],
         {:ok, body} <- Keyword.fetch(opts, :do) do
      case body do
        {:__block__, _, [_ | _] = exprs} -> structs(List.last(exprs), caller)
        body -> structs(body, caller)
      end
    else
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
      emitted: emitted,
      folds: folds(env, model, evolve),
      file: env.file,
      line: impl.line
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

  # The events `evolve/2` folds (plan E11f-5): those a clause names by struct, when every
  # other clause is `def evolve(state, _), do: state` and so changes nothing — the
  # state is then a function of those events alone, and dispatch reads no other. Any
  # other clause that catches events, a guarded variable or a body that is not the
  # state, may fold anything: `:all`.
  defp folds(_env, _model, nil), do: :all

  defp folds(env, model, evolve) do
    {:v1, _kind, _meta, clauses} = Module.get_definition(env.module, {:evolve, 2})

    named =
      MapSet.new(
        Enum.flat_map(clauses, fn {_meta, [_state, event], _, _} -> struct_modules(event) end)
      )

    passing =
      Enum.reject(clauses, fn {_meta, [_state, event], _guards, _body} ->
        struct_modules(event) != []
      end)

    if Enum.all?(passing, &unchanged?/1),
      do: for(event <- evolve.events, Model.module_for(model, :event, event) in named, do: event),
      else: :all
  end

  defp unchanged?({_meta, [{state, _, context}, event], [], {state, _, context}})
       when is_atom(state) and is_atom(context),
       do: catch_all?(event)

  defp unchanged?(_clause), do: false

  defp catch_all?({name, _meta, context}) when is_atom(name) and is_atom(context), do: true
  defp catch_all?({:=, _, [left, right]}), do: catch_all?(left) and catch_all?(right)
  defp catch_all?(_), do: false

  defp struct_modules({:%, _, [module, _]}) when is_atom(module), do: [module]

  defp struct_modules({:=, _, [left, right]}),
    do: struct_modules(left) ++ struct_modules(right)

  defp struct_modules(_), do: []

  # The clause I2 shows: the callback's head, with the aliases the module has.
  defp clause(%{names: [_ | _] = names} = callback, _aliases),
    do: "    @impl true\n    def #{callback.name}(#{Enum.join(names, ", ")}) do\n      …\n    end"

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

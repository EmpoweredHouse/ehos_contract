if Code.ensure_loaded?(StreamData) do
  defmodule EhOsContract.PropertyCase do
    # Plan DD, PC2 (#266), on the generators of PC1 (#264). Compiled only where
    # StreamData is, as `EhOsContract.Generators`.
    @moduledoc """
    A unit's code, tried on hundreds of legal histories made from its contract.

        defmodule Clinic.VisitsPropertiesTest do
          use EhOsContract.PropertyCase, contract: Clinic.Contracts.Visits, max_runs: 50
        end

    For every aggregate of the contract with an implementation, it writes properties:

    - **It folds every legal history.** `evolve/2` folds each history of the unit's
      events the contract allows (`EhOsContract.Generators.history/3`), from its default
      state, into its state, without raising. The events carry `__meta__` as the log
      gives them, and a personal field is now and then erased.
    - **Each command decides within the contract.** On a legal history, in a status its
      `from:` admits, the command's decision returns events the engine would append (its
      `emits`, the command's identity, values that fit, in an order the lifecycle
      allows) or a rejection on one of its `rejects:`. A raise, or anything else, fails.
      A command that creates its aggregate is decided on an empty history, with the
      identity the engine would generate.
    - **It keeps its invariants**, when the implementation says what each one means with
      `holds?(invariant, state) :: boolean`. Commands of one identity are decided in
      turn and their events folded; after each, every invariant of the unit holds.

    A failure shows the shortest history, or the shortest list of commands, that breaks
    the property. `implementations:` names where to look for the implementations, as in
    `EhOsContract.ScenarioCase`; `max_runs:` (default 50) how many cases each property
    tries. A dynamic consistency boundary is left out: its events come from several
    streams, and no generator makes its history yet.

    The functions behind the properties, `fold/4`, `decide/5` and `walk/4`, with the
    generators `decisions/3` and `walks/2`, are public, for a host's own `check all`.

    A failure prints the history and, for an invariant, the state it reached, which may
    hold a unit's personal fields: generated here, but a host calling `walk/4` with its
    own data prints that.

    The module exists only when StreamData is a dependency of the application. One that
    adds StreamData to a build compiled without it recompiles this package,
    `mix deps.compile eh_os_contract --force`, since the module's presence is decided
    when the package compiles.
    """

    import ExUnit.Assertions
    import StreamData

    alias EhOsContract.{Decision, Generators, Lifecycle, Meta, Model, Rejection, ScenarioCase}

    @epoch ~U[2026-01-01 09:00:00Z]
    @max_walk 10

    @doc false
    defmacro __using__(opts) do
      contract = Keyword.fetch!(opts, :contract)
      implementations = Keyword.get(opts, :implementations)
      max_runs = Keyword.get(opts, :max_runs, 50)
      async = Keyword.get(opts, :async, true)

      quote do
        use ExUnit.Case, async: unquote(async)
        use ExUnitProperties

        for {unit, commands, holds?, found} <-
              EhOsContract.PropertyCase.plan(unquote(contract), unquote(implementations)) do
          @eh_os_contract_unit unit
          @eh_os_contract_found found

          property "#{unit} folds every legal history" do
            check all(
                    events <-
                      EhOsContract.Generators.history(unquote(contract), @eh_os_contract_unit),
                    max_runs: unquote(max_runs)
                  ) do
              EhOsContract.PropertyCase.fold(
                unquote(contract),
                @eh_os_contract_unit,
                events,
                implementations: @eh_os_contract_found
              )
            end
          end

          for command <- commands do
            @eh_os_contract_command command

            property "#{unit} decides #{command} within the contract" do
              check all(
                      {events, command, rows} <-
                        EhOsContract.PropertyCase.decisions(
                          unquote(contract),
                          @eh_os_contract_unit,
                          @eh_os_contract_command
                        ),
                      max_runs: unquote(max_runs)
                    ) do
                EhOsContract.PropertyCase.decide(
                  unquote(contract),
                  @eh_os_contract_unit,
                  events,
                  {command, rows},
                  implementations: @eh_os_contract_found
                )
              end
            end
          end

          if holds? do
            property "#{unit} keeps its invariants" do
              check all(
                      commands <-
                        EhOsContract.PropertyCase.walks(unquote(contract), @eh_os_contract_unit),
                      max_runs: unquote(max_runs)
                    ) do
                EhOsContract.PropertyCase.walk(
                  unquote(contract),
                  @eh_os_contract_unit,
                  commands,
                  implementations: @eh_os_contract_found
                )
              end
            end
          end
        end
      end
    end

    @doc false
    # Every aggregate of `contract` with an implementation, its commands, whether the
    # implementation defines `holds?/2`, and the implementations found, looked up once
    # for the module rather than once per case. One with two is kept, so that its
    # properties fail naming them, as dispatch refuses it; one with none is left out, as
    # a contract without code is legal.
    @spec plan(module(), [module()] | nil) :: [{atom(), [atom()], boolean(), [module()]}]
    def plan(contract, implementations) do
      model = Model.fetch(contract)

      for %{kind: :aggregate, name: unit} <- model.units,
          found = ScenarioCase.implementations(model, :aggregate, unit, implementations),
          found != [] do
        commands = for c <- model.commands, c.unit == unit, do: c.name
        {unit, commands, Enum.any?(found, &function_exported?(&1, :holds?, 2)), found}
      end
    end

    # --- folding ----------------------------------------------------------------------

    @doc """
    Folds `events`, a history of the unit `unit` of `contract`, through its
    implementation's `evolve/2` from its default state, and returns the state. Fails the
    test when `evolve/2` raises or returns anything but the unit's state struct.

    The events get `__meta__` as the log gives them, a minute apart, unless they carry
    one.
    """
    @spec fold(module(), atom(), [struct()], keyword()) :: struct()
    def fold(contract, unit, events, opts \\ []) do
      {model, impl, declaration} = unit!(contract, unit, opts)
      events = stamp(events, 0)
      fold_from(model, impl, declaration, identity_from(declaration, List.first(events)), events)
    end

    # As dispatch folds a stream (`Decision.folded/7`): from the default state named by
    # `identity`, the status before each event from the lifecycle's walk, and a step that
    # fails naming the event and the history.
    defp fold_from(model, impl, unit, identity, events) do
      module = state_module(model, unit.name)
      all = names(model, events)

      {befores, status} =
        case Lifecycle.of(unit) do
          nil -> {[], nil}
          lifecycle -> Lifecycle.walk(lifecycle, all)
        end

      Decision.folded(unit, impl, struct(module, identity), events, befores, status, fn
        state, event, index ->
          folded =
            try do
              impl.evolve(state, event)
            rescue
              error ->
                flunk(
                  "#{inspect(impl)}.evolve/2 raised on #{name_of(model, event)}, event " <>
                    "#{index + 1} of the history #{inspect(all)}:\n" <>
                    Exception.format(:error, error, __STACKTRACE__)
                )
            end

          assert is_struct(folded, module),
                 "#{inspect(impl)}.evolve/2 returned #{inspect(folded)} for " <>
                   "#{name_of(model, event)}, and it returns the unit's state, " <>
                   "%#{inspect(module)}{}"

          folded
      end)
    end

    # --- deciding ---------------------------------------------------------------------

    @doc """
    Decides `command`, with the entity `rows` it reads, after the history `events` of the
    unit `unit` of `contract`, as dispatch would, and fails the test when the decision
    steps outside the contract.

    Returns `{:ok, events}` with the events decided, `:rejected` for a rejection the
    command declares, or `:not_admitted` when the history leaves the unit in a status
    the command's `from:` does not admit, or a command that creates its aggregate meets
    a history, so that the engine would not decide it.
    """
    @spec decide(module(), atom(), [struct()], {struct(), map()}, keyword()) ::
            {:ok, [struct()]} | :rejected | :not_admitted
    def decide(contract, unit, events, {command, rows}, opts \\ []) do
      {model, impl, declaration} = unit!(contract, unit, opts)
      events = stamp(events, 0)
      decide_after(model, impl, declaration, events, command, rows)
    end

    defp decide_after(model, impl, unit, events, command, rows) do
      declaration = Enum.find(model.commands, &(&1.name == name_of(model, command)))
      lifecycle = Lifecycle.of(unit)
      history = names(model, events)
      status = if lifecycle, do: Lifecycle.status(lifecycle, history)

      cond do
        Map.get(declaration, :creates) && events != [] ->
          :not_admitted

        not Lifecycle.admits?(declaration, status) ->
          :not_admitted

        true ->
          state = fold_from(model, impl, unit, identity_from(unit, command), events)
          read = if rows == %{}, do: [], else: [rows]
          command = issued(command, length(events))

          result =
            try do
              apply(impl, declaration.name, [command, state | read])
            rescue
              error ->
                flunk(
                  "#{inspect(impl)}.#{declaration.name}/#{2 + length(read)} raised after the " <>
                    "history #{inspect(history)}:\n" <>
                    Exception.format(:error, error, __STACKTRACE__)
                )
            end

          held(model, declaration, unit, status, command, result, history)
      end
    end

    defp held(model, declaration, unit, status, command, {:ok, decided}, history)
         when is_list(decided) do
      try do
        {pairs, _status} = Decision.held!(model, declaration, unit, status, command, decided)
        {:ok, Enum.map(pairs, &elem(&1, 1))}
      rescue
        error in ArgumentError ->
          flunk(
            "command #{inspect(declaration.name)}, after the history #{inspect(history)}, " <>
              "decided what the contract does not allow: #{Exception.message(error)}"
          )
      end
    end

    defp held(_model, declaration, _unit, _status, _command, {:error, %Rejection{} = r}, history) do
      assert r.invariant in declaration.rejects,
             "command #{inspect(declaration.name)}, after the history #{inspect(history)}, " <>
               "was rejected on #{inspect(r.invariant)}, which is not among its rejects: " <>
               inspect(declaration.rejects)

      :rejected
    end

    defp held(_model, declaration, _unit, _status, _command, other, history) do
      flunk(
        "command #{inspect(declaration.name)}, after the history #{inspect(history)}, " <>
          "returned #{inspect(other)}; a decision returns {:ok, events} or " <>
          "{:error, %EhOsContract.Rejection{}}"
      )
    end

    @doc """
    A generator of what `decide/5` takes for the command `command` of the unit `unit`:
    `{history, command, rows}`, a legal history, the command of the same identity, and
    a row of each entity it reads, keyed by its name in `reads:`. A command that creates
    its aggregate comes with an empty history and the identity the engine would give it.
    """
    @spec decisions(module(), atom(), atom()) :: StreamData.t({[struct()], struct(), map()})
    def decisions(contract, unit, command) do
      model = Model.fetch(contract)
      declaration = Enum.find(model.commands, &(&1.name == command and &1.unit == unit))
      identity = Enum.find(model.units, &(&1.name == unit)).identity

      if Map.get(declaration, :creates) do
        bind(identity_of(identity), fn ids ->
          contract
          |> Generators.command(command)
          |> map(&struct!(&1, ids))
          |> bind(&with_rows(model, declaration, &1))
          |> map(fn {command, rows} -> {[], command, rows} end)
        end)
      else
        bind(identity_of(identity), fn ids ->
          fixed = Enum.to_list(ids)

          bind(Generators.history(contract, unit, fields: fixed), fn events ->
            contract
            |> Generators.command(command, fields: fixed)
            |> bind(&with_rows(model, declaration, &1))
            |> map(fn {command, rows} -> {events, command, rows} end)
          end)
        end)
      end
    end

    defp with_rows(model, declaration, command) do
      case Map.get(declaration, :reads, []) do
        [] ->
          constant({command, %{}})

        reads ->
          reads
          |> Enum.map(fn {name, field} ->
            %{refers_to: entity} = Enum.find(declaration.fields, &(&1.name == field))
            id = Enum.find(Model.fetch(model.domain).entities, &(&1.name == entity)).identity

            model.domain
            |> Generators.entity_row(entity, fields: [{id, Map.fetch!(command, field)}])
            |> map(&{name, &1})
          end)
          |> fixed_list()
          |> map(&{command, Map.new(&1)})
      end
    end

    # --- walking ----------------------------------------------------------------------

    @doc """
    Decides `commands`, each `{command, rows}`, in turn on one unit of `unit`, folding
    what each decides, and fails the test when, after any of them, an invariant of the
    unit does not hold by its implementation's `holds?(invariant, state)`. A command the
    engine would not decide in the status reached is skipped, as dispatch refuses it.
    """
    @spec walk(module(), atom(), [{struct(), map()}], keyword()) :: struct()
    def walk(contract, unit, commands, opts \\ []) do
      {model, impl, declaration} = unit!(contract, unit, opts)
      invariants = Enum.map(declaration.invariants, & &1.name)

      {events, _issued} =
        Enum.reduce(commands, {[], []}, fn {command, rows}, {events, issued} ->
          issued = issued ++ [name_of(model, command)]

          case decide_after(model, impl, declaration, events, command, rows) do
            {:ok, decided} ->
              events = events ++ stamp(decided, length(events))

              state =
                fold_from(model, impl, declaration, identity_from(declaration, command), events)

              for invariant <- invariants, not holds?(impl, invariant, state) do
                flunk(
                  "invariant #{inspect(invariant)} of #{inspect(unit)} does not hold after the " <>
                    "commands #{inspect(issued)}, which left the history " <>
                    "#{inspect(names(model, events))} and the state #{inspect(state)}"
                )
              end

              {events, issued}

            _rejected_or_not_admitted ->
              {events, issued}
          end
        end)

      fold_from(model, impl, declaration, identity_from(declaration, List.first(events)), events)
    end

    @doc """
    A generator of what `walk/4` takes: up to #{@max_walk} commands of the unit `unit`,
    of one identity, each with the rows it reads. A unit one of whose commands creates
    it starts with that command, given the identity the engine would give it, and the
    others follow.
    """
    @spec walks(module(), atom()) :: StreamData.t([{struct(), map()}])
    def walks(contract, unit) do
      model = Model.fetch(contract)
      identity = Enum.find(model.units, &(&1.name == unit)).identity

      {creating, others} =
        model.commands
        |> Enum.filter(&(&1.unit == unit))
        |> Enum.split_with(&Map.get(&1, :creates, false))

      bind(identity_of(identity), fn ids ->
        fixed = Enum.to_list(ids)

        start =
          case creating do
            [] ->
              constant([])

            _ ->
              creating
              |> Enum.map(fn declaration ->
                contract
                |> Generators.command(declaration.name)
                |> map(&struct!(&1, ids))
                |> bind(&with_rows(model, declaration, &1))
              end)
              |> one_of()
              |> map(&[&1])
          end

        rest =
          case others do
            [] ->
              constant([])

            _ ->
              others
              |> Enum.map(fn declaration ->
                contract
                |> Generators.command(declaration.name, fields: fixed)
                |> bind(&with_rows(model, declaration, &1))
              end)
              |> one_of()
              |> list_of(max_length: @max_walk)
          end

        map({start, rest}, fn {start, rest} -> start ++ rest end)
      end)
    end

    defp holds?(impl, invariant, state) do
      impl.holds?(invariant, state)
    rescue
      FunctionClauseError ->
        flunk(
          "#{inspect(impl)}.holds?/2 says nothing of invariant #{inspect(invariant)}; it " <>
            "answers for every invariant of the unit"
        )
    end

    # --- helpers ----------------------------------------------------------------------

    # A command as dispatch hands it to the decision: with `__meta__`, a minute after the
    # history's last event.
    defp issued(%{__meta__: nil} = command, after_events) do
      %{
        command
        | __meta__: %Meta{
            id: Ecto.UUID.generate(),
            occurred_at: DateTime.add(@epoch, 60 * (after_events + 1))
          }
      }
    end

    defp issued(command, _after_events), do: command

    defp unit!(contract, unit, opts) do
      model = Model.fetch(contract)

      declaration =
        Enum.find(model.units, &(&1.name == unit and &1.kind == :aggregate)) ||
          raise ArgumentError, "#{inspect(contract)} declares no aggregate #{inspect(unit)}"

      case ScenarioCase.implementations(model, :aggregate, unit, opts[:implementations]) do
        [impl] ->
          {model, impl, declaration}

        found ->
          flunk(
            "aggregate #{inspect(unit)} of #{inspect(contract)} needs one implementation, " <>
              "and has #{length(found)}: #{inspect(found)}"
          )
      end
    end

    defp identity_of(fields) do
      fixed_map(for f <- fields, do: {f, string(:alphanumeric, min_length: 1, max_length: 16)})
    end

    defp state_module(model, unit),
      do: Module.concat(Model.module_for(model, :aggregate, unit), State)

    # The identity a state is named by: the command's, as dispatch names it, or a
    # history's first event's.
    defp identity_from(_unit, nil), do: %{}
    defp identity_from(unit, struct), do: Map.new(unit.identity, &{&1, Map.get(struct, &1)})

    # A history as the log gives it back: an id, a position, a moment a minute after the
    # one before. An event that carries `__meta__` keeps it.
    defp stamp(events, offset) do
      events
      |> Enum.with_index(offset + 1)
      |> Enum.map(fn
        {%{__meta__: %Meta{}} = event, _position} ->
          event

        {event, position} ->
          meta = %Meta{
            id: Ecto.UUID.generate(),
            position: position,
            occurred_at: DateTime.add(@epoch, 60 * position)
          }

          %{event | __meta__: meta}
      end)
    end

    defp names(model, structs), do: Enum.map(structs, &name_of(model, &1))

    defp name_of(model, %module{}) do
      Enum.find_value(model.events ++ model.commands, fn declaration ->
        kind = if declaration in model.commands, do: :command, else: :event
        if Model.module_for(model, kind, declaration.name) == module, do: declaration.name
      end)
    end
  end
end

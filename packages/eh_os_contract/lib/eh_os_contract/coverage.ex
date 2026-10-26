defmodule EhOsContract.Coverage do
  # Which of a v2 contract's scenarios the log has seen happen, and which decisions it
  # has seen that no scenario declares (v2 §13, plan E7c-2).
  #
  # **A scenario is observed** when a command of its trigger was decided with the
  # scenario's `given` types among the stream's (`given_types` of the command's row in
  # `eh_os_contract_commands`) and either was accepted with the scenario's `expect`
  # types as a subsequence of what it emitted, or was rejected on the scenario's
  # invariant — the semantics `ScenarioCase` gives a scenario. **By type only**: matching on data would mean
  # storing command payloads, and those are personal data.
  #
  # Only a scenario whose trigger is a command can be observed: a query leaves no row,
  # and a scenario of a reaction is its own command's when the reaction issues one. Nor
  # does a command refused for its data, on a value's invariant, before any decision
  # (issue #458). The others are not counted either way.
  #
  # **An outcome no scenario declares** is a decision of a command — accepted with the
  # types it emitted, or rejected on an invariant — that no scenario of that command
  # would match. It is a question for the process owner: the code decided something
  # the agreed cases do not say.
  @moduledoc false

  import Ecto.Query

  alias EhOsContract.{CommandRecord, Model}
  alias EhOsContract.Contract.Links

  @typedoc "What the log says about a contract's scenarios."
  @type t :: %{
          declared: non_neg_integer(),
          observed: non_neg_integer(),
          never_observed: [String.t()],
          undeclared_outcomes: [map()]
        }

  @doc """
  Coverage of `contract`'s command scenarios. `opts`: `:since` and `:until` bound the
  decisions, on the row's `recorded_at`.
  """
  @spec of(module() | map(), keyword()) :: t()
  def of(contract, opts \\ []) do
    model = Model.fetch(contract)
    rows = decisions(model, opts)

    implementations = EhOsContract.Implementations.index(model.module).declarations

    scenarios =
      for %{trigger: %{kind: :command, name: name}} = scenario <- model.scenarios,
          command = Enum.find(model.commands, &(&1.name == name)),
          not Links.Scenarios.refused_on_value?(scenario, command),
          do: expected(model, scenario, folded(model, implementations, scenario))

    observed = Enum.filter(scenarios, fn s -> Enum.any?(rows, &matches?(s, &1)) end)

    %{
      declared: length(scenarios),
      observed: length(observed),
      never_observed: for(s <- scenarios, s not in observed, do: s.description),
      undeclared_outcomes: undeclared(model, scenarios, rows)
    }
  end

  # A scenario in the log's terms: stored types, names as strings. Its `given` counts
  # only the types its unit's `evolve/2` folds (plan E11f-5), and those its lifecycle
  # moves on (plan LC2): a boundary reads, and records as the command's `given_types`,
  # only those. An aggregate still records its
  # whole stream, of which the folded types are a part, so the comparison stays a
  # subset, never an equality.
  defp expected(model, scenario, folded) do
    %{
      description: scenario.description,
      command: Atom.to_string(scenario.trigger.name),
      given:
        scenario.given
        |> Enum.map(&type!(model, &1.event))
        |> Enum.filter(&(folded == :all or MapSet.member?(folded, &1)))
        |> MapSet.new(),
      expect: Enum.map(scenario.expect, &type!(model, &1.event)),
      rejected: scenario.rejected && Atom.to_string(scenario.rejected)
    }
  end

  defp folded(model, implementations, scenario) do
    command = Enum.find(model.commands, &(&1.name == scenario.trigger.name))
    unit = Enum.find(model.units, &(&1.name == command.unit))

    module =
      case Map.get(implementations, {model.module, unit.kind, unit.name}) do
        [module] -> module
        _none_or_several -> nil
      end

    case {EhOsContract.Implementations.folded_types(model, module), Map.get(unit, :lifecycle)} do
      {:all, _lifecycle} ->
        :all

      {folded, nil} ->
        folded

      # Plan LC2: the status is computed from every event the lifecycle names, and it can
      # refuse a command, so those count as given whether `evolve/2` folds them or not.
      {folded, lifecycle} ->
        moving =
          Enum.map(lifecycle.initial, & &1.on) ++ Enum.map(lifecycle.transitions, & &1.event)

        MapSet.union(folded, MapSet.new(moving, &type!(model, &1)))
    end
  end

  defp type!(model, name) do
    {_contract, %{type: type}} = Model.declaring(model, name)
    type
  end

  defp decisions(model, opts) do
    from(c in CommandRecord,
      where: c.contract == ^model.id and c.outcome in ["accepted", "rejected"],
      select: %{
        command: c.type,
        outcome: c.outcome,
        invariant: c.invariant,
        given: c.given_types,
        emitted: c.emitted_types
      }
    )
    |> bound(opts)
    |> repo().all()
  end

  defp matches?(scenario, row) do
    row.command == scenario.command and MapSet.subset?(scenario.given, MapSet.new(row.given)) and
      outcome?(scenario, row)
  end

  defp outcome?(%{rejected: nil, expect: expect}, %{outcome: "accepted", emitted: emitted}),
    do: subsequence?(expect, emitted)

  defp outcome?(%{rejected: invariant}, %{outcome: "rejected", invariant: invariant})
       when invariant != nil,
       do: true

  defp outcome?(_scenario, _row), do: false

  defp subsequence?([], _list), do: true
  defp subsequence?(_wanted, []), do: false
  defp subsequence?([x | wanted], [x | rest]), do: subsequence?(wanted, rest)
  defp subsequence?(wanted, [_ | rest]), do: subsequence?(wanted, rest)

  # Each distinct decision of a command no scenario of that command declares. The
  # outcome, not the stream it met: `given` narrows when a scenario applies, and a
  # decision nobody wrote a case for is the finding whatever came before it.
  defp undeclared(model, scenarios, rows) do
    labels = Map.new(model.events, &{&1.type, &1.label})
    commands = Map.new(model.commands, &{Atom.to_string(&1.name), &1})

    invariants =
      for u <- model.units, i <- u.invariants, into: %{}, do: {Atom.to_string(i.name), i.label}

    rows
    |> Enum.map(&Map.take(&1, [:command, :outcome, :invariant, :emitted]))
    |> Enum.uniq()
    |> Enum.reject(fn row ->
      Enum.any?(scenarios, &(&1.command == row.command and outcome?(&1, row)))
    end)
    |> Enum.flat_map(fn row ->
      case Map.get(commands, row.command) do
        nil ->
          []

        command ->
          [
            %{
              command: %{kind: :command, name: command.name, label: command.label},
              emitted:
                if(row.outcome == "accepted",
                  do: for(t <- row.emitted, do: Map.get(labels, t, t))
                ),
              rejected:
                if(row.outcome == "rejected",
                  do: Map.get(invariants, row.invariant, row.invariant)
                )
            }
          ]
      end
    end)
    |> Enum.sort_by(&{to_string(&1.command.name), &1.emitted || [], &1.rejected || ""})
  end

  defp bound(query, opts) do
    query
    |> then(fn q -> if at = opts[:since], do: where(q, [c], c.recorded_at >= ^at), else: q end)
    |> then(fn q -> if at = opts[:until], do: where(q, [c], c.recorded_at <= ^at), else: q end)
  end

  defp repo, do: EhOsContract.Config.fetch!(:repo)
end

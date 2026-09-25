defmodule EhOsContract.Next.Contract.Links.Scenarios do
  @moduledoc """
  X9 of v2 §6: scenario values fit their types, where L2 could not tell.

  S3 checks a scenario's data against the fields this contract declares, and a
  value of a built-in type against its type. Two things are left here:

  - **a value of a domain type**, anywhere a scenario gives one: one member of an
    enum, a value of the type a value names, a map of the fields a value with
    fields declares — in lists too (`EhOsContract.Next.Contract.Data.problems/3`);
  - **the data of an event consumed from a sibling contract**, whose fields are the
    sibling's: every key a field of the sibling's event, every required field given
    where S3 requires one (a `given` and the trigger, not what is expected or
    issued), each value of its type. The sibling's identity is filled in by
    `EhOsContract.ScenarioCase`, as a unit's own is, so it need not be given.
  """

  alias EhOsContract.Model
  alias EhOsContract.Next.Contract.{Data, Links, Rules}

  @doc false
  @spec check(map()) :: [Links.violation()]
  def check(system), do: Enum.flat_map(system.contracts, &contract/1)

  defp contract(c) do
    values = if c.domain, do: Map.new(c.domain.values, &{&1.name, &1}), else: %{}

    for {model, declaration} <- Enum.zip(c.model.scenarios, c.declarations.scenarios),
        {what, shape, data, at, required?} <- entries(c, model, declaration),
        problem <- problems(shape, data, values, required?) do
      {"X9: scenario #{inspect(model.description)}: #{what}#{problem}", at}
    end
  end

  # `{what, shape, data, where, required?}` for everything the scenario gives data
  # for. The model and the declaration list them in the same order.
  defp entries(c, model, declaration) do
    givens =
      for {given, at} <- Enum.zip(model.given, declaration.given),
          do: event(c, given.event, given.data, at, true)

    trigger =
      case {model.trigger, declaration.trigger} do
        {%{kind: :command} = t, [at]} -> [command(c, t.name, t.data, at, true)]
        {%{kind: :on} = t, [at]} -> [event(c, t.name, t.data, at, true)]
        _ -> []
      end

    expected =
      for {expect, at} <- Enum.zip(model.expect, declaration.expect),
          do: event(c, expect.event, expect.data, at, false)

    issued =
      for {issues, at} <- Enum.zip(model.issues, declaration.issues),
          do: command(c, issues.command, issues.data, at, false)

    Enum.reject(givens ++ trigger ++ expected ++ issued, &is_nil/1)
  end

  defp command(c, name, data, at, required?) do
    case Enum.find(c.model.commands, &(&1.name == name)) do
      nil ->
        nil

      command ->
        {"command #{inspect(name)}, ", {:local, command.fields}, data, Links.at(at), required?}
    end
  end

  # A local event, or a received one, whose fields S3 has checked; a sibling's, whose
  # fields it could not see; or nothing to check, as for a timer that fires.
  defp event(c, name, data, at, required?) do
    case Enum.find(c.model.events, &(&1.name == name)) do
      %{fields: fields} ->
        {"event #{inspect(name)}, ", {:local, fields}, data, Links.at(at), required?}

      nil ->
        case Model.consumed(c.model, name) do
          {:published, fields} ->
            {"event #{inspect(name)}, ", {:local, fields}, data, Links.at(at), required?}

          {:contract, from, original} ->
            sibling(from, original, name, data, at, required?)

          nil ->
            nil
        end
    end
  end

  defp sibling(from, original, name, data, at, required?) do
    with %{} = sibling <- Links.contract(from),
         %{} = event <- Enum.find(sibling.model.events, &(&1.name == original)) do
      identity = Enum.find(sibling.model.units, &(&1.name == event.unit)).identity
      declared = Enum.find(Rules.local_events(sibling.declarations), &(&1.name == original))

      {"event #{inspect(name)} of #{inspect(from)} (#{Links.place(Links.at(declared))}): ",
       {:sibling, event.fields, identity}, data, Links.at(at), required?}
    else
      # X5 names a sibling or an event that is not there.
      _ -> nil
    end
  end

  defp problems({:local, fields}, data, values, _required?), do: typed(fields, data, values)

  defp problems({:sibling, fields, identity}, data, values, required?) do
    declared = MapSet.new(fields, & &1.name)

    unknown =
      for key <- Map.keys(data), not MapSet.member?(declared, key), do: "no field #{inspect(key)}"

    missing =
      if required?,
        do:
          for(
            f <- fields,
            not f.optional,
            f.name not in identity,
            not Map.has_key?(data, f.name),
            do: "needs #{inspect(f.name)}"
          ),
        else: []

    unknown ++ missing ++ typed(fields, data, values)
  end

  defp typed(fields, data, values) do
    types = Map.new(fields, &{&1.name, &1.type})

    for {key, value} <- data,
        Map.has_key?(types, key),
        problem <- Data.problems(Map.fetch!(types, key), value, values) do
      "field #{inspect(key)}: #{problem}"
    end
  end
end

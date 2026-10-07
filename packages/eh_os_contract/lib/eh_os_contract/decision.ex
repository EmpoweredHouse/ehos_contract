defmodule EhOsContract.Decision do
  # What a decision has to be for the engine to append it (plan W4): the rules dispatch
  # holds a decision to, in one place, so that the code that checks a decision outside
  # dispatch — a scenario, later a property test — calls them rather than a copy.
  #
  # Dispatch holds a decision to `held!/6`. `EhOsContract.ScenarioCase` holds it to
  # `admitted/4` and `lifecycle!/4` only: a scenario does not yet check that an event is
  # about the unit that decided it, or that its fields fit, so a decision can pass its
  # scenario and still be refused by dispatch.
  #
  # A decision is code, and code can build a struct the contract's macros never saw
  # (v2 §5). So after it returns, everything it produced is held to its declaration:
  #
  # - `admitted/4` — each struct produced is one the declaration allows: an event among
  #   the command's `emits`, a command among a reaction's `issues`;
  # - `held!/6` — everything dispatch requires of a command's events before it appends
  #   them: admitted, about the unit that decided them, with fields that fit, and allowed
  #   by the unit's lifecycle from where it stood.
  #
  # None of these is a business outcome. A decision that breaks one is a defect, and
  # nothing is appended.
  @moduledoc false

  alias EhOsContract.{Codec, Lifecycle, Model}

  @typedoc "Why a struct produced is not one the declaration allows."
  @type refusal :: {:not_a_struct, term()} | {:not_allowed, struct()}

  @doc """
  Each of `structs`, named by the declaration it is an instance of — `{name, struct}`,
  in order — when every one is a struct of a `kind` (`:event` or `:command`) among
  `allowed`; otherwise the first that is not, and why. The caller says it in its own
  words, since a scenario and dispatch say it to different readers.
  """
  @spec admitted(map(), :event | :command, [term()], [atom()]) ::
          {:ok, [{atom(), struct()}]} | {:error, refusal()}
  def admitted(model, kind, structs, allowed) do
    modules = Map.new(allowed, &{Model.module_for(model, kind, &1), &1})

    Enum.reduce_while(structs, {:ok, []}, fn struct, {:ok, named} ->
      cond do
        not is_struct(struct) -> {:halt, {:error, {:not_a_struct, struct}}}
        name = Map.get(modules, struct.__struct__) -> {:cont, {:ok, [{name, struct} | named]}}
        true -> {:halt, {:error, {:not_allowed, struct}}}
      end
    end)
    |> case do
      {:ok, named} -> {:ok, Enum.reverse(named)}
      error -> error
    end
  end

  @doc """
  The events a command's decision emitted, held to everything dispatch requires before
  it appends them, and the unit's status after them.

  `declaration` is the command's, `unit` the unit that decided it, `status` where the
  unit stood (`nil` for a unit with no lifecycle, or one not yet started), `command`
  the command decided and `events` what the decision returned. Each event is returned
  with its declaration, `{event_declaration, event}`, in order. `values`
  are the domain's values by name (`EhOsContract.Codec.values/1`), read from the model's
  domain when not given.

  Raises `ArgumentError` naming the command, and saying that nothing was appended,
  when an event is not among the command's `emits`, carries another unit's identity —
  it would be folded into this unit's stream — has fields that do not fit their
  types, or is one the lifecycle does not allow from `status` (`Lifecycle.decided!/4`).
  """
  @spec held!(map(), map(), map(), Lifecycle.status(), struct(), [term()], map() | nil) ::
          {[{map(), struct()}], Lifecycle.status()}
  def held!(model, declaration, unit, status, command, events, values \\ nil) do
    # Dispatch has the domain's values already, and passes them; read them otherwise.
    values = values || Codec.values(model.domain)
    modules = Map.new(declaration.emits, &{Model.module_for(model, :event, &1), &1})

    emitted =
      for event <- events do
        name = emitted_name!(model, declaration, modules, event)
        event_declaration = Enum.find(model.events, &(&1.name == name))
        same_unit!(declaration, unit, command, event, name)
        fits!(model, declaration, event_declaration, event, values, name)
        {event_declaration, event}
      end

    {emitted, lifecycle!(unit, status, declaration.name, Enum.map(emitted, &elem(&1, 0).name))}
  end

  @doc """
  What `names`, emitted in order, leave `unit` in from `status`, held to its lifecycle:
  `status` unchanged for a unit that declares none. Raises `ArgumentError` naming
  `command` for an event the graph does not allow (`Lifecycle.decided!/4`).
  """
  @spec lifecycle!(map(), Lifecycle.status(), atom(), [atom()]) :: Lifecycle.status()
  def lifecycle!(unit, status, command, names) do
    case Lifecycle.of(unit) do
      nil -> status
      lifecycle -> Lifecycle.decided!(lifecycle, status, command, names)
    end
  end

  # The same rule as `admitted/4`, with the map built once per decision, not per event.
  defp emitted_name!(model, declaration, modules, event) do
    (is_struct(event) && Map.get(modules, event.__struct__)) ||
      raise ArgumentError,
            "command #{inspect(declaration.name)} of #{inspect(model.module)} decided " <>
              "#{describe(event)}, which is not among the events it emits: " <>
              "#{inspect(declaration.emits)}. Nothing was appended."
  end

  # The event joins the unit that decided it — its stream, or its boundary's own
  # events — so it has to be about the same unit: one carrying another identity would
  # be folded into this unit's state.
  defp same_unit!(declaration, unit, command, event, name) do
    for field <- unit.identity, Map.fetch!(event, field) != Map.fetch!(command, field) do
      raise ArgumentError,
            "command #{inspect(declaration.name)} decided event #{inspect(name)} for another " <>
              "unit: its #{field} is not the command's, and an event joins the stream of the " <>
              "unit that decided it. Nothing was appended."
    end
  end

  defp fits!(model, declaration, event_declaration, event, values, name) do
    case Codec.problems(event_declaration.fields, event, values, model.domain) do
      [] ->
        :ok

      problems ->
        raise ArgumentError,
              "command #{inspect(declaration.name)} decided event #{inspect(name)} with fields " <>
                "that do not fit: #{inspect(problems)}. Nothing was appended."
    end
  end

  defp describe(%module{}), do: "%#{inspect(module)}{}"
  defp describe(other), do: inspect(other)

  @doc """
  The invariant `command` is refused on when `person`, the subject of whoever issues it,
  is not the one its `actor_is` field of `state` holds (plan DD, A1, #247); `nil` when
  they are, or when the command names nobody who must issue it. A field still empty, or
  an empty subject, names nobody, so it is refused. Dispatch asks it for a credential;
  a scenario, for the person it names with `as`.
  """
  @spec not_the_person(map(), map(), String.t() | nil) :: atom() | nil
  def not_the_person(%{actor_is: %{field: field, or_rejects: invariant}}, state, person) do
    value = Map.get(state, field)
    if is_binary(person) and value == person, do: nil, else: invariant
  end

  def not_the_person(_command, _state, _person), do: nil
end

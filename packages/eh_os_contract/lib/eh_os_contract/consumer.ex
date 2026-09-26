defmodule EhOsContract.Consumer do
  @moduledoc """
  One consumer taking one event (v2 §12): what a read model, a policy and an effect
  each do with it. Dispatch runs it inside its transaction for a consumer delivered
  `:in_transaction`; `EhOsContract.Subscription` runs it for an ordered one, and
  `EhOsContract.EffectJob` for an effect delivered `:at_least_once`. The three
  paths share this, so a policy reacts the same way wherever it runs.

  - **A read model** projects: its callback returns `:ok`.
  - **A policy** reacts: what its callback issues is dispatched at once, as the
    policy's own actor, with the event as its cause and a key derived from it,
    `"policy:<contract>:<name>:<event id>:<index>"`. A second delivery of the event
    therefore appends nothing. A rejection is the unit's answer and is not a
    failure; a policy reacting to the kind of event it already reacted to down one
    chain is a cycle, and raises.
  - **An effect** acts outside the log: its callback returns `:ok` or
    `{:error, reason}`.
  """

  alias EhOsContract.{Actor, Codec, Dispatcher, Event, Implementations, Meta, Model, Rejection}

  @longest_chain 32

  @doc """
  Hands `event` to `consumer`. `chain` is the path of policies that led to the event,
  each link `"<contract>:<policy>:<type>"`. Raises on anything but what the
  consumer's kind returns; an effect's `{:error, reason}` is returned, since only its
  caller knows whether to roll back or to retry.
  """
  @spec handle!(Implementations.inline(), struct(), [String.t()]) :: :ok | {:error, term()}
  def handle!(%{kind: :read_model} = consumer, event, _chain) do
    case apply(implemented!(consumer), consumer.callback, [event]) do
      :ok ->
        :ok

      other ->
        raise ArgumentError,
              "read model #{inspect(consumer.name)} returned #{inspect(other)} for " <>
                "#{inspect(consumer.callback)}; a projection returns :ok"
    end
  end

  def handle!(%{kind: :effect} = consumer, event, _chain) do
    case apply(implemented!(consumer), consumer.callback, [event]) do
      :ok ->
        :ok

      {:error, _reason} = error ->
        error

      other ->
        raise ArgumentError,
              "effect #{inspect(consumer.name)} returned #{inspect(other)} for " <>
                "#{inspect(consumer.callback)}; an effect returns :ok or {:error, reason}"
    end
  end

  def handle!(%{kind: :policy} = consumer, event, chain) do
    module = implemented!(consumer)
    model = Model.fetch(consumer.contract)
    policy = Enum.find(model.policies, &(&1.name == consumer.name))
    link = link(consumer)

    # The cycle guard v1's emitter had: a policy that reacts, down one chain, to the
    # kind of event it has already reacted to would dispatch for ever.
    if link in chain or length(chain) >= @longest_chain do
      raise ArgumentError,
            "policy #{inspect(consumer.name)} of #{inspect(consumer.contract)} reacts to " <>
              "#{inspect(event.__struct__)} again down one chain of dispatches, which would " <>
              "never end: #{inspect(Enum.reverse([link | chain]))}"
    end

    case apply(module, consumer.callback, [event]) do
      {:ok, commands} when is_list(commands) ->
        dispatch_issued!(consumer, event, commands, {model, policy.issues}, [link | chain])

      other ->
        raise ArgumentError,
              "policy #{inspect(consumer.name)} returned #{inspect(other)}; it returns " <>
                "{:ok, commands}"
    end
  end

  @doc "Where a failure of `consumer` happened, as a `failed` row names it."
  @spec label(Implementations.inline() | Implementations.consumer()) :: String.t()
  def label(consumer), do: "#{consumer.kind}:#{consumer.name}"

  @doc """
  An event as its consumers take it: the struct of the contract that declares its
  type, with `__meta__` from the row. Raises when no contract of the host declares the
  type, or the payload no longer fits it.
  """
  @spec decode!(Event.t()) :: struct()
  def decode!(%Event{} = row) do
    model =
      case Model.fetch(Module.safe_concat([row.contract])) do
        %{kind: :contract, units: _} = model -> model
        _v1 -> raise ArgumentError, "#{row.contract} is not a v2 contract"
      end

    decode!(model, Codec.values(model.domain), row)
  end

  @doc false
  @spec decode!(map(), map(), Event.t()) :: struct()
  def decode!(model, values, %Event{} = row) do
    declaration =
      Enum.find(model.events, &(&1.type == row.type)) ||
        raise ArgumentError,
              "#{inspect(model.module)} declares no event of type #{inspect(row.type)}, " <>
                "which its log holds at position #{row.position}"

    case Codec.decode(declaration.fields, row.payload, values) do
      {:ok, fields} ->
        struct!(
          Model.module_for(model, :event, declaration.name),
          Map.put(fields, :__meta__, %Meta{
            actor: row.actor,
            occurred_at: row.occurred_at,
            correlation_id: row.correlation_id,
            causation_id: row.causation_id,
            id: row.id,
            position: row.position
          })
        )

      {:error, problems} ->
        raise ArgumentError,
              "the event at position #{row.position} no longer fits #{inspect(row.type)} as " <>
                "declared: #{inspect(problems)}"
    end
  end

  # One link of a chain: the policy, and the type of the event it reacted to.
  defp link(consumer), do: "#{inspect(consumer.contract)}:#{consumer.name}:#{consumer.type}"

  defp dispatch_issued!(consumer, event, commands, {model, issues}, chain) do
    allowed = MapSet.new(issues, &Model.module_for(model, :command, &1))

    for {command, index} <- Enum.with_index(commands) do
      unless is_struct(command) and MapSet.member?(allowed, command.__struct__) do
        raise ArgumentError,
              "policy #{inspect(consumer.name)} issued #{describe(command)}, which is not among " <>
                "the commands it issues: #{inspect(issues)}"
      end

      opts = [
        actor: Actor.reaction(:policy, consumer.name),
        causation_id: event.__meta__.id,
        correlation_id: event.__meta__.correlation_id,
        idempotency_key:
          "policy:#{inspect(consumer.contract)}:#{consumer.name}:#{event.__meta__.id}:#{index}",
        chain: chain
      ]

      case Dispatcher.dispatch(consumer.contract, command, opts) do
        {:ok, _receipt} ->
          :ok

        # A rejection is the unit's answer, and its row is written: the policy asked
        # and was told no. The command that set it off still stands.
        {:error, %Rejection{}} ->
          :ok

        {:error, reason} ->
          raise ArgumentError,
                "policy #{inspect(consumer.name)} issued #{describe(command)}, and dispatch " <>
                  "refused it: #{inspect(reason)}"
      end
    end

    :ok
  end

  defp implemented!(%{module: nil} = consumer) do
    raise ArgumentError,
          "#{consumer.kind} #{inspect(consumer.name)} of #{inspect(consumer.contract)} takes " <>
            "events and no module implements it; bind one with " <>
            "`use #{inspect(consumer.contract)}, #{consumer.kind}: #{inspect(consumer.name)}`"
  end

  defp implemented!(%{module: module}), do: module

  defp describe(%module{}), do: "%#{inspect(module)}{}"
  defp describe(other), do: inspect(other)
end

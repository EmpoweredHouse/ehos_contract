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

  alias EhOsContract.{
    Actor,
    Codec,
    Dispatcher,
    Erased,
    Event,
    Implementations,
    Meta,
    Model,
    Personal,
    Rejection
  }

  @longest_chain 32

  @doc """
  Hands `event` to `consumer`. `chain` is the path of policies that led to the event,
  each link `"<contract>:<policy>:<type>"`. Raises on anything but what the
  consumer's kind returns; an effect's `{:error, reason}` is returned, since only its
  caller knows whether to roll back or to retry.
  """
  @spec handle!(Implementations.inline(), struct(), [String.t()]) :: :ok | {:error, term()}
  # An erasure: the read model forgets the subject, if it holds that type's data at
  # all (v2 §14). One nobody implemented has written nothing to forget, and must not
  # stop every erasure of the type.
  def handle!(%{kind: :read_model, callback: :forget} = consumer, %Erased{} = erased, _chain) do
    if consumer.module != nil and MapSet.member?(consumer.forgets, erased.subject),
      do: forget!(consumer, erased),
      else: :ok
  end

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

    # A cycle guard: a policy that reacts, down one chain, to the
    # kind of event it has already reacted to would dispatch for ever.
    if link in chain or length(chain) >= @longest_chain do
      raise ArgumentError,
            "policy #{inspect(consumer.name)} of #{inspect(consumer.contract)} reacts to " <>
              "#{inspect(event.__struct__)} again down one chain of dispatches, which would " <>
              "never end: #{inspect(Enum.reverse([link | chain]))}"
    end

    case apply(module, consumer.callback, [event]) do
      {:ok, commands} when is_list(commands) ->
        issue!(consumer, :policy, event.__meta__, commands, {model, policy.issues}, [link | chain])

      other ->
        raise ArgumentError,
              "policy #{inspect(consumer.name)} returned #{inspect(other)}; it returns " <>
                "{:ok, commands}"
    end
  end

  @doc "Where a failure of `consumer` happened, as a `failed` row names it."
  @spec label(Implementations.inline() | Implementations.consumer()) :: String.t()
  def label(consumer), do: "#{consumer.kind}:#{consumer.name}"

  defp forget!(consumer, erased) do
    case implemented!(consumer).forget(erased.subject, erased.id) do
      :ok ->
        :ok

      other ->
        raise ArgumentError,
              "read model #{inspect(consumer.name)} returned #{inspect(other)} from forget/2; " <>
                "it returns :ok"
    end
  end

  @doc """
  An event as its consumers take it: the struct of the contract that declares its
  type, with `__meta__` from the row. Raises when no contract of the host declares the
  type, or the payload no longer fits it.

  A personal field is opened with its subject's key, read for this row alone and
  only when the row has a sealed field; once the subject is erased it holds
  `EhOsContract.Erased`. A key missing for a subject never erased raises. The
  erasure itself, `eh_os_contract.subject_erased`, is declared by no contract, and
  reads as the `EhOsContract.Erased` it names.
  """
  @spec decode!(Event.t()) :: struct()
  def decode!(%Event{type: type, payload: payload} = row) do
    if type == Personal.erased_type(),
      do: Personal.erased_event(payload),
      else: decode_declared!(row)
  end

  defp decode_declared!(row) do
    model =
      case Model.fetch(Module.safe_concat([row.contract])) do
        %{kind: :contract, units: _} = model -> model
        _other -> raise ArgumentError, "#{row.contract} is not a contract"
      end

    values = Codec.values(model.domain)
    [decoded] = decode_all!(model, values, [row])
    decoded
  end

  @doc false
  # Rows of one contract's log, decoded with every key they need read in one query:
  # a stream folded for a decision is one query, not one per event.
  @spec decode_all!(map(), map(), [Event.t()]) :: [struct()]
  def decode_all!(model, values, rows) do
    declared = Enum.map(rows, &{declaration!(model, &1), &1})

    subjects =
      for {declaration, row} <- declared,
          subject <- Codec.subjects(declaration.fields, row.payload, values, :stored),
          uniq: true,
          do: subject

    repo = Application.fetch_env!(:eh_os_contract, :repo)
    keys = Personal.for_reading(repo, subjects)

    # Only a subject without any key can have been erased, and only then is it asked.
    keyed = MapSet.new(Map.keys(keys), fn {type, id, _version} -> {type, id} end)

    erased =
      Personal.erased_among(
        repo,
        Enum.reject(subjects, fn {t, id} -> MapSet.member?(keyed, {Atom.to_string(t), id}) end)
      )

    for {declaration, row} <- declared do
      decode!(model, values, declaration, row, Personal.opener(keys, row.type, erased))
    end
  end

  defp declaration!(model, row) do
    Enum.find(model.events, &(&1.type == row.type)) ||
      raise ArgumentError,
            "#{inspect(model.module)} declares no event of type #{inspect(row.type)}, " <>
              "which its log holds at position #{row.position}"
  end

  defp decode!(model, values, declaration, row, open) do
    case Codec.decode(declaration.fields, row.payload, values, open: open) do
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

  @doc false
  # What a reaction issued, dispatched at once as the reaction's own actor, `:policy`
  # or `:pm`, with `source` — the event it reacted to, or the timer's — as its cause
  # and a key derived from it, so a second delivery appends nothing. A rejection is
  # the unit's answer; anything else dispatch refuses raises.
  @spec issue!(map(), :policy | :pm, map(), term(), {map(), [atom()]}, [String.t()]) :: :ok
  def issue!(consumer, kind, source, commands, {model, issues}, chain) do
    allowed = MapSet.new(issues, &Model.module_for(model, :command, &1))
    what = if kind == :policy, do: "policy", else: "process manager"

    unless is_list(commands) do
      raise ArgumentError,
            "#{what} #{inspect(consumer.name)} returned #{inspect(commands)}; it returns " <>
              "{:ok, commands}"
    end

    for {command, index} <- Enum.with_index(commands) do
      unless is_struct(command) and MapSet.member?(allowed, command.__struct__) do
        raise ArgumentError,
              "#{what} #{inspect(consumer.name)} issued #{describe(command)}, which is not " <>
                "among the commands it issues: #{inspect(issues)}"
      end

      opts = [
        actor: Actor.reaction(kind, consumer.name),
        causation_id: source.id,
        correlation_id: source.correlation_id,
        idempotency_key: reaction_key(kind, consumer.contract, consumer.name, source.id, index),
        chain: chain
      ]

      case Dispatcher.dispatch(consumer.contract, command, opts) do
        {:ok, _receipt} ->
          :ok

        # A rejection is the unit's answer, and its row is written: the reaction asked
        # and was told no. What set it off still stands.
        {:error, %Rejection{}} ->
          :ok

        # So is an erasure's: the command would have written an erased subject's data
        # again (v2 §14), and nothing was. Raising would roll back what set the
        # reaction off, or stop an ordered consumer for every subject.
        {:error, :subject_erased} ->
          :ok

        {:error, reason} ->
          raise ArgumentError,
                "#{what} #{inspect(consumer.name)} issued #{describe(command)}, and dispatch " <>
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

  @doc false
  # The key a reaction's command is dispatched with: one per event and command, so a
  # delivery again is the same command. Held to dispatch's rule as every key is; one that
  # would break it — names past what 255 bytes leave, or a quoted module — is its SHA-256
  # in the same form, and the key of every other reaction stays as it always was.
  @spec reaction_key(atom(), module(), atom(), String.t(), non_neg_integer()) :: String.t()
  def reaction_key(kind, contract, name, id, index) do
    key = "#{kind}:#{inspect(contract)}:#{name}:#{id}:#{index}"

    if Dispatcher.idempotency_key?(key),
      do: key,
      else: "#{kind}:sha256:" <> Base.encode16(:crypto.hash(:sha256, key), case: :lower)
  end
end

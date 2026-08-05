defmodule PNS.Job do
  @moduledoc """
  The Oban worker that runs one asynchronous handler.

  Oban gives at-least-once, so this event **will arrive a second time**.
  Idempotency here is not a good practice but a correctness condition — which is
  why the handler macro refuses `async: true` without a key.

  The whole thing is deliberately **not** wrapped in a transaction. An
  asynchronous handler exists precisely to do I/O against the outside world, and a
  transaction around I/O holds a pooled connection for the duration of the call.
  The price is that a failure between the effect and the handling row produces a
  repeat — and that is what the idempotency key is for.
  """

  use Oban.Worker, queue: :events, max_attempts: 3

  alias PNS.EventHandling

  @repo Application.compile_env!(:pns_prototype, :repo)

  @impl Oban.Worker
  def perform(%Oban.Job{args: args, attempt: attempt}) do
    handler = resolve!(args["handler"])
    meta = handler.__pns_handler__()
    event_def = meta.contract.event(meta.event)
    payload = PNS.Payload.cast(event_def, args["payload"])

    ctx = %{
      # The trap from notes §3, closed here: the job runs in a different BEAM
      # process, so correlation has to be serialised into its arguments. Without
      # that the chain breaks at the boundary the most interesting processes
      # cross.
      correlation_id: args["correlation_id"],
      causation_id: args["causation_id"],
      actor: args["actor"],
      attempt: attempt,
      idempotency_key: idempotency_key(event_def, args, payload)
    }

    started = System.monotonic_time(:microsecond)

    {status, error, emissions} =
      try do
        case handler.handle(payload, ctx) do
          :ok ->
            {"ok", nil, []}

          {:ok, list} when is_list(list) ->
            # Inside the `try`, so an undeclared emission lands where every other
            # handler failure lands — recorded against the event with its message —
            # instead of crashing after the handling row has already claimed success.
            PNS.Handler.verify_publications!(meta, list)
            {"ok", nil, list}

          {:ok, _} ->
            {"ok", nil, []}

          {:error, reason} ->
            {"error", inspect(reason), []}
        end
      rescue
        e -> {"error", Exception.message(e), []}
      end

    repo().insert!(%EventHandling{
      event_id: args["event_id"],
      handler: args["handler"],
      attempt: attempt,
      status: status,
      duration_us: System.monotonic_time(:microsecond) - started,
      error: error,
      inserted_at: DateTime.utc_now()
    })

    if status == "ok" do
      PNS.Emitter.emit_all(meta.contract, emissions, ctx)
      :ok
    else
      {:error, error}
    end
  end

  # The idempotency key comes from the `identity:` of **the event in the
  # contract**, not from the handler's declaration. A fact has one identity, while
  # one event can have many handlers — held on the handler it would drift between
  # them.
  @spec idempotency_key(map(), map(), map()) :: String.t()
  defp idempotency_key(%{identity: nil}, args, _payload), do: args["event_id"]

  defp idempotency_key(%{identity: fields, name: name}, _args, payload) do
    values =
      Enum.map(fields, fn field ->
        Map.get(payload, field) || Map.get(payload, to_string(field))
      end)

    Enum.join([name | values], ":")
  end

  @spec resolve!(String.t()) :: module()
  defp resolve!("Elixir." <> _ = name), do: String.to_existing_atom(name)
  defp resolve!(name), do: String.to_existing_atom("Elixir." <> name)

  defp repo, do: @repo
end

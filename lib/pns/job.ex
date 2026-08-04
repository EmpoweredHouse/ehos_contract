defmodule PNS.Job do
  @moduledoc """
  Worker Obana uruchamiający jeden handler asynchroniczny.

  Oban daje at-least-once, więc to zdarzenie **przyjdzie drugi raz**.
  Idempotencja nie jest tu dobrą praktyką, a warunkiem poprawności — dlatego
  makro handlera nie pozwala zadeklarować `async: true` bez klucza.

  Świadomie **nie** owijam całości w transakcję. Handler asynchroniczny
  istnieje właśnie po to, żeby robić I/O na zewnątrz, a transakcja wokół I/O
  trzyma połączenie z puli przez cały czas trwania wywołania. Cena jest ta, że
  awaria między efektem a zapisem obsługi daje powtórkę — i po to jest klucz
  idempotencji.
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
      # Pułapka z notatek §3, tu domknięta: job leci w innym procesie BEAM-a,
      # więc korelacja musi być zserializowana do argumentów. Bez tego łańcuch
      # urywa się na granicy, którą przechodzą najciekawsze procesy.
      correlation_id: args["correlation_id"],
      causation_id: args["causation_id"],
      actor: args["actor"],
      attempt: attempt,
      idempotency_key: idempotency_key(meta, args, payload)
    }

    started = System.monotonic_time(:microsecond)

    {status, error, emissions} =
      try do
        case handler.handle(payload, ctx) do
          :ok -> {"ok", nil, []}
          {:ok, list} when is_list(list) -> {"ok", nil, list}
          {:ok, _} -> {"ok", nil, []}
          {:error, reason} -> {"error", inspect(reason), []}
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

  defp idempotency_key(%{idempotency_key: nil}, args, _payload), do: args["event_id"]

  defp idempotency_key(%{idempotency_key: fields}, args, payload) do
    values =
      fields
      |> List.wrap()
      |> Enum.map(fn field -> Map.get(payload, field) || Map.get(payload, to_string(field)) end)

    Enum.join([args["event_type"] | values], ":")
  end

  defp resolve!("Elixir." <> _ = name), do: String.to_existing_atom(name)
  defp resolve!(name), do: String.to_existing_atom("Elixir." <> name)

  defp repo, do: @repo
end

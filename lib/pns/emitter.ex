defmodule PNS.Emission do
  @moduledoc "Zamiar wyemitowania zdarzenia, zwracany przez czystą funkcję decyzyjną."
  defstruct [:name, :payload]
end

defmodule PNS.Payload do
  @moduledoc """
  Payload jest deklarowany w kontrakcie, więc deserializacja jest typowana.

  To jedna z rzeczy, które kontrakt daje darmo: po przejściu przez JSON
  (kolejka, baza) klucze wracają jako stringi, ale kontrakt wie, jakie pola
  zadeklarowano — więc handler synchroniczny i asynchroniczny widzą **ten sam
  kształt**. Bez kontraktu trzeba by to trzymać w dwóch miejscach.
  """

  def to_storage(payload) do
    Map.new(payload, fn {k, v} -> {to_string(k), v} end)
  end

  def cast(event_def, payload) do
    declared = Map.keys(event_def.payload)

    Map.new(payload, fn {key, value} ->
      key_atom = Enum.find(declared, &(to_string(&1) == to_string(key)))
      {key_atom || to_string(key), value}
    end)
  end
end

defmodule PNS.Emitter do
  @moduledoc """
  Podział dispatchu przebiega po **granicy transakcji**, nie po preferencji
  programisty (ADR §9-10, notatki §4).

  Cała decyzja jest widoczna w jednej funkcji i to jest celowe: jeśli nie
  mieści się w kilkudziesięciu linijkach, argument za własną warstwą emisji
  jest słabszy niż zapisany w rekordzie.
  """

  alias PNS.{Event, EventHandling, Payload, Registry}

  @repo Application.compile_env!(:pns_prototype, :repo)

  @doc """
  Emituje zdarzenie: zapis do logu, handlery synchroniczne w tej samej
  transakcji, joby asynchroniczne wstawione w tej samej transakcji.

  Handler synchroniczny, który rzuci, wywala całą transakcję — i to jest
  poprawne tylko dlatego, że takie handlery są ograniczone do stanu pochodnego
  w tej samej bazie. Nie ma czego ponawiać, bo nic się nie stało.
  """
  def emit(contract, type, payload, ctx \\ %{}) do
    repo = repo()

    if repo.in_transaction?() do
      {:ok, do_emit(repo, contract, type, payload, ctx)}
    else
      repo.transaction(fn -> do_emit(repo, contract, type, payload, ctx) end)
    end
  end

  def emit!(contract, type, payload, ctx \\ %{}) do
    {:ok, event} = emit(contract, type, payload, ctx)
    event
  end

  @doc """
  Emituje listę zamiarów zwróconych przez funkcję decyzyjną.

  Korelacja jest ustalana **raz, dla całej listy**. To wyszło jako błąd w
  pierwszym przebiegu testów: bez tego każde zdarzenie z jednej komendy
  dostawało własne `correlation_id`, więc jedna operacja biznesowa rozpadała się
  w logu na cztery niepowiązane fakty — i cały łańcuch, po który ten log
  istnieje, nie dawał się odtworzyć.

  Zamiary z jednej funkcji decyzyjnej są **rodzeństwem**, nie łańcuchem: żaden
  nie spowodował żadnego, spowodowała je ta sama komenda. Dlatego wspólna
  korelacja i wspólna przyczyna, a nie causation między nimi.
  """
  def emit_all(contract, emissions, ctx \\ %{}) do
    repo = repo()
    ctx = Map.put_new_lazy(ctx, :correlation_id, &Ecto.UUID.generate/0)

    run = fn ->
      Enum.map(emissions, fn %PNS.Emission{name: name, payload: payload} ->
        do_emit(repo, contract, name, payload, ctx)
      end)
    end

    if repo.in_transaction?(), do: {:ok, run.()}, else: repo.transaction(run)
  end

  defp do_emit(repo, contract, type, payload, ctx) do
    unless contract.event?(type) do
      raise ArgumentError,
            "#{inspect(contract)} nie deklaruje zdarzenia #{inspect(type)}. " <>
              "Publikacja dynamiczna jest nielegalna — od tego zależy, czy graf statyczny " <>
              "jest faktem, czy heurystyką."
    end

    event_def = contract.event(type)
    correlation_id = ctx[:correlation_id] || Ecto.UUID.generate()

    # Polityka `retain` jest stosowana **raz**, przed czymkolwiek innym, i to,
    # co z niej wyjdzie, jest jedyną wersją tego payloadu w systemie: idzie do
    # logu, do handlerów synchronicznych i do argumentów joba.
    #
    # Kusiło, żeby handlery dostawały pełną wartość, a log hash — ale wtedy
    # asynchroniczny handler dostaje pełną wartość przez `oban_jobs`, czyli
    # przez tabelę, której `retain` nie obejmuje. Polityka retencji obchodzona
    # przez kolejkę jest gorsza niż jej brak, bo wygląda na spełnioną.
    #
    # Konsekwencja jest jawna i należy do kontraktu, nie do kodu: jeśli handler
    # potrzebuje surowej wartości, to pole nie może mieć `:hash`.
    stored = apply_retain(payload, event_def)
    cast_payload = Payload.cast(event_def, stored)

    # Liczona z payloadu **po** `retain`, więc klucz przebiegu jest odtwarzalny
    # z samego logu — a nie tylko z logu plus wiedzy, co odpadło po drodze.
    {process, instance_id} = PNS.Instance.key(contract, type, cast_payload)

    event =
      repo.insert!(%Event{
        type: to_string(type),
        contract: inspect(contract),
        contract_version: contract.version(),
        process: process,
        instance_id: instance_id,
        correlation_id: correlation_id,
        causation_id: ctx[:causation_id],
        payload: Payload.to_storage(stored),
        actor: ctx[:actor] && to_string(ctx[:actor]),
        occurred_at: DateTime.utc_now()
      })

    # Kontekst dla obsługi: korelacja przechodzi dalej, a to zdarzenie staje
    # się przyczyną wszystkiego, co z niego wynika.
    child_ctx = %{
      correlation_id: correlation_id,
      causation_id: event.id,
      actor: ctx[:actor]
    }

    dispatch_sync(repo, contract, type, cast_payload, child_ctx, event)
    dispatch_async(type, cast_payload, child_ctx, event)

    event
  end

  defp dispatch_sync(repo, contract, type, payload, ctx, event) do
    for handler <- Registry.sync_handlers_for(type) do
      started = System.monotonic_time(:microsecond)

      result =
        try do
          handler.module.handle(payload, ctx)
        rescue
          error ->
            # Wiersz obsługi zniknie razem z transakcją — i to jest poprawne:
            # nic się nie stało, więc log nie może twierdzić, że się stało.
            reraise error, __STACKTRACE__
        end

      repo.insert!(%EventHandling{
        event_id: event.id,
        handler: inspect(handler.module),
        status: "ok",
        duration_us: System.monotonic_time(:microsecond) - started,
        inserted_at: DateTime.utc_now()
      })

      # Handler może zwrócić dalsze zamiary — lecą w tej samej transakcji.
      case result do
        {:ok, emissions} when is_list(emissions) ->
          Enum.each(emissions, fn %PNS.Emission{name: name, payload: p} ->
            do_emit(repo, contract, name, p, ctx)
          end)

        _ ->
          :ok
      end
    end
  end

  defp dispatch_async(type, payload, ctx, event) do
    for handler <- Registry.async_handlers_for(type) do
      # Wstawienie joba idzie w tej samej transakcji — to jest outbox darmo,
      # i to jest własność, która zdecydowała o Obanie.
      #
      # Pułapka z notatek §3: job leci później, w innym procesie BEAM-a, więc
      # korelacja musi być zserializowana do argumentów. Bez tego łańcuch
      # urywa się dokładnie na granicy, którą przechodzą najciekawsze procesy.
      %{
        "handler" => inspect(handler.module),
        "event_id" => event.id,
        "event_type" => to_string(type),
        "payload" => Payload.to_storage(payload),
        "correlation_id" => ctx.correlation_id,
        "causation_id" => ctx.causation_id,
        "actor" => ctx[:actor] && to_string(ctx[:actor])
      }
      |> PNS.Job.new()
      |> Oban.insert!()
    end
  end

  defp apply_retain(payload, event_def) do
    Enum.reduce(event_def.retain, payload, fn {field, policy}, acc ->
      case {policy, Map.fetch(acc, field)} do
        {:persist, _} -> acc
        {_, :error} -> acc
        {:drop, _} -> Map.delete(acc, field)
        {:hash, {:ok, value}} -> Map.put(acc, field, hash(value))
      end
    end)
  end

  defp hash(value) do
    "sha256:" <>
      (:crypto.hash(:sha256, :erlang.term_to_binary(value))
       |> Base.encode16(case: :lower)
       |> binary_part(0, 16))
  end

  defp repo, do: @repo
end

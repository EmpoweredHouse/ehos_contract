defmodule PNS.Handler do
  @moduledoc """
  Wymuszenie w czasie kompilacji (ADR §5-6, notatki §2).

  Sprawdzenia dzieją się **w ciele makra, nie w `quote`** — to tworzy
  zależność kompilacyjną, która każe kompilatorowi wziąć kontrakt pierwszy,
  a `__CALLER__` daje file i line wskazujące na handler, nie na bibliotekę.
  """

  @callback handle(payload :: map(), ctx :: map()) :: :ok | {:ok, list()} | {:error, term()}

  @doc false
  defmacro __using__(opts) do
    caller = __CALLER__
    contract = opts |> Keyword.fetch!(:contract) |> Macro.expand(caller)
    event = Keyword.fetch!(opts, :event)
    publishes = Keyword.get(opts, :publishes, [])
    async = Keyword.get(opts, :async, false)
    idempotency_key = Keyword.get(opts, :idempotency_key)

    # Wymuszenie kolejności kompilacji: bez tego kontrakt mógłby jeszcze nie
    # istnieć, a sprawdzenie niżej zamilkłoby zamiast zadziałać.
    Code.ensure_compiled!(contract)

    unless function_exported?(contract, :__pns_contract__, 0) do
      bail!(caller, "#{inspect(contract)} nie jest kontraktem PNS (brak `use PNS.Contract`)")
    end

    unless contract.event?(event) do
      bail!(
        caller,
        "handler deklaruje zdarzenie #{inspect(event)}, którego nie ma w kontrakcie " <>
          "#{inspect(contract)}. Zadeklarowane zdarzenia: #{inspect(contract.event_names())}"
      )
    end

    for published <- publishes, not contract.event?(published) do
      bail!(
        caller,
        "handler deklaruje `publishes: #{inspect(published)}`, czego nie ma w kontrakcie " <>
          "#{inspect(contract)}"
      )
    end

    if async and is_nil(idempotency_key) do
      bail!(
        caller,
        "handler asynchroniczny musi zadeklarować `idempotency_key:` — Oban daje " <>
          "at-least-once, więc to zdarzenie przyjdzie drugi raz (notatki §4)"
      )
    end

    for field <- List.wrap(idempotency_key), not Map.has_key?(contract.event(event).payload, field) do
      bail!(
        caller,
        "`idempotency_key: #{inspect(field)}` nie jest polem payloadu zdarzenia " <>
          "#{inspect(event)}. Zadeklarowane pola: #{inspect(Map.keys(contract.event(event).payload))}"
      )
    end

    quote do
      @behaviour PNS.Handler

      @doc false
      def __pns_handler__ do
        %{
          module: __MODULE__,
          contract: unquote(contract),
          event: unquote(event),
          publishes: unquote(publishes),
          async: unquote(async),
          idempotency_key: unquote(idempotency_key)
        }
      end
    end
  end

  defp bail!(caller, message) do
    raise CompileError, file: caller.file, line: caller.line, description: message
  end
end

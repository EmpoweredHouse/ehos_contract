defmodule EhOsContract.Instance do
  @moduledoc """
  The identity of **one run** of a process.

  `identity` answers "what makes two occurrences **the same fact**". `instance`
  answers a different question: "what makes two events part of **the same run**".
  The first sits on the event, the second on the process, because a run is a
  property of the process rather than of a single fact.

  The reason is technical, not presentational. A `trace` assertion says "after X,
  eventually Y"; without run identity a Y found for another company in another
  month counts as satisfaction. The same hole is in the counters: an edge
  traversed 49 times by one company looks identical to one traversed once by 49 —
  and the difference between them is the silence this product exists for.

  The key is computed from the payload **after `retain` is applied**, so it is
  reproducible from the log alone. The process name is its first segment: two
  processes can have coinciding field values, and without the prefix their runs
  would merge into one.
  """

  @separator "|"
  @escaped "%7C"
  @percent "%"
  @escaped_percent "%25"

  @doc """
  Returns `{process_name, instance_id}` for an event, or `{nil, nil}` when the
  event belongs to no process.
  """
  @spec key(module(), atom(), map()) :: {String.t(), String.t()} | {nil, nil}
  def key(contract, event_name, payload) do
    case EhOsContract.Model.process_of(contract, event_name) do
      nil -> {nil, nil}
      process -> {to_string(process.name), encode(process, event_name, payload)}
    end
  end

  @spec encode(map(), atom(), map()) :: String.t()
  defp encode(process, event_name, payload) do
    values =
      Enum.map(process.instance, fn field ->
        case fetch(payload, field) do
          {:ok, value} ->
            value
            |> to_string()
            |> String.replace(@percent, @escaped_percent)
            |> String.replace(@separator, @escaped)

          :error ->
            # **Unreachable from `EhOsContract.Emitter` since stage 2.2b, and kept anyway.**
            # Payload validation runs before this and refuses any declared field that
            # is missing, so the emit path can no longer arrive here — the compile gate
            # guarantees the field is declared, validation guarantees it is supplied.
            #
            # It stays because this function is public and a direct caller has nothing
            # in front of it, and because the failure it prevents is the quiet kind: an
            # event landing with an empty key segment, merging with another company's
            # run. Unreachable from one path is not dead.
            raise ArgumentError,
                  "event #{inspect(event_name)} does not carry instance field #{inspect(field)}, " <>
                    "and process #{inspect(process.name)} declares " <>
                    "`instance: #{inspect(process.instance)}`. Without that field there is no way " <>
                    "to say which run this event belongs to."
        end
      end)

    Enum.join([to_string(process.name) | values], @separator)
  end

  @spec fetch(map(), atom()) :: {:ok, term()} | :error
  defp fetch(payload, field) do
    case Map.get(payload, field, Map.get(payload, to_string(field))) do
      nil -> :error
      value -> {:ok, value}
    end
  end
end

defmodule EhOsContract.Conformance.Wire do
  @moduledoc """
  The conformance report as values that survive JSON, and nothing else.

  `EhOsContract.Conformance.report/2` answers in Elixir: module names, atoms, duration
  tuples, `DateTime` structs. None of those crosses a wire unchanged, and two of
  them do not cross at all — `Jason` refuses a tuple outright.

  **This lives in the engine rather than in a transport.** The shape on the wire is
  what a consumer compares against, version to version, so it is part of what this
  package promises. A projection written in whichever web package happens to serve
  it would make the promise a property of the transport.

  ## Why not a `Jason.Encoder` implementation

  Implementing the protocol for `Tuple` would be a library changing how *every*
  tuple in the consuming application encodes. Deriving it for the report's maps
  would not help either: the report is plain maps, not structs. An explicit
  projection is longer and is the only version that keeps its effects inside this
  function.

  ## The mapping, and why each one

  | From | To | Because |
  | --- | --- | --- |
  | module | `inspect/1` | a module is the code's name for itself, and stands only in `module`; the contract is named by its `id:` (`contract`), as every row of the log names it since plan DD, ID4 (#178) |
  | atom | `to_string/1` | JSON has no atoms |
  | map key | `to_string/1` | JSON has no atom keys either |
  | `{n, unit}` | `%{"count" => n, "unit" => "day"}` | a two-element array would make the reader guess which slot is which |
  | `DateTime` | `DateTime.to_iso8601/1` | stated explicitly, so the format does not silently become whatever a dependency prefers |

  Any other tuple raises. A tuple that reaches here is a shape nobody has decided
  how to publish, and guessing at one is how a wire format acquires a field whose
  meaning nobody can reconstruct.
  """

  @doc """
  The report, projected onto strings, numbers, booleans, `nil`, lists and
  string-keyed maps.
  """
  @spec encode(term()) :: term()
  def encode(%DateTime{} = at), do: DateTime.to_iso8601(at)

  def encode(%_struct{} = other) do
    raise ArgumentError,
          "#{inspect(other.__struct__)} has no decided shape on the wire. Add one to " <>
            "EhOsContract.Conformance.Wire rather than letting it encode as whatever its fields are."
  end

  def encode(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {key_to_string(key), encode(value)} end)
  end

  def encode(list) when is_list(list), do: Enum.map(list, &encode/1)

  # The only tuple the report carries is a duration, and `EhOsContract.Duration` is the one
  # place that says what its two slots mean.
  def encode({count, unit}) when is_integer(count) and is_atom(unit) do
    %{"count" => count, "unit" => to_string(unit)}
  end

  def encode(tuple) when is_tuple(tuple) do
    raise ArgumentError,
          "#{inspect(tuple)} has no decided shape on the wire. JSON has no tuples, and " <>
            "guessing at an order for one is how a field nobody can read gets published."
  end

  def encode(atom) when is_atom(atom) and not is_nil(atom) and not is_boolean(atom) do
    case Atom.to_string(atom) do
      "Elixir." <> _ -> inspect(atom)
      plain -> plain
    end
  end

  def encode(other), do: other

  @spec key_to_string(term()) :: String.t()
  defp key_to_string(key) when is_atom(key), do: to_string(key)
  defp key_to_string(key) when is_binary(key), do: key
  defp key_to_string(key), do: to_string(key)
end

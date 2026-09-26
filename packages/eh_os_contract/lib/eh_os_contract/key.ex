defmodule EhOsContract.Key do
  @moduledoc """
  The one escaping every key the store builds goes through (v2 §10.4): stream ids,
  tags and instance ids.

      Key.stream(:visit_settlement, ["w-1"])   #=> "visit_settlement:w-1"
      Key.tag(:visit_id, "w-1")                #=> "visit_id:w-1"
      Key.join(["visit_settlement", "w-1"])    #=> "visit_settlement|w-1"

  Values are joined with `|`, and a `|` or `%` inside a value is percent-escaped,
  as `EhOsContract.Instance` has escaped since 21 August. Without it `a|b` + `c`
  and `a` + `b|c` would be one key: two runs, or two streams, merged. One copy of
  that rule, not one per kind of key.
  """

  @separator "|"

  @doc "Values joined with `|`, each escaped."
  @spec join([term()]) :: String.t()
  def join(values) when is_list(values), do: Enum.map_join(values, @separator, &escape/1)

  @doc "A unit's stream: its name, `:`, then its key values in declared order."
  @spec stream(atom(), [term()]) :: String.t()
  def stream(unit, values) when is_atom(unit), do: "#{unit}:" <> join(values)

  @doc "A tag: the field's name, `:`, then its value."
  @spec tag(atom(), term()) :: String.t()
  def tag(field, value) when is_atom(field), do: "#{field}:" <> escape(value)

  @doc "One value, with `%` and `|` percent-escaped."
  @spec escape(term()) :: String.t()
  def escape(nil),
    do: raise(ArgumentError, "a key has no nil segment: it would merge with every other nil")

  def escape(value) do
    value
    |> to_string()
    |> String.replace("%", "%25")
    |> String.replace(@separator, "%7C")
  end
end

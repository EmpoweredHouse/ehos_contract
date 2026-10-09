defmodule EhOsContract.GraphRenderer.Words do
  @moduledoc """
  The words the views and the panel share: a declaration's kind or a relation's type as
  the reader sees it, a field's type, a count, a duration.
  """

  @doc "A kind or a type as the reader sees it: the name, spaced."
  @spec words(String.t()) :: String.t()
  def words(name), do: String.replace(name, "_", " ")

  @doc "A field's type in words: a name, `list of …`, or `one of …` with an inline enum's values."
  @spec type(term()) :: String.t()
  def type(%{"list" => inner}), do: "list of #{type(inner)}"
  def type(%{"enum" => members}), do: "one of #{Enum.map_join(members, ", ", & &1["value"])}"
  def type(type) when is_binary(type), do: type
  def type(_unknown), do: "?"

  @doc "`n` of `noun`: `1 scenario`, `0 scenarios`, `3 scenarios`."
  @spec count(non_neg_integer(), String.t()) :: String.t()
  def count(1, noun), do: "1 #{noun}"
  def count(n, noun), do: "#{n} #{noun}s"

  @doc "A duration in words, with its number: `1 day`, `24 hours`."
  @spec duration(map()) :: String.t()
  def duration(%{"amount" => amount, "unit" => unit}),
    do: "#{amount} #{if amount == 1, do: unit, else: unit <> "s"}"

  def duration(_other), do: "?"

  @doc "When a process manager's timer fires: `after 14 days`, `at check_at`."
  @spec fires(map()) :: String.t() | nil
  def fires(%{"wait" => %{} = wait}), do: "after #{duration(wait)}"
  def fires(%{"at" => at}) when is_binary(at), do: "at #{at}"
  def fires(_timer), do: nil
end

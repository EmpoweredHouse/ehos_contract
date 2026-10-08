defmodule EhOsContract.GraphRenderer.Words do
  @moduledoc """
  The words the views and the panel share: a declaration's kind or a relation's type as
  the reader sees it, a field's type, a count, and the context-mapping patterns.
  """

  @patterns ~w(partnership shared_kernel separate_ways customer_supplier conformist
               anticorruption_layer open_host_service published_language)
  @symmetric ~w(partnership shared_kernel separate_ways)

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

  @doc "The relation types of the eight context-mapping patterns."
  @spec patterns() :: [String.t()]
  def patterns, do: @patterns

  @doc "Whether a pattern is symmetric, with neither end upstream."
  @spec symmetric?(String.t()) :: boolean()
  def symmetric?(type), do: type in @symmetric
end

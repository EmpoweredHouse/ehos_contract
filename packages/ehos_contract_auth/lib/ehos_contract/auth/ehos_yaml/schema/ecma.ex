defmodule EhosContract.Auth.EhosYaml.Schema.Ecma do
  @moduledoc false
  # A JSON Schema as JSV should build it, so that its patterns mean what JSON Schema says: each
  # `$` that ends the text in a `pattern`, or in a name of `patternProperties`, is written as `\z`,
  # which ends the text in PCRE too. A `$` escaped or in a character class is a dollar sign and
  # stays, and so is what `const`, `enum`, `default` and `examples` hold, which is data. EHOS
  # builds its schemas the same way.

  @data ~w(const enum default examples)
  # These map names to schemas: a property named `pattern` or `default` is a schema like another.
  @named ~w(properties $defs definitions dependentSchemas)

  @doc false
  @spec schema(term()) :: term()
  def schema(%{} = schema) do
    Map.new(schema, fn
      {"pattern", pattern} when is_binary(pattern) ->
        {"pattern", anchor(pattern, <<>>, false)}

      {"patternProperties", %{} = properties} ->
        {"patternProperties",
         Map.new(properties, fn {pattern, value} ->
           {anchor(pattern, <<>>, false), schema(value)}
         end)}

      {key, %{} = schemas} when key in @named ->
        {key, Map.new(schemas, fn {name, value} -> {name, schema(value)} end)}

      {key, value} when key in @data ->
        {key, value}

      {key, value} ->
        {key, schema(value)}
    end)
  end

  def schema(list) when is_list(list), do: Enum.map(list, &schema/1)
  def schema(value), do: value

  # The flag is whether the walk is inside a character class, `[…]`, where only `\` and `]` mean
  # anything to it.
  defp anchor(<<?\\, char::utf8, rest::binary>>, acc, class),
    do: anchor(rest, <<acc::binary, ?\\, char::utf8>>, class)

  defp anchor(<<?[, rest::binary>>, acc, false), do: anchor(rest, <<acc::binary, ?[>>, true)
  defp anchor(<<?], rest::binary>>, acc, true), do: anchor(rest, <<acc::binary, ?]>>, false)
  defp anchor(<<?$, rest::binary>>, acc, false), do: anchor(rest, <<acc::binary, "\\z">>, false)

  defp anchor(<<char::utf8, rest::binary>>, acc, class),
    do: anchor(rest, <<acc::binary, char::utf8>>, class)

  defp anchor(<<>>, acc, _class), do: acc
end

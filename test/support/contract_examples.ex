defmodule ContractExamples do
  @moduledoc """
  Executes one `example` from a contract. Shared by every contract, because
  "an example is a test" is meant to be a property of the DSL rather than of
  TaxVision — which is one of the things the universality gate checks.
  """

  use Boundary, deps: [], exports: []

  import ExUnit.Assertions

  def run(example, rule) do
    {module, function, 1} = rule.function
    {command_name, params} = example.command

    input =
      example.given
      |> Map.put(:command, command_name)
      |> Map.merge(params)

    case example.outcome do
      {:rejected, reason} ->
        assert {:error, ^reason} = apply(module, function, [input])

      {:emits, []} ->
        assert :ok = apply(module, function, [input])

      {:emits, expected} ->
        emissions = apply(module, function, [input])
        assert is_list(emissions), "expected a list of intentions, got #{inspect(emissions)}"
        emitted = Enum.map(emissions, & &1.name)

        # **A subsequence, not equality.** The first version required an example to
        # list everything the function emits — so the example for the rule "without
        # a consistent registry check the month does not open" pinned four events,
        # three of which had nothing to do with that rule. Adding one event to the
        # flow broke every example of that rule, although the rule had not changed.
        # At fifty rules that is a machine for false alarms, that is, for switching
        # the tests off.
        assert subsequence?(expected, emitted),
               """
               the example requires these events to appear among those emitted, in this order:
                 #{inspect(expected)}
               and the function emitted:
                 #{inspect(emitted)}
               """
    end
  end

  # Whether `expected` occurs in `emitted` in that order, not necessarily adjacent.
  defp subsequence?([], _emitted), do: true
  defp subsequence?(_expected, []), do: false
  defp subsequence?([head | tail], [head | rest]), do: subsequence?(tail, rest)
  defp subsequence?(expected, [_ | rest]), do: subsequence?(expected, rest)
end

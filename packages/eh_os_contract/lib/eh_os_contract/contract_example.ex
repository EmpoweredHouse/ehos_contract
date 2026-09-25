defmodule EhOsContract.ContractExample do
  @moduledoc """
  Runs one `example` from a contract as an assertion.

  **"An example is a test" is a property of the DSL, not of anybody's domain**, so
  the runner belongs to the package rather than to a host's `test/support/`. It
  lived there until 2026-08-21 and that was load-bearing in the wrong direction:
  the engine's own fixtures could not check their examples without borrowing a
  module from the client tree, and two hosts would have written it twice.

  In `lib/` rather than in the package's tests for the same reason `Oban.Testing`
  is: a consumer's suite has to be able to call it, and a module compiled only
  under `MIX_ENV=test` in this package does not exist in anybody else's build.

      test "an example is a test" do
        EhOsContract.ContractExample.run(example, EhOsContract.Model.rule(contract, example.rule))
      end
  """

  import ExUnit.Assertions

  @doc """
  Applies the rule's decision function to the example's input and asserts its outcome.

  A `rejected_with:` example asserts the error. A `then:` example asserts that the
  named events appear **among those emitted, in that order** — a subsequence, not
  equality.

  The first version required equality, so the example for "without a consistent
  registry check the month does not open" pinned four events, three of which had
  nothing to do with that rule. Adding one event to the flow broke every example of
  that rule although the rule had not changed. At fifty rules that is a machine for
  false alarms, that is, for switching the tests off.
  """
  @spec run(map(), map()) :: true
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
  @spec subsequence?([atom()], [atom()]) :: boolean()
  defp subsequence?([], _emitted), do: true
  defp subsequence?(_expected, []), do: false
  defp subsequence?([head | tail], [head | rest]), do: subsequence?(tail, rest)
  defp subsequence?(expected, [_ | rest]), do: subsequence?(expected, rest)
end

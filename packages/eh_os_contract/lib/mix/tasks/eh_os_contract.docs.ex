defmodule Mix.Tasks.EhOsContract.Docs do
  @shortdoc "Regenerates the key reference inside docs/contract.md"

  @moduledoc """
  Writes the mechanical part of the contract reference — which keys exist, which
  are required, what an omitted key falls back to — from `EhOsContract.Contract.schema/0`
  into a delimited block of `docs/contract.md`.

  Only that block is generated. Everything around it is prose that a generator
  has no business writing: what a key *means*, why it sits where it sits, and
  which mechanism stops working without it.

  `--check` verifies the block is current and exits non-zero otherwise. That is
  the whole reason this task exists: a hand-maintained key table is a second
  source of truth, and every second source of truth in this project has
  eventually disagreed with the code. `mix check` runs it, so the reference
  cannot rot without a red build.
  """

  use Boundary, classify_to: EhOsContract
  use Mix.Task

  @path "docs/contract.md"
  @start "<!-- pns:reference:start -->"
  @stop "<!-- pns:reference:end -->"

  @impl Mix.Task
  def run(args) do
    :io.setopts(:standard_io, encoding: :unicode)
    {opts, _} = OptionParser.parse!(args, strict: [check: :boolean])

    Mix.Task.run("compile")
    Application.load(:eh_os_contract)

    current = File.read!(@path)
    updated = replace_block(current, reference())

    cond do
      current == updated ->
        Mix.shell().info("#{@path}: reference is current")

      opts[:check] ->
        Mix.raise(
          "#{@path} is out of date with EhOsContract.Contract.schema/0. Run `mix eh_os_contract.docs`.\n" <>
            "The reference is generated precisely so it cannot drift from the code."
        )

      true ->
        File.write!(@path, updated)
        Mix.shell().info("#{@path}: reference regenerated")
    end
  end

  defp replace_block(text, block) do
    [before | _] = String.split(text, @start, parts: 2)
    [_, rest] = String.split(text, @stop, parts: 2)
    before <> @start <> "\n" <> block <> @stop <> rest
  end

  defp reference do
    declarations() <> "\n" <> payload_types()
  end

  # Generated for the same reason as the key table: this is a **closed** set, and a
  # hand-written copy of a closed set is the first place a sixth type appears
  # undocumented.
  defp payload_types do
    rows = Enum.map_join(EhOsContract.Contract.payload_types(), "\n", &"| `#{inspect(&1)}` |")

    """
    ### payload types

    | Type |
    | --- |
    #{rows}
    """
  end

  defp declarations do
    schema = EhOsContract.Contract.schema()

    # Reading order, then anything `schema/0` holds that this list does not name.
    # It used to be the whole list, which meant a seventh declaration kind was
    # **silently omitted** from the generated reference while `--check` reported the
    # file as current — the one failure mode a generated document must not have.
    order = [:event, :process, :trace, :external, :rule, :example, :command]
    order = order ++ (Map.keys(schema) -- order)

    Enum.map_join(order, "\n", fn declaration ->
      keys = Map.fetch!(schema, declaration)

      rows =
        Enum.map_join(keys.required ++ keys.optional, "\n", fn key ->
          required = if key in keys.required, do: "yes", else: "no"

          fallback =
            case Map.fetch(keys.defaults, key) do
              {:ok, value} -> "`#{inspect(value)}`"
              :error -> if key in keys.required, do: "—", else: "`nil`"
            end

          "| `#{key}` | #{required} | #{fallback} |"
        end)

      """
      ### `#{declaration}`

      | Key | Required | Omitted means |
      | --- | --- | --- |
      #{rows}
      """
    end)
  end
end

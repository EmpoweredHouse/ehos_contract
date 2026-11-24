defmodule Fulfilment.ConsumedFieldChangeTest do
  @moduledoc """
  **A change to the structure of an event another contract consumes breaks the
  subscriber's contract and its implementation, and each refusal names the other
  side**; a change the subscriber does not use touches neither.

  The pair is the invented fulfilment's: the warehouse publishes `parcel_packed`,
  shipping consumes it, and its policy `BookCarrier` reads `weight_grams` to book a
  parcel or freight. The test compiles copies of the three real files under a namespace
  of their own — the publisher changed as its author would change it, the rest as they
  are — so what breaks is what would break in the real tree, and the real modules stay
  as they are.

  The subscriber's contract breaks through its scenarios, which feed the policy a
  `parcel_packed` with `weight_grams:`; the contract has no compile dependency on its
  sibling, so the refusal is the rules between modules (`EhosContract.Contract.Links`),
  which the project's compiler runs.
  """

  use ExUnit.Case, async: false

  @publisher "lib/fulfilment/contracts/warehouse.ex"
  @subscriber "lib/fulfilment/contracts/shipping.ex"
  @policy "lib/fulfilment/shipping/book_carrier.ex"

  # The real sources, renamed into `namespace`: every module of the three files, and
  # every reference to them. Orders, the domain and the library stay the real ones, as
  # they would in the tree.
  defp copy(file, namespace, change \\ & &1) do
    file
    |> File.read!()
    |> change.()
    |> String.replace("Fulfilment.Contracts.Warehouse", "#{namespace}.Warehouse")
    |> String.replace("Fulfilment.Contracts.Shipping", "#{namespace}.Shipping")
    |> String.replace("Fulfilment.Shipping.BookCarrier", "#{namespace}.BookCarrier")
  end

  # Spark records a declaration's file and line only with `:debug_info` on, which
  # `mix compile` sets and a string compiled in a test does not.
  defp compile(source, file) do
    previous = Code.get_compiler_option(:debug_info)
    Code.put_compiler_option(:debug_info, true)

    try do
      for {module, _binary} <- Code.compile_string(source, file), do: module
    after
      Code.put_compiler_option(:debug_info, previous)
    end
  end

  # The two contracts compiled and checked against each other, as the project's compiler
  # does; the violations with their file and line. The real orders contract is checked
  # beside them, as in the tree: both identities name its order.
  defp contracts(namespace, change) do
    modules =
      compile(copy(@publisher, namespace, change), @publisher) ++
        compile(copy(@subscriber, namespace), @subscriber) ++ [Fulfilment.Contracts.Orders]

    for {message, anno} <- EhosContract.Contract.Links.check(modules),
        do: {message, anno && to_string(:erl_anno.file(anno)), anno && :erl_anno.line(anno)}
  end

  # The subscriber's implementation compiled against the changed publisher; the
  # compiler's first error, or `:compiled`.
  defp policy(namespace) do
    {result, diagnostics} =
      Code.with_diagnostics(fn ->
        try do
          compile(copy(@policy, namespace), @policy)
          :compiled
        rescue
          CompileError -> :refused
        end
      end)

    case Enum.filter(diagnostics, &(&1.severity == :error)) do
      [] -> result
      [first | _] -> {first.message, first.file, first.position}
    end
  end

  defp namespace(name), do: "FulfilmentFieldChange.#{name}"

  # The publisher's author renames a field on one of their events, and in their own
  # scenarios of it: every line that names the event.
  defp rename_on(event, from, to) do
    fn source ->
      source
      |> String.replace(
        ~r/(event :#{event}[^\n]*\n(?:      [^\n]*\n)*?      field :)#{from}/u,
        "\\1#{to}"
      )
      |> String.split("\n")
      |> Enum.map_join("\n", fn line ->
        if line =~ ":#{event},", do: String.replace(line, "#{from}:", "#{to}:"), else: line
      end)
    end
  end

  test "control: the three files as they are link with nothing to say" do
    ns = namespace("Unchanged")
    assert contracts(ns, & &1) == []
    assert policy(ns) == :compiled
  end

  test "renaming a field the subscriber reads breaks its contract and its implementation" do
    ns = namespace("Renamed")
    rename = rename_on("parcel_packed", "weight_grams", "weight_g")
    assert rename.(File.read!(@publisher)) =~ "field :weight_g, :integer"

    violations = contracts(ns, rename)

    # The subscriber's contract, at each scenario that feeds the policy the event: the
    # field it gives is gone, the one it lacks is required, and each names the
    # publisher's event with the file and line it is declared at.
    lines = File.read!(@subscriber) |> String.split("\n")

    assert length(violations) == 4

    for {message, file, line} <- violations do
      assert file == @subscriber
      assert Enum.at(lines, line - 1) =~ "on :parcel_packed"
      assert message =~ "event :parcel_packed of #{ns}.Warehouse (#{@publisher}:"
    end

    assert Enum.count(violations, fn {m, _, _} -> m =~ "no field :weight_grams" end) == 2
    assert Enum.count(violations, fn {m, _, _} -> m =~ "needs :weight_g" end) == 2

    # The subscriber's implementation, at the pattern that reads the field.
    assert {refusal, file, {policy_line, _column}} = policy(ns)
    assert refusal =~ "unknown key :weight_grams"
    assert Path.relative_to_cwd(file) == @policy

    assert File.read!(@policy) |> String.split("\n") |> Enum.at(policy_line - 1) =~
             "weight_grams: grams"
  end

  test "control: a field the subscriber does not read touches neither side" do
    # An optional field added to the consumed event: nothing the subscriber declares or
    # matches names it.
    ns = namespace("Added")

    add =
      &String.replace(
        &1,
        "event :parcel_packed, \"Parcel packed\" do\n      field :weight_grams, :integer\n",
        "event :parcel_packed, \"Parcel packed\" do\n      field :weight_grams, :integer\n      field :boxes, :integer, optional: true\n"
      )

    assert File.read!(@publisher) != add.(File.read!(@publisher))
    assert contracts(ns, add) == []
    assert policy(ns) == :compiled
  end

  test "control: a field of an event nobody consumes touches neither side" do
    ns = namespace("Unconsumed")
    rename = rename_on("assigned", "picker_id", "assignee_id")
    assert rename.(File.read!(@publisher)) =~ "field :assignee_id, :id"

    assert contracts(ns, rename) == []
    assert policy(ns) == :compiled
  end
end

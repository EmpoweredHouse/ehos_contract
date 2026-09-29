defmodule EhOsContract.DocsTest do
  @moduledoc """
  v2 plan, E11d: **the package's documentation is held to the code it describes.**

  The reference of both DSLs is generated (`mix eh_os_contract.docs --check`), so what
  is left by hand is prose and its examples. This file keeps the two from drifting
  apart:

    * every example that defines a module compiles, with the modules the same page
      defines before it, and passes the rules between modules (L3) — a page is read
      top to bottom, and so is it compiled;
    * the table of refusals in `docs/contract.md` names exactly the codes the
      library refuses with, each of which a test in `test/dsl/` asserts;
    * every section, entity, argument and option of both DSLs says what it is, since
      the generated reference prints nothing else;
    * every relative link between the pages leads to a page.
  """

  use EhOsContract.DslCase, async: false

  @pages ["README.md", "docs/contract.md", "docs/authorization.md"]

  defp read(path), do: File.read!(path)

  # The ```elixir blocks of a page, in order.
  defp blocks(page) do
    ~r/^```elixir\n(.*?)^```/msu
    |> Regex.scan(read(page), capture: :all_but_first)
    |> List.flatten()
  end

  for page <- @pages do
    test "the examples of #{page} compile and pass the rules between modules" do
      source = unquote(page) |> blocks() |> Enum.filter(&(&1 =~ ~r/^defmodule /mu)) |> Enum.join()

      if source == "" do
        flunk("#{unquote(page)} has no example defining a module")
      end

      # An example may call the host's own code, which does not exist here, so a
      # warning is not a failure; an error is, and it is shown with the test's.
      {result, diagnostics} =
        Code.with_diagnostics(fn ->
          try do
            {:ok, links([{unquote(page), source}])}
          rescue
            error -> {:error, error}
          end
        end)

      case result do
        {:ok, violations} ->
          assert violations == []

        {:error, error} ->
          errors =
            for %{severity: :error} = d <- diagnostics,
                do: "  #{d.file}:#{inspect(d.position)} #{d.message}"

          flunk(
            "#{unquote(page)} does not compile: #{Exception.message(error)}\n" <>
              Enum.join(errors, "\n")
          )
      end
    end
  end

  # The codes the library refuses with: every message that starts with one.
  defp codes_in_lib do
    for path <- Path.wildcard("lib/**/*.ex"),
        [code] <- Regex.scan(~r/"([A-Z][0-9]+): /u, read(path), capture: :all_but_first),
        into: MapSet.new(),
        do: code
  end

  defp codes_in_table do
    for [code] <-
          Regex.scan(~r/^\| `([A-Z][0-9]+)` \|/mu, read("docs/contract.md"),
            capture: :all_but_first
          ),
        into: MapSet.new(),
        do: code
  end

  test "the table of refusals names exactly the codes the library refuses with" do
    in_lib = codes_in_lib()
    in_table = codes_in_table()

    assert MapSet.size(in_lib) > 50

    assert MapSet.difference(in_lib, in_table) |> Enum.sort() == [],
           "codes missing from the table"

    assert MapSet.difference(in_table, in_lib) |> Enum.sort() == [],
           "codes the library never uses"
  end

  test "every code in the table has a test in test/dsl that asserts it" do
    tests = "test/dsl/**/*_test.exs" |> Path.wildcard() |> Enum.map_join("\n", &read/1)

    untested = for code <- codes_in_table(), not (tests =~ "#{code}: "), do: code

    assert Enum.sort(untested) == []
  end

  # Every section and entity of an extension, with where it sits.
  defp declarations(extension) do
    Enum.flat_map(extension.sections(), &section([], &1))
  end

  defp section(path, %Spark.Dsl.Section{} = section) do
    path = path ++ [section.name]

    [{path, section.describe, section.schema}] ++
      Enum.flat_map(section.entities, &entity(path, &1)) ++
      Enum.flat_map(section.sections, &section(path, &1))
  end

  defp entity(path, %Spark.Dsl.Entity{} = entity) do
    path = path ++ [entity.name]

    [{path, entity.describe, entity.schema}] ++
      Enum.flat_map(entity.entities, fn {_key, entities} ->
        Enum.flat_map(List.wrap(entities), &entity(path, &1))
      end)
  end

  defp blank?(text), do: not is_binary(text) or String.trim(text) == ""

  for extension <- [EhOsContract.Domain.Dsl, EhOsContract.Contract.Dsl] do
    test "every declaration and key of #{inspect(extension)} has a description" do
      undescribed =
        for {path, describe, schema} <- declarations(unquote(extension)),
            missing <- [path | for({key, opts} <- schema, blank?(opts[:doc]), do: path ++ [key])],
            missing != path or blank?(describe),
            do: Enum.join(missing, ".")

      assert undescribed == []
    end
  end

  test "every relative link between the pages leads to a page" do
    pages = @pages ++ ["docs/rules.md"]

    broken =
      for page <- pages,
          [target] <-
            Regex.scan(~r/\]\(([^)#:]+\.md)[^)]*\)/u, read(page), capture: :all_but_first),
          path = Path.expand(target, Path.dirname(page)),
          not File.exists?(path),
          do: "#{page} → #{target}"

    assert broken == []
  end
end

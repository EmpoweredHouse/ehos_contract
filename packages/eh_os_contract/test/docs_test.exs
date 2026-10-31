defmodule EhOsContract.DocsTest do
  @moduledoc """
  v2 plan, E11d: **the package's documentation is held to the code it describes.**

  The reference of both DSLs is generated (`mix eh_os_contract.docs --check`), so what
  is left by hand is prose and its examples. This file keeps the two from drifting
  apart:

    * every example that defines a module compiles, with the modules the same page
      defines before it, and passes the rules between modules — a page is read
      top to bottom, and so is it compiled;
    * every example that defines no module, a snippet, compiles in the module of its
      page that the comment above it names, or the comment says why it is not, and it
      then parses and names only what the library has;
    * the table of refusals in `docs/refusals.md` names exactly the codes the
      library refuses with, and the layer that refuses each, each code asserted by
      a test in `test/dsl/`;
    * every section, entity, argument and option of both DSLs says what it is, since
      the generated reference prints nothing else;
    * every relative link between the pages leads to a page, and every anchor it
      names is there; no two pages share the basename ExDoc names a page after;
    * a refusal code in a prose page links to its family's table, and each family
      has one;
    * every page ExDoc builds is generated or prose, and every such page is built;
    * every top-level entity and rule is covered by some prose page.

  `MAINTAINING-DOCS.md` says what each failure asks of whoever changes the library.
  """

  use EhOsContract.DslCase, async: false

  @pages EhOsContract.Docs.prose()

  defp read(path), do: File.read!(path)

  # The `elixir` blocks of a page, in order, as `%{line:, code:, marker:}`: the line of
  # the opening fence, the code without the fence's indent, and the comment on the line
  # above the fence.
  defp elixir_blocks(page) do
    {blocks, nil, _above} =
      page
      |> read()
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.reduce({[], nil, ""}, fn
        {line, number}, {blocks, nil, above} ->
          case Regex.run(~r/^(\s*)```elixir\s*$/u, line) do
            [_, indent] ->
              {blocks, %{line: number, indent: indent, code: [], marker: marker(above)}, line}

            nil ->
              {blocks, nil, line}
          end

        {line, _number}, {blocks, block, _above} ->
          if String.trim(line) == "```" do
            code = block.code |> Enum.reverse() |> Enum.join("\n")
            {[%{block | code: code} | blocks], nil, line}
          else
            {blocks,
             %{block | code: [String.replace_prefix(line, block.indent, "") | block.code]}, line}
          end
      end)

    Enum.reverse(blocks)
  end

  defp marker(line) do
    case Regex.run(~r/^\s*<!--\s*(in|and in|not compiled):\s*(.*?)\s*-->\s*$/u, line) do
      [_, "in", target] -> {:in, target}
      [_, "and in", target] -> {:and_in, target}
      [_, "not compiled", why] -> {:not_compiled, why}
      nil -> nil
    end
  end

  defp module_block?(block), do: block.code =~ ~r/^defmodule /mu

  defp where(page, block), do: "#{page}:#{block.line}"

  # A block's code, quoted with the lines it has on its page.
  defp parse(page, block),
    do: Code.string_to_quoted(block.code, file: page, line: block.line + 1)

  defp modules(page) do
    for block <- elixir_blocks(page), module_block?(block) do
      {:ok, quoted} = parse(page, block)
      quoted
    end
  end

  # Compiles `modules` as the page `page` and runs the rules between modules: what
  # fails, as lines. An example may call the host's own code, which does not exist
  # here, so a warning is not a failure; an error is, and it is shown.
  defp compile_problems(page, modules) do
    {result, diagnostics} =
      Code.with_diagnostics(fn ->
        try do
          {:ok, links([{page, {:__block__, [], modules}}])}
        rescue
          error -> {:error, error}
        end
      end)

    case result do
      {:ok, violations} ->
        for v <- violations, do: "#{v.file}:#{v.line}: #{v.message}"

      {:error, error} ->
        errors =
          for %{severity: :error} = d <- diagnostics,
              do: "#{d.file}:#{inspect(d.position)}: #{d.message}"

        ["does not compile: #{Exception.message(error)}" | errors]
    end
  end

  for page <- @pages do
    test "the examples of #{page} compile and pass the rules between modules" do
      modules = modules(unquote(page))

      if modules == [] do
        flunk("#{unquote(page)} has no example defining a module")
      end

      problems = compile_problems(unquote(page), modules)
      assert problems == [], Enum.join(problems, "\n")
    end

    # A snippet is a block that defines no module. The comment on the line above it
    # says where it belongs, `<!-- in: Lending.Contracts.Loans -->` or
    # `<!-- in: Lending.Contracts.Loans, command :open_loan -->`, and it is compiled
    # there with the page; `<!-- and in: … -->` puts it in place together with the
    # snippet before it. Or the comment says why it is not compiled,
    # `<!-- not compiled: … -->`.
    test "the snippets of #{page} compile in the module they name" do
      page = unquote(page)
      modules = modules(page)

      problems =
        for [block | _] = group <- page |> elixir_blocks() |> groups(),
            problem <- snippet_problems(page, group, modules) do
          "#{where(page, block)}: #{problem}"
        end

      assert problems == [], Enum.join(problems, "\n\n")
    end
  end

  # The blocks of a page, each with the `and in:` snippets that follow it.
  defp groups(blocks) do
    Enum.chunk_while(
      blocks,
      [],
      fn
        %{marker: {:and_in, _}} = block, group -> {:cont, group ++ [block]}
        block, [] -> {:cont, [block]}
        block, group -> {:cont, group, [block]}
      end,
      fn
        [] -> {:cont, []}
        group -> {:cont, group, []}
      end
    )
  end

  defp snippet_problems(page, [block | others], modules) do
    stray? =
      match?({:and_in, _}, block.marker) or
        (others != [] and (module_block?(block) or not match?({:in, _}, block.marker)))

    case {module_block?(block), block.marker} do
      _stray when stray? ->
        ["an `and in:` snippet follows a block that is not marked `in:`"]

      {true, nil} ->
        []

      {true, _marker} ->
        ["a block that defines a module is compiled with its page, and takes no marker"]

      {false, nil} ->
        [
          "say on the line above the block where it belongs, `<!-- in: Module -->` or " <>
            "`<!-- in: Module, command :name -->`, or why it is not compiled, " <>
            "`<!-- not compiled: ... -->`"
        ]

      {false, {:not_compiled, _why}} ->
        unknown_calls(page, block)

      {false, {:in, _target}} ->
        result =
          Enum.reduce_while([block | others], {:ok, modules}, fn block, {:ok, modules} ->
            {_kind, target} = block.marker

            with {:ok, snippet} <- parse(page, block),
                 {:ok, modules} <- insert(modules, target, exprs(snippet)) do
              {:cont, {:ok, modules}}
            else
              error -> {:halt, error}
            end
          end)

        case result do
          {:ok, modules} -> compile_problems(page, modules)
          {:error, problem} when is_binary(problem) -> [problem]
          {:error, problem} -> ["does not parse: #{inspect(problem)}"]
        end
    end
  end

  # `modules` with the snippet put in the module `target` names, or in the declaration
  # of that module it names after a comma.
  defp insert(modules, target, snippet) do
    [module | declaration] = String.split(target, ",", parts: 2)
    module = Module.concat([String.trim(module)])
    declaration = for d <- declaration, do: d |> Code.string_to_quoted!() |> key()

    {modules, placed} =
      Enum.map_reduce(modules, 0, fn quoted, placed ->
        Macro.prewalk(quoted, placed, fn
          {:defmodule, _, [{:__aliases__, _, parts}, _]} = node, placed ->
            case Module.concat(parts) == module && place(node, declaration, snippet) do
              {:ok, node} -> {node, placed + 1}
              _not_here -> {node, placed}
            end

          node, placed ->
            {node, placed}
        end)
      end)

    if placed == 1,
      do: {:ok, modules},
      else: {:error, "the page has no one #{target}, with a do block, to put the snippet in"}
  end

  defp place(module, [], snippet) do
    if body = with_body(module, &merge(&1, snippet)), do: {:ok, body}, else: :error
  end

  defp place(module, [key], snippet) do
    {module, found} =
      Macro.prewalk(module, 0, fn node, found ->
        with true <- key(node) == key, {_, _, _} = node <- with_body(node, &merge(&1, snippet)) do
          {node, found + 1}
        else
          _other -> {node, found}
        end
      end)

    if found == 1, do: {:ok, module}, else: :error
  end

  defp with_body({kind, meta, args}, fun) when is_list(args) and args != [] do
    case List.last(args) do
      [{:do, body} | rest] -> {kind, meta, List.replace_at(args, -1, [{:do, fun.(body)} | rest])}
      _other -> nil
    end
  end

  defp with_body(_node, _fun), do: nil

  # The snippet's declarations take the place of the body's declarations of the same
  # key, at the first of them, or go to the end of the body.
  defp merge(body, snippet) do
    keys = for expr <- snippet, key = key(expr), do: key
    body = exprs(body)
    {before, rest} = Enum.split_while(body, &(key(&1) not in keys))
    {:__block__, [], before ++ snippet ++ Enum.reject(rest, &(key(&1) in keys))}
  end

  defp exprs({:__block__, _, exprs}), do: exprs
  defp exprs(expr), do: [expr]

  # What tells a declaration from its siblings: its kind and its name. A function is
  # named by its name alone, so a snippet's clauses take the place of all of the
  # body's; a declaration with no name, as `state do … end`, by its kind.
  defp key({kind, _, [{:when, _, [{name, _, _} | _]} | _]}) when kind in [:def, :defp],
    do: {kind, name}

  defp key({kind, _, [{name, _, _} | _]}) when kind in [:def, :defp], do: {kind, name}
  defp key({kind, _, [[{:do, _} | _]]}) when is_atom(kind), do: {kind, nil}

  defp key({kind, _, [name | _]})
       when is_atom(kind) and kind not in [:@, :__aliases__, :., :%{}, :{}],
       do: {kind, Macro.prewalk(name, &Macro.update_meta(&1, fn _ -> [] end))}

  defp key(_expr), do: nil

  @typespecs [:type, :typep, :opaque, :spec, :callback, :macrocallback]

  # A snippet that is not compiled is still read: it parses, and each module of the
  # library it names is there, with each function, macro or type it calls.
  defp unknown_calls(page, block) do
    # A line of a keyword list, as `compilers: …` of a `mix.exs`, parses inside one.
    parsed =
      with {:error, _} = error <- parse(page, block),
           {:error, _} <- parse(page, %{block | code: "[#{block.code}]"}),
           do: error

    case parsed do
      {:ok, quoted} ->
        {_quoted, unknown} = Macro.prewalk(quoted, [], &unknown_call/2)
        for name <- unknown |> Enum.reverse() |> Enum.uniq(), do: "#{name} is not in the library"

      {:error, error} ->
        ["does not parse: #{inspect(error)}"]
    end
  end

  defp unknown_call({:@, _, [{attribute, _, [spec]}]}, unknown) when attribute in @typespecs do
    {_spec, unknown} = Macro.prewalk(spec, unknown, &unknown_type/2)
    {:read, unknown}
  end

  defp unknown_call(
         {{:., _, [{:__aliases__, _, [:EhOsContract | _] = parts}, name]}, _, args} = node,
         unknown
       ) do
    module = Module.concat(parts)
    arity = length(args)

    if Code.ensure_loaded?(module) and
         (function_exported?(module, name, arity) or macro_exported?(module, name, arity)),
       do: {node, unknown},
       else: {node, ["#{inspect(module)}.#{name}/#{arity}" | unknown]}
  end

  defp unknown_call({:__aliases__, _, [:EhOsContract | _] = parts} = node, unknown) do
    module = Module.concat(parts)
    if Code.ensure_loaded?(module), do: {node, unknown}, else: {node, [inspect(module) | unknown]}
  end

  defp unknown_call(node, unknown), do: {node, unknown}

  defp unknown_type(
         {{:., _, [{:__aliases__, _, [:EhOsContract | _] = parts}, name]}, _, args} = node,
         unknown
       ) do
    module = Module.concat(parts)

    known =
      case Code.Typespec.fetch_types(module) do
        {:ok, types} ->
          Enum.any?(types, fn {_kind, {type, _, params}} ->
            type == name and length(params) == length(args)
          end)

        :error ->
          false
      end

    if known,
      do: {node, unknown},
      else: {node, ["#{inspect(module)}.#{name}/#{length(args)} (a type)" | unknown]}
  end

  defp unknown_type(node, unknown), do: {node, unknown}

  # Where a code is refused decides its layer, by the name `docs/refusals.md` gives it:
  # the rules of one module, the rules between modules, the implementation macros.
  # Nothing else in `lib/` refuses a model, so a code mentioned anywhere else — a
  # docstring's example — does not count.
  @refusals "docs/refusals.md"

  @layers [
    {"lib/eh_os_contract/contract/rules.ex", "One module"},
    {"lib/eh_os_contract/contract/rules/*.ex", "One module"},
    {"lib/eh_os_contract/domain/rules.ex", "One module"},
    {"lib/eh_os_contract/process/rules.ex", "One module"},
    {"lib/eh_os_contract/contract/links.ex", "Between modules"},
    {"lib/eh_os_contract/contract/links/*.ex", "Between modules"},
    {"lib/eh_os_contract/implementation.ex", "Implementation"}
  ]

  # %{code => layers}, for every message that starts with a code.
  defp codes_in_lib do
    for {glob, layer} <- @layers,
        path <- Path.wildcard(glob),
        [code] <- Regex.scan(~r/"([A-Z]+[0-9]+): /u, read(path), capture: :all_but_first),
        reduce: %{} do
      codes -> Map.update(codes, code, MapSet.new([layer]), &MapSet.put(&1, layer))
    end
  end

  # %{code => layers}, from the table's first two columns.
  defp codes_in_table do
    for [code, layers] <-
          Regex.scan(~r/^\| `([A-Z]+[0-9]+)` \| ([^|]+) \|/mu, read(@refusals),
            capture: :all_but_first
          ),
        into: %{},
        do:
          {code,
           layers |> String.split(",", trim: true) |> Enum.map(&String.trim/1) |> MapSet.new()}
  end

  test "the table of refusals names exactly the codes the library refuses with, and where" do
    in_lib = codes_in_lib()
    in_table = codes_in_table()

    assert map_size(in_lib) > 50

    missing = Map.keys(in_lib) -- Map.keys(in_table)
    assert Enum.sort(missing) == [], "codes missing from the table"

    unused = Map.keys(in_table) -- Map.keys(in_lib)
    assert Enum.sort(unused) == [], "codes the library never refuses with"

    wrong =
      for {code, layers} <- in_lib,
          in_table[code] != layers,
          do: {code, table: Enum.sort(in_table[code]), lib: Enum.sort(layers)}

    assert Enum.sort(wrong) == [], "codes whose layer the table gets wrong"
  end

  test "every code in the table has a test in test/dsl that asserts it" do
    # Comment lines do not count: a test that mentions a code is not one that asserts it.
    tests =
      "test/dsl/**/*_test.exs"
      |> Path.wildcard()
      |> Enum.flat_map(&(&1 |> read() |> String.split("\n")))
      |> Enum.reject(&String.starts_with?(String.trim_leading(&1), "#"))
      |> Enum.join("\n")

    untested = for code <- Map.keys(codes_in_table()), not (tests =~ "#{code}: "), do: code

    assert Enum.sort(untested) == []
  end

  # A reader meets a code in prose and needs its row: each links to its family's table.
  # Examples, headings and the refusal rows themselves are left as they are; a code is
  # found with or without backticks, since `**X10**` reads as one too.
  test "a refusal code in a prose page links to its family in the table" do
    codes = codes_in_table()

    problems =
      for page <- @pages,
          line <- page |> read() |> EhOsContract.Docs.Prose.outside_fences(),
          not String.starts_with?(line, "#"),
          not Regex.match?(~r/^\| `[A-Z]+[0-9]+` \|/u, line),
          problem <- code_problems(line, codes),
          do: "#{page}: #{problem}"

    assert problems == []
  end

  # A link whose text is a code goes to that code's family, in refusals.md; any other
  # mention of a code, a link's text taken out, is bare.
  defp code_problems(line, codes) do
    links =
      for [code, family, target] <-
            Regex.scan(~r/\[`?(([A-Z]+)[0-9]+)`?\]\(([^)]*)\)/u, line, capture: :all_but_first),
          Map.has_key?(codes, code) or target =~ "#refusals-",
          not Map.has_key?(codes, code) or
            not Regex.match?(~r/refusals\.md#refusals-#{String.downcase(family)}\z/u, target),
          do: "#{code} links to #{target}"

    bare =
      for [code] <-
            Regex.scan(~r/\b([A-Z]+[0-9]+)\b/u, Regex.replace(~r/\[[^\]]*\]\([^)]*\)/u, line, ""),
              capture: :all_but_first
            ),
          Map.has_key?(codes, code),
          do: "#{code} is not a link"

    links ++ bare
  end

  test "every family of refusal codes has its table's anchor" do
    families = codes_in_table() |> Map.keys() |> Enum.map(&String.replace(&1, ~r/[0-9]+/u, ""))

    missing =
      for family <- Enum.uniq(families),
          not (read(@refusals) =~ ~s(<a id="refusals-#{String.downcase(family)}"></a>)),
          do: family

    assert missing == []
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

  for extension <- [EhOsContract.Domain.Dsl, EhOsContract.Contract.Dsl, EhOsContract.Process.Dsl] do
    test "every declaration and key of #{inspect(extension)} has a description" do
      undescribed =
        for {path, describe, schema} <- declarations(unquote(extension)),
            missing <- [path | for({key, opts} <- schema, blank?(opts[:doc]), do: path ++ [key])],
            missing != path or blank?(describe),
            do: Enum.join(missing, ".")

      assert undescribed == []
    end
  end

  # The pages ExDoc builds, as `mix.exs` lists them.
  defp extras, do: Mix.Project.config()[:docs][:extras]

  # The id ExDoc gives an extra's page (`ExDoc.Utils.text_to_id/1` on its basename):
  # two pages of one id are numbered in the order they are listed, so a link to
  # either stops being stable.
  defp page_id(path) do
    path
    |> Path.basename()
    |> Path.rootname()
    |> String.downcase()
    |> String.replace(~r/\W+/u, "-")
    |> String.trim("-")
  end

  test "every page of the documentation exists, and no two share the id ExDoc names it by" do
    assert Enum.reject(extras(), &File.exists?/1) == []

    ids = Enum.map(extras(), &page_id/1)
    assert ids -- Enum.uniq(ids) == []
  end

  test "every relative link between the pages leads to a page" do
    pages = extras()

    broken =
      for page <- pages,
          [target] <-
            Regex.scan(~r/\]\(([^)#:]+\.md)[^)]*\)/u, read(page), capture: :all_but_first),
          path = Path.expand(target, Path.dirname(page)),
          not File.exists?(path),
          do: "#{page} → #{target}"

    assert broken == []
  end

  test "every anchor a page links to is on its page" do
    broken =
      for page <- extras(),
          [file, anchor] <-
            Regex.scan(~r/\]\(([^)#:]*)#([^)]+)\)/u, read(page), capture: :all_but_first),
          target = if(file == "", do: page, else: Path.expand(file, Path.dirname(page))),
          not (File.exists?(target) and read(target) =~ ~s(id="#{anchor}")),
          do: "#{page} → #{file}##{anchor}"

    assert broken == []
  end

  # `EhOsContract.DslWrappers` widens an optional argument with a keyword list no
  # declaration may pass; the reference shows the type as declared.
  test "an optional argument's type is shown as declared, not as the wrappers widen it" do
    widened =
      for {page, key} <- [{"contract-consumes", "events"}, {"domain-value", "type"}],
          [row] <- Regex.scan(~r/^\| `#{key}` \|.*$/mu, read("docs/dsl/#{page}.md")),
          row =~ "keyword",
          do: row

    assert widened == []
  end

  # A link to an entity of the old single page needs only its file changed.
  test "the page of a DSL entity carries the entity's anchor" do
    missing =
      for page <- Path.wildcard("docs/dsl/*-*.md"),
          not String.ends_with?(page, "-dsl.md"),
          id = Path.basename(page, ".md"),
          not (read(page) =~ ~s(<a id="#{id}"></a>)),
          do: page

    assert missing == []
  end

  # A page about something renamed or removed is found the day it happens (#141).
  test "what a prose page says it covers exists" do
    names = EhOsContract.Docs.Prose.names()

    unknown =
      for page <- EhOsContract.Docs.prose(),
          name <- EhOsContract.Docs.Prose.unknown(read(page), names),
          do: "#{page}: #{name}"

    assert unknown == []
  end

  # Otherwise a new hand-written page would be held to nothing.
  test "every page ExDoc builds is generated, prose, or the changelog" do
    generated = Enum.map(EhOsContract.Docs.generated(), &elem(&1, 0))
    # `docs/rules.md` is the rules task's, `mix eh_os_contract.rules`; `docs/refusals.md`
    # is held to the code by the tests of its table above.
    known =
      generated ++
        EhOsContract.Docs.prose() ++ ["docs/refusals.md", "docs/rules.md", "CHANGELOG.md"]

    assert extras() -- known == []
    # And the other way: a page the manifest lists but `mix.exs` leaves out is never built.
    assert known -- extras() == []
  end

  # A new top-level entity or rule needs a page that explains it, beside its reference
  # row: name it in a page's `<!-- covers: -->`, or write the page.
  test "every top-level entity and every rule is covered by a prose page" do
    assert EhOsContract.Docs.Prose.uncovered(Enum.map(@pages, &read/1)) == []
  end
end

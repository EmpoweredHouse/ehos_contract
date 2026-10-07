defmodule EhOsContract.Docs.Prose do
  @moduledoc """
  Prose pages held to the code (#141): what a page says it covers, checked against
  what exists, and regions of a page that a generator fills.

  **What a page covers** is an HTML comment, invisible in every renderer, anywhere in
  the page and as often as needed:

      <!-- covers: entities contract.policy, contract.aggregate; keys contract.policy.delivery; rules in-transaction-across-contexts -->

  An entity is named by its path in its DSL (`domain.value`, `contract.aggregate.command`,
  `process.promise`), a key by its entity's path and its name, a rule by its id in
  `docs/rules.md`. A name that no longer exists fails `test/docs_test.exs`, so a page
  about something renamed or removed is found the day it happens.

  **A generated region** is a pair of comments, each on a line of its own, with what
  the generator writes between them:

      <!-- generated: dsl-keys contract.policy -->
      ...
      <!-- /generated -->

  `dsl-keys <entity>` is the entity's tables of arguments and options, as its
  reference page prints them; `config` is the configuration's keys. `mix
  eh_os_contract.docs` rewrites every region, and `--check` fails on one that
  differs from the code. A page keeps its prose and borrows the facts.

  Both are read outside fenced code blocks only, so a page may show the syntax in a
  code block, as this one does. A comment that looks like either but cannot be read
  (`<!-- Covers: -->`, an opener sharing its line with text, a closer with no opener)
  is refused rather than ignored: a page whose region is never filled would pass
  `--check` while showing stale facts, and a region read to the wrong closer would
  replace the prose between them.
  """

  alias EhOsContract.Docs.DslPages

  @typedoc "What a page says it covers."
  @type covers() :: %{entities: [String.t()], keys: [String.t()], rules: [String.t()]}

  @doc "Every entity of the three DSLs, by its path: `{\"contract.policy\", entity}`."
  @spec entities() :: [{String.t(), Spark.Dsl.Entity.t()}]
  def entities do
    for extension <- EhOsContract.Docs.extensions(),
        {path, entity} <- DslPages.entities(extension),
        do: {Enum.join(path, "."), entity}
  end

  @doc "Every name a page may cover: the entities, keys and rules that exist."
  @spec names() :: covers()
  def names do
    entities = entities()

    %{
      entities: Enum.map(entities, &elem(&1, 0)),
      keys:
        for(
          {path, entity} <- entities,
          key <- DslPages.key_names(entity),
          do: "#{path}.#{key}"
        ),
      rules: Enum.map(EhOsContract.Check.Catalog.rules(), & &1.id)
    }
  end

  @doc """
  What `markdown` says it covers, from every `<!-- covers: ... -->` outside its code
  blocks. Raises on a comment it cannot read, naming it.
  """
  @spec covers(String.t()) :: covers()
  def covers(markdown) do
    prose = markdown |> lines() |> Enum.reject(&elem(&1, 1)) |> Enum.map_join("\n", &elem(&1, 0))

    for [whole, word, body] <-
          Regex.scan(~r/<!--\s*(covers?)\s*:(.*?)-->/isu, prose),
        reduce: %{entities: [], keys: [], rules: []} do
      acc ->
        if word != "covers" do
          raise ArgumentError, "#{inspect(whole)} is written `<!-- covers: ... -->`"
        end

        body
        |> String.split(";", trim: true)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
        |> Enum.reduce(acc, &group/2)
    end
  end

  @kinds %{"entities" => :entities, "keys" => :keys, "rules" => :rules}

  defp group(group, acc) do
    with [kind, list] <- String.split(group, ~r/\s+/u, parts: 2),
         {:ok, key} <- Map.fetch(@kinds, kind) do
      names = list |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
      Map.update!(acc, key, &(&1 ++ names))
    else
      _other ->
        raise ArgumentError,
              "a covers comment has #{inspect(group)}; it takes `entities`, `keys` " <>
                "and `rules`, each followed by names separated by commas"
    end
  end

  @doc "The names `markdown` covers that do not exist, as `\"key contract.policy.x\"`."
  @spec unknown(String.t(), covers()) :: [String.t()]
  def unknown(markdown, names \\ names()) do
    covered = covers(markdown)

    for {kind, word} <- [entities: "entity", keys: "key", rules: "rule"],
        name <- Map.fetch!(covered, kind),
        name not in Map.fetch!(names, kind),
        do: "#{word} #{name}"
  end

  @doc """
  The top-level entities and the rules that no page of `markdowns` covers. An entity
  counts as covered when it, or anything nested in it, is named.
  """
  @spec uncovered([String.t()], covers()) :: [String.t()]
  def uncovered(markdowns, names \\ names()) do
    covered = Enum.map(markdowns, &covers/1)
    entities = Enum.flat_map(covered, & &1.entities) ++ Enum.flat_map(covered, & &1.keys)
    rules = Enum.flat_map(covered, & &1.rules)

    top =
      for name <- names.entities,
          match?([_dsl, _entity], String.split(name, ".")),
          not Enum.any?(entities, &(&1 == name or String.starts_with?(&1, name <> "."))),
          do: "entity #{name}"

    top ++ for(rule <- names.rules, rule not in rules, do: "rule #{rule}")
  end

  @doc """
  `markdown` with every generated region rewritten from the code, everything else
  kept as it was. Raises, naming the line, on a region it does not know, an opener
  or closer that does not stand on a line of its own, and a region left open or
  closed twice.
  """
  @spec fill(String.t()) :: String.t()
  def fill(markdown) do
    entities = Map.new(entities())

    {out, open} =
      markdown
      |> lines()
      |> Enum.with_index(1)
      |> Enum.reduce({[], nil}, fn {{line, in_code?}, number}, {out, open} ->
        step(line, in_code?, number, out, open, entities)
      end)

    if open, do: raise(ArgumentError, "the generated region at line #{open} is not closed")

    out |> Enum.reverse() |> Enum.join()
  end

  @opener ~r/\A\s*<!--\s*generated:\s*(.+?)\s*-->\s*\z/u
  @closer ~r/\A\s*<!--\s*\/generated\s*-->\s*\z/u

  # A region's own lines are dropped and written again when it closes.
  defp step(line, true, _number, out, nil, _entities), do: {[line | out], nil}

  defp step(line, _in_code?, number, out, open, entities) do
    text = String.trim_trailing(line, "\n")

    cond do
      open == nil and Regex.match?(@opener, text) ->
        [_, what] = Regex.run(@opener, text)
        {[region(what, entities, number) <> "\n\n", newline(line), line | out], number}

      open != nil and Regex.match?(@closer, text) ->
        {[line | out], nil}

      Regex.match?(~r/<!--\s*\/?generated\b/u, text) ->
        raise ArgumentError,
              "line #{number}: a generated region's opener and closer each stand on a line " <>
                "of their own, in order; got #{inspect(String.trim(text))}"

      open != nil ->
        {out, open}

      true ->
        {[line | out], nil}
    end
  end

  defp newline(line), do: if(String.ends_with?(line, "\r\n"), do: "\r\n", else: "\n")

  defp region("config", _entities, _number), do: String.trim(EhOsContract.Config.docs())

  defp region("dsl-keys " <> path, entities, number) do
    case Map.fetch(entities, String.trim(path)) do
      {:ok, entity} ->
        DslPages.keys_table(entity)

      :error ->
        raise ArgumentError,
              "line #{number}: a generated region names the entity #{path}, which no DSL has"
    end
  end

  defp region(other, _entities, number) do
    raise ArgumentError,
          "line #{number}: a generated region asks for #{inspect(other)}; it takes " <>
            "`dsl-keys <entity>` or `config`"
  end

  # Each line with its newline, and whether it is inside a fenced code block (the
  # fences themselves count as inside).
  # As CommonMark reads a fence: it opens with three or more backticks or tildes,
  # indented at most three spaces, and closes only on a line of the same character,
  # at least as long, with nothing after it but spaces. So a block of four backticks
  # can show a block of three, and `~~~` inside backticks closes nothing.
  defp lines(markdown) do
    markdown
    |> String.split(~r/(?<=\n)/u)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map_reduce(nil, fn line, open ->
      case {open, Regex.run(~r/\A {0,3}(`{3,}|~{3,})(.*?)\r?\n?\z/su, line)} do
        {nil, [_, fence, _info]} ->
          {{line, true}, fence}

        {nil, nil} ->
          {{line, false}, nil}

        {open, [_, fence, rest]} ->
          closes? =
            String.first(fence) == String.first(open) and
              String.length(fence) >= String.length(open) and String.trim(rest) == ""

          {{line, true}, if(closes?, do: nil, else: open)}

        {open, nil} ->
          {{line, true}, open}
      end
    end)
    |> elem(0)
  end
end

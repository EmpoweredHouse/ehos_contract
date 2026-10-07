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

  **A generated region** is a pair of comments with what the generator writes between
  them:

      <!-- generated: dsl-keys contract.policy -->
      ...
      <!-- /generated -->

  `dsl-keys <entity>` is the entity's tables of arguments and options, as its
  reference page prints them; `config` is the configuration's keys. `mix
  eh_os_contract.docs` rewrites every region, and `--check` fails on one that
  differs from the code. A page keeps its prose and borrows the facts.
  """

  alias EhOsContract.Docs.DslPages

  @extensions [EhOsContract.Domain.Dsl, EhOsContract.Contract.Dsl, EhOsContract.Process.Dsl]

  @typedoc "What a page says it covers."
  @type covers() :: %{entities: [String.t()], keys: [String.t()], rules: [String.t()]}

  @doc "Every name a page may cover: the entities, keys and rules that exist."
  @spec names() :: covers()
  def names do
    entities = for extension <- @extensions, pair <- DslPages.entities(extension), do: pair

    %{
      entities: for({path, _entity} <- entities, do: Enum.join(path, ".")),
      keys:
        for(
          {path, entity} <- entities,
          key <- DslPages.key_names(entity),
          do: Enum.join(path ++ [to_string(key)], ".")
        ),
      rules: Enum.map(EhOsContract.Check.Catalog.rules(), & &1.id)
    }
  end

  @doc """
  What `markdown` says it covers, from every `<!-- covers: ... -->` in it. Raises on a
  comment it cannot read, naming the part.
  """
  @spec covers(String.t()) :: covers()
  def covers(markdown) do
    empty = %{entities: [], keys: [], rules: []}

    for [body] <- Regex.scan(~r/<!--\s*covers:(.*?)-->/su, markdown, capture: :all_but_first),
        group <- String.split(body, ";", trim: true),
        group = String.trim(group),
        group != "",
        reduce: empty do
      acc ->
        case String.split(group, ~r/\s+/u, parts: 2) do
          [kind, list] when kind in ["entities", "keys", "rules"] ->
            names = list |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
            Map.update!(acc, String.to_existing_atom(kind), &(&1 ++ names))

          _other ->
            raise ArgumentError,
                  "a covers comment has #{inspect(group)}; it takes `entities`, `keys` " <>
                    "and `rules`, each followed by names separated by commas"
        end
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
  `markdown` with every generated region rewritten from the code. Raises on a region
  it does not know, or one left open.
  """
  @spec fill(String.t()) :: String.t()
  def fill(markdown) do
    if Regex.scan(~r/<!--\s*generated:/u, markdown) |> length() !=
         Regex.scan(~r/<!--\s*\/generated\s*-->/u, markdown) |> length() do
      raise ArgumentError, "a generated region is not closed with <!-- /generated -->"
    end

    Regex.replace(
      ~r/(<!--\s*generated:\s*(.*?)\s*-->\n).*?(<!--\s*\/generated\s*-->)/su,
      markdown,
      fn _whole, open, what, close -> open <> "\n" <> region(what) <> "\n\n" <> close end
    )
  end

  defp region("config"), do: String.trim(EhOsContract.Config.docs())

  defp region("dsl-keys " <> path) do
    entities = for extension <- @extensions, pair <- DslPages.entities(extension), do: pair

    case Enum.find(entities, fn {here, _entity} -> Enum.join(here, ".") == path end) do
      {_path, entity} -> DslPages.keys_table(entity)
      nil -> raise ArgumentError, "a generated region names the entity #{path}, which no DSL has"
    end
  end

  defp region(other),
    do: raise(ArgumentError, "a generated region asks for #{inspect(other)}; it takes `dsl-keys <entity>` or `config`")
end

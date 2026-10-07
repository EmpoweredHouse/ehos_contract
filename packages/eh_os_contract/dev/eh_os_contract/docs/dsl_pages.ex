defmodule EhOsContract.Docs.DslPages do
  @moduledoc """
  The reference of a DSL as Markdown pages: an index of the DSL, and a page for each
  top-level entity with every entity nested in it (#141).

  Written from the Spark extension rather than taken from `Spark.CheatSheet`, whose
  output is for ExDoc only: its anchors are Earmark attributes (`{: #id}`) and it ends
  with a `<style>` block, both of which other renderers print as text. Here an anchor
  is an `<a id>` and a required key says so in a column.

  Every entity has an anchor, its path joined with `-` (`contract-aggregate-command`),
  as Spark's were, so a link written against the old single page needs only its file
  changed. The anchor is an `<a id>` on a line of its own: ExDoc prints one inside a
  table cell as text, so options have none.
  """

  @doc """
  The pages of `extension`, as `{path, markdown}`: `index` for the index and one per
  top-level entity beside it, `<prefix>-<entity>.md`.
  """
  @spec pages(module(), String.t(), String.t()) :: [{String.t(), String.t()}]
  def pages(extension, index, prefix) do
    section = only_section!(extension)
    dir = Path.dirname(index)
    entities = Enum.map(section.entities, &{&1, Path.join(dir, "#{prefix}-#{&1.name}.md")})

    [{index, index_page(extension, section, entities)}] ++
      for {entity, path} <- entities,
          do: {path, entity_page(extension, section, entity, Path.basename(index))}
  end

  defp index_page(extension, section, entities) do
    rows =
      Enum.map_join(entities, "\n", fn {entity, path} ->
        "| [`#{entity.name}`](#{Path.basename(path)}) | #{first_sentence(entity.describe)} |"
      end)

    """
    #{marker(extension)}

    # #{title(extension)}

    #{shift(moduledoc(extension))}

    ## #{section.name}

    #{shift(section.describe)}

    #{table("Options", section.schema || [])}

    | Entity | What it declares |
    |--------|------------------|
    #{rows}
    """
  end

  defp entity_page(extension, section, entity, index) do
    path = [section.name]

    """
    #{marker(extension)}

    <a id="#{anchor(path ++ [entity.name])}"></a>

    # #{entity.name}

    In [#{title(extension)}](#{index}), section `#{section.name}`.

    #{entity_body(entity, path)}
    #{Enum.map_join(nested(entity), "\n", &nested_block(&1, path ++ [entity.name]))}\
    """
  end

  defp nested_block(entity, path) do
    """
    <a id="#{anchor(path ++ [entity.name])}"></a>

    ## #{Enum.join(tl(path) ++ [entity.name], ".")}

    #{entity_body(entity, path)}
    #{Enum.map_join(nested(entity), "\n", &nested_block(&1, path ++ [entity.name]))}\
    """
  end

  defp entity_body(entity, path) do
    path = path ++ [entity.name]
    args = arg_keys(entity)

    options =
      entity.schema
      |> Keyword.drop(List.wrap(entity.hide) ++ Keyword.keys(entity.auto_set_fields))
      |> Enum.reject(fn {_key, opts} -> opts[:hide] end)

    {positional, named} = Enum.split_with(options, fn {key, _} -> key in args end)
    positional = Enum.sort_by(positional, fn {key, _} -> Enum.find_index(args, &(&1 == key)) end)
    named = Enum.sort_by(named, fn {_key, opts} -> !opts[:required] end)

    children =
      case nested(entity) do
        [] ->
          ""

        list ->
          "Inside it: " <>
            Enum.map_join(list, ", ", &"[`#{&1.name}`](##{anchor(path ++ [&1.name])})") <> "."
      end

    [
      "```elixir\n#{entity.name}#{signature(entity)}\n```",
      shift(entity.describe),
      table("Arguments", positional),
      table("Options", named),
      children
    ]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
    |> Kernel.<>("\n")
  end

  defp table(_header, []), do: ""

  defp table(header, options) do
    rows =
      Enum.map_join(options, "\n", fn {key, opts} ->
        required = if opts[:required] && is_nil(opts[:default]), do: "yes", else: ""
        default = if is_nil(opts[:default]), do: "", else: "`#{cell(inspect(opts[:default]))}`"

        "| `#{key}` | " <>
          "`#{cell(Spark.Options.Docs.dsl_docs_type(opts[:type]))}` | #{required} | " <>
          "#{default} | #{cell(opts[:doc] || "")} |"
      end)

    """
    **#{header}**

    | Name | Type | Required | Default | Docs |
    |------|------|----------|---------|------|
    #{rows}\
    """
  end

  defp nested(entity), do: Enum.flat_map(List.wrap(entity.entities), &elem(&1, 1))

  defp signature(%{args: []}), do: ""

  defp signature(entity) do
    " " <>
      Enum.map_join(entity.args, ", ", fn
        {:optional, key} -> "#{key} \\\\ #{inspect(entity.schema[key][:default])}"
        {:optional, key, default} -> "#{key} \\\\ #{inspect(default)}"
        key -> to_string(key)
      end)
  end

  defp arg_keys(entity) do
    Enum.map(entity.args, fn
      {:optional, key} -> key
      {:optional, key, _default} -> key
      key -> key
    end)
  end

  defp anchor(path), do: Enum.join(path, "-")

  defp marker(extension), do: EhOsContract.Docs.marker(inspect(extension))

  # The reference renders one section of entities; anything else is refused rather
  # than left out of a page `--check` would then call current.
  defp only_section!(extension) do
    case extension.sections() do
      [%{sections: []} = section] ->
        section

      _other ->
        raise ArgumentError,
              "#{inspect(extension)} has more than one section, or a nested one, which " <>
                "EhOsContract.Docs.DslPages does not render"
    end
  end

  defp title(extension), do: extension |> inspect() |> String.replace_suffix(".Dsl", "")

  defp moduledoc(extension) do
    {:docs_v1, _, _, _, %{"en" => doc}, _, _} = Code.fetch_docs(extension)
    doc
  end

  # A description's own headings sit below the page's: `#` becomes `###`.
  defp shift(text) do
    text
    |> String.trim()
    |> String.split(~r/(```.*?```)/su, include_captures: true)
    |> Enum.map_join(fn
      "```" <> _ = code -> code
      prose -> Regex.replace(~r/^(#+)/mu, prose, "##\\1")
    end)
  end

  defp first_sentence(text) do
    text |> String.trim() |> String.split(~r/(?<=\.)\s/u, parts: 2) |> hd() |> cell()
  end

  defp cell(text) do
    text
    |> String.trim()
    |> String.replace("|", "\\|")
    |> String.replace(~r/\s*\n\s*/u, " ")
  end
end

defmodule EhOsContract.Glossary do
  # A domain's ubiquitous language as Markdown, one section per context (ESDM's
  # `glossary`; plan EL2). `mix eh_os_contract.glossary` prints it.
  #
  # A context's terms are written in its language: its own `language:`, or the
  # domain's. Asked for another language, a context written in it prints as it is,
  # and any other prints each term's translation into it — its text, its definition
  # and its own words to avoid — or says there is none. The
  # headings and the notes around the terms are the library's, in English; the terms,
  # definitions and words to avoid are the client's, printed as declared.
  #
  # Contexts and terms come in the order the domain declares them, as every reader of
  # the model prints (v2 §9).
  @moduledoc false

  @doc """
  The glossary of `domain`, a domain module or its model. `language:` asks for the
  terms in that language; `context:` keeps one context.
  """
  @spec render(module() | map(), keyword()) :: String.t()
  def render(domain, opts \\ []) do
    model = EhOsContract.Model.fetch(domain)
    wanted = opts[:language]

    contexts =
      case opts[:context] do
        nil -> model.contexts
        name -> Enum.filter(model.contexts, &(&1.name == name))
      end

    sections = Enum.map(contexts, &context(&1, model, wanted))
    Enum.join(["# Glossary of `#{model.name}`\n" | sections], "\n")
  end

  defp context(context, model, wanted) do
    language = context.language || model.language
    heading = "## #{context.label} (`#{context.name}`)\n"

    terms =
      case context.terms do
        [] ->
          ["_No terms._\n"]

        terms ->
          for term <- terms do
            if wanted in [nil, language],
              do: term(term, across(model, context.name, term.text)),
              else: translated(term, wanted, across(model, context.name, term.text))
          end
      end

    Enum.join([heading | terms], "\n")
  end

  defp term(term, across) do
    lines =
      ["### #{term.text}", "", term.definition] ++
        avoid(term.avoid) ++
        across ++ if(term.source, do: ["_Source: #{term.source}_"], else: [])

    Enum.join(lines, "\n") <> "\n"
  end

  @doc """
  Plan EP5b: what the other end of each relation that pairs the term `text` of
  context `name` calls it, one line each — the glossary's and a context page's.
  An external end is said to be one, since it has no glossary of its own.
  """
  @spec across(map(), atom(), String.t()) :: [String.t()]
  def across(model, name, text) do
    externals = MapSet.new(model.externals, & &1.name)

    for relation <- model.relations,
        [first_end, second_end] = EhOsContract.Domain.Build.sides(relation),
        [first, second] <- Map.get(relation, :terms, []),
        {own, word, other, other_word} <- [
          {first_end, first, second_end, second},
          {second_end, second, first_end, first}
        ],
        own == name and word == text do
      where = if MapSet.member?(externals, other), do: "external `#{other}`", else: "`#{other}`"
      ~s|_In #{where} (#{relation.type}): "#{other_word}"._|
    end
  end

  defp translated(term, language, across) do
    case Enum.find(term.translations, &(&1.language == language)) do
      # The relation's line follows a term with or without a translation, and its word
      # is the other end's as declared, in the client's language, as every pair is.
      nil ->
        Enum.join(["### #{term.text}", "", "_No translation into #{language}._" | across], "\n") <>
          "\n"

      translation ->
        lines =
          ["### #{translation.text}", "", translation.definition] ++
            avoid(translation.avoid) ++ [~s|_Translates "#{term.text}"._|] ++ across

        Enum.join(lines, "\n") <> "\n"
    end
  end

  # ESDM's form: the word, then why, when the domain says.
  defp avoid(words) do
    for word <- words do
      case word.reason do
        nil -> ~s|_Avoid the term "#{word.text}"._|
        reason -> ~s|_Avoid the term "#{word.text}"._ #{reason}|
      end
    end
  end
end

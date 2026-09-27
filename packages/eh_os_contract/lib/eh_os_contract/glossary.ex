defmodule EhOsContract.Glossary do
  @moduledoc """
  A domain's ubiquitous language as Markdown, one section per context (ESDM's
  `glossary`; plan EL2). `mix eh_os_contract.glossary` prints it.

  A context's terms are written in its language: its own `language:`, or the
  domain's. Asked for another language, a context written in it prints as it is,
  and any other prints each term's translation into it, or says there is none. The
  headings and the notes around the terms are the library's, in English; the terms,
  definitions and words to avoid are the client's, printed as declared.

  Contexts and terms come in the order the domain declares them, as every reader of
  the model prints (v2 §9).
  """

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

    sections = Enum.map(contexts, &context(&1, model.language, wanted))
    Enum.join(["# Glossary of `#{model.name}`\n" | sections], "\n")
  end

  defp context(context, domain_language, wanted) do
    language = context.language || domain_language
    heading = "## #{context.label} (`#{context.name}`)\n"

    terms =
      case context.terms do
        [] ->
          ["_No terms._\n"]

        terms ->
          for term <- terms do
            if wanted in [nil, language], do: term(term), else: translated(term, wanted)
          end
      end

    Enum.join([heading | terms], "\n")
  end

  defp term(term) do
    lines =
      ["### #{term.text}", "", term.definition] ++
        Enum.map(term.avoid, &~s|_Avoid the term "#{&1.text}"._|) ++
        if(term.source, do: ["_Source: #{term.source}_"], else: [])

    Enum.join(lines, "\n") <> "\n"
  end

  defp translated(term, language) do
    case Enum.find(term.translations, &(&1.language == language)) do
      nil ->
        "### #{term.text}\n\n_No translation into #{language}._\n"

      translation ->
        "### #{translation.text}\n\n_Translates #{inspect(term.text)}: #{term.definition}_\n"
    end
  end
end

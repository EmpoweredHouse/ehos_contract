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
  # Given the contracts, each term also says its word in code and the declarations of
  # its context's contracts named with it (plan DD, L1 (#269)): the names
  # `EhOsContract.CodeWords` reads, which the check's two rules about words read too.
  # Given the process modules as well (plan DD, P2e (#220)), it lists after them each
  # process module that includes events of the context's contracts and whose names say
  # the term: its id, its stages, its promises and the fields that tell its runs apart.
  # A process crosses contexts, so it is listed under the term of each context it takes
  # events from. The check's rules do not read a process module's names.
  #
  # Contexts and terms come in the order the domain declares them, as every reader of
  # the model prints (v2 §9).
  @moduledoc false

  @doc """
  The glossary of `domain`, a domain module or its model. `language:` asks for the
  terms in that language; `context:` keeps one context; `contracts:`, contract
  modules, adds each term's word in code and the declarations named with it;
  `processes:`, process modules, adds with them the process modules named with it.
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

    names =
      for module <- Keyword.get(opts, :contracts, []),
          %{model: %{domain: domain}} = c <- [EhOsContract.Contract.Links.contract(module)],
          domain == model.module,
          do: {c.model.context, c.module, EhOsContract.CodeWords.names(c)}

    processes =
      for module <- Keyword.get(opts, :processes, []),
          %{kind: :process, domain: domain} = process <- [EhOsContract.Model.fetch(module)],
          domain == model.module do
        contexts =
          process
          |> EhOsContract.Model.process_events()
          |> Enum.map(&EhOsContract.Model.fetch(&1.contract).context)
          |> Enum.uniq()

        {contexts, process.id, process_names(process)}
      end

    code =
      if Keyword.has_key?(opts, :contracts),
        do: %{contracts: names, processes: processes},
        else: nil

    sections = Enum.map(contexts, &context(&1, model, wanted, code))
    Enum.join(["# Glossary of `#{model.name}`\n" | sections], "\n")
  end

  defp context(context, model, wanted, code) do
    language = context.language || model.language
    heading = "## #{context.label} (`#{context.name}`)\n"

    terms =
      case context.terms do
        [] ->
          ["_No terms._\n"]

        terms ->
          for term <- terms do
            across =
              across(model, context.name, term.text) ++
                in_code(
                  term,
                  context.name,
                  language,
                  EhOsContract.CodeWords.code_language(model),
                  code
                )

            if wanted in [nil, language],
              do: term(term, across),
              else: translated(term, wanted, across)
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

  # The term's word in code and, per contract of its context, the declarations whose
  # names say it; a field is named once, with how many declarations carry it.
  defp in_code(_term, _context, _language, _code_language, nil), do: []

  defp in_code(term, context, language, code_language, code) do
    text = EhOsContract.CodeWords.in_code(term, language, code_language)

    case EhOsContract.CodeWords.words(text || "") do
      # No translation, or one with no letter or digit, which no name could say.
      [] ->
        ["_No word in code: no translation into #{code_language}._"]

      sequence ->
        word = Enum.join(sequence, "_")

        named =
          for {^context, module, names} <- code.contracts,
              names = Enum.filter(names, &EhOsContract.CodeWords.contains?(&1.words, sequence)),
              names != [] do
            "- `#{inspect(module)}`: " <> declarations(names)
          end

        named =
          named ++
            for {contexts, id, names} <- code.processes,
                context in contexts,
                names = Enum.filter(names, &EhOsContract.CodeWords.contains?(&1.words, sequence)),
                names != [] do
              "- process `#{id}`: " <>
                (names |> Enum.map(& &1.what) |> Enum.uniq() |> Enum.join(", "))
            end

        case named do
          [] -> ["_In code: `#{word}`, in no declaration._"]
          named -> ["_In code: `#{word}`._" | named]
        end
    end
  end

  # A process module's names: each segment of its id after the domain's name, its
  # stages, its promises and the fields that tell its runs apart. A segment is a name of
  # its own: a term's words do not run across the dot.
  defp process_names(process) do
    [_namespace | rest] = String.split(process.id, ".")

    for(segment <- rest, do: %{what: "its id", words: EhOsContract.CodeWords.words(segment)}) ++
      for(s <- process.stages, do: name("stage", s.name)) ++
      for(p <- process.promises, do: name("promise", p.name)) ++
      for(f <- process.correlate, do: name("field", f))
  end

  defp name(kind, name),
    do: %{what: "#{kind} `#{inspect(name)}`", words: EhOsContract.CodeWords.words(name)}

  defp kind(%{kind: :unit, what: what}), do: what |> String.split(" ") |> hd()
  defp kind(%{kind: :read_model}), do: "read model"
  defp kind(%{kind: kind}), do: Atom.to_string(kind)

  defp declarations(names) do
    {fields, others} = Enum.split_with(names, &(&1.kind == :field))

    fields =
      fields
      |> Enum.frequencies_by(& &1.name)
      |> Enum.sort()
      |> Enum.map(fn
        {name, 1} -> "field `#{inspect(name)}`"
        {name, count} -> "field `#{inspect(name)}` (in #{count} declarations)"
      end)

    others = for n <- others, do: "#{kind(n)} `#{inspect(n.name)}`"
    Enum.join(Enum.uniq(others) ++ fields, ", ")
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

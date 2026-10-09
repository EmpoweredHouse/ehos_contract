defmodule EhOsContract.CodeWords do
  # The glossary joined to the code (plan DD, L1): which word of a term the code is
  # held to, and the names of a contract read as words.
  #
  # A term's word in code is its text in the domain's `code_language:`: the term
  # itself in a context written in that language, its translation into it otherwise,
  # and none when it has no such translation. A name is split into words at anything
  # that is not a letter or a digit, so `:visit_closed_at` is `visit`, `closed`, `at`,
  # and a term matches a name when its words stand in the name next to each other, in
  # order: "Settlement date" is in `:settlement_date_set`, not in `:date_of_settlement`.
  # Inflected forms are not matched, as `label-with-avoided-term` matches none.
  #
  # The glossary's page and the two rules of `mix eh_os_contract.check` read the same
  # names, so the page lists what the rules judged.
  @moduledoc false

  alias EhOsContract.Contract.Links
  alias EhOsContract.Contract.Rules

  @typedoc """
  A name of a contract: what it names, the name, its words, where it was written, and
  whether it names a thing (`true`: a unit, a read model, a field) or an action (a
  command, an event).
  """
  @type name :: %{
          what: String.t(),
          name: atom(),
          words: [String.t()],
          at: term(),
          thing?: boolean()
        }

  @doc "The words of a name or a term, lowercase."
  @spec words(atom() | String.t()) :: [String.t()]
  def words(name) when is_atom(name), do: name |> Atom.to_string() |> words()

  def words(text) when is_binary(text),
    do: text |> String.downcase() |> String.split(~r/[^\p{L}\p{N}]+/u, trim: true)

  @doc """
  The terms of context `name` of the domain `model` that have a word in code, as
  `{term, words}`, in the order the glossary declares them.
  """
  @spec terms(map(), atom()) :: [{String.t(), [String.t()]}]
  def terms(model, name) do
    case Enum.find(model.contexts, &(&1.name == name)) do
      nil ->
        []

      context ->
        for term <- context.terms,
            text = in_code(term, context.language || model.language, model.code_language),
            words = words(text || ""),
            words != [],
            do: {term.text, words}
    end
  end

  @doc """
  The term's text in `code`, the domain's `code_language`, when the context is
  written in `own`: the term itself, its translation, or `nil`.
  """
  @spec in_code(map(), atom(), atom()) :: String.t() | nil
  def in_code(term, code, code), do: term.text

  def in_code(term, _own, code) do
    case Enum.find(term.translations, &(&1.language == code)) do
      nil -> nil
      translation -> translation.text
    end
  end

  @doc """
  Every name of `contract`, as `EhOsContract.Contract.Links.contract/1` reads it: its
  units, read models, commands and events, and the fields of their states, commands,
  events and rows. A unit's identity is the unit's own name and is left out, and so
  is a field that refers to an entity (`{:id, entity}`), which names what another
  declaration owns.
  """
  @spec names(map()) :: [name()]
  def names(%{declarations: d}) do
    units =
      for u <- d.units do
        name("#{u.kind} #{inspect(u.name)}", u.name, u, true)
      end

    read_models =
      for r <- d.read_models, do: name("read model #{inspect(r.name)}", r.name, r, true)

    actions =
      for u <- d.units,
          {what, declaration} <-
            Enum.map(u.commands, &{"command", &1}) ++ Enum.map(Rules.events(u), &{"event", &1}) do
        name("#{what} #{inspect(declaration.name)}", declaration.name, declaration, false)
      end

    fields =
      for {where, fields, _injected, kind} <- Rules.Fields.structs(d),
          kind == :state or kind == :command or kind == :row or match?({:event, _}, kind),
          field <- fields,
          not match?({:id, _}, field.type) do
        name("field #{inspect(field.name)} of #{where}", field.name, field, true)
      end

    units ++ read_models ++ actions ++ fields
  end

  defp name(what, name, declaration, thing?),
    do: %{what: what, name: name, words: words(name), at: Links.at(declaration), thing?: thing?}

  @doc """
  The positions of `words` that `sequence` covers, wherever it stands in them whole.
  """
  @spec covers([String.t()], [String.t()]) :: MapSet.t(non_neg_integer())
  def covers(words, sequence) do
    size = length(sequence)

    for start <- 0..(length(words) - size)//1,
        Enum.slice(words, start, size) == sequence,
        position <- start..(start + size - 1),
        into: MapSet.new(),
        do: position
  end

  @doc "Whether `sequence` stands whole in `words`."
  @spec contains?([String.t()], [String.t()]) :: boolean()
  def contains?(words, sequence), do: MapSet.size(covers(words, sequence)) > 0
end

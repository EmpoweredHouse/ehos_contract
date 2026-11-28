defmodule EhosContract.Contract.Rules.Consumes do
  # K1 of v2 §6: what a contract takes in from a sibling contract of the same
  # application, `consumes Contract, events`.
  #
  # A contract does not consume itself, and it names the events it consumes: a
  # rename, `as: [old: :new]`, renames one of them. It declares no fields for them:
  # a subscriber never declares a copy of a sibling's event, it reads the one the
  # sibling's contract declares (v2 §7). That a consumed alias does not
  # collide with a local name is N1's, since both share the callback namespace.
  #
  # Whether the sibling exists and has those events is the domain-wide view a Mix
  # compiler has (L3, X5), not this one: the sibling is named without a compile
  # dependency (v2 §8). Another application's published event is `subscribe`d to,
  # by name, and follows D11; `consumes` given a name is refused here, with the
  # declaration to write instead (plan N2).
  @moduledoc false

  alias EhosContract.Contract.Published
  alias EhosContract.Contract.Rules.Boundaries
  alias EhosContract.DslRules

  @doc false
  @spec check(map()) :: [DslRules.violation()]
  def check(declarations) do
    named =
      for %{from: from, via: :consumes} = consumes <- declarations.consumes, is_binary(from) do
        {"K1: consumes #{inspect(from)} names another application's published event, which is " <>
           "subscribed to: subscribe #{key(from)}, as: :name_here, with the fields it reads",
         consumes}
      end

    named ++
      for %{from: from} = consumes <- declarations.consumes,
          is_atom(from),
          violation <- violations(consumes, declarations.module) do
        violation
      end
  end

  defp violations(consumes, module) do
    where = "consumes #{inspect(consumes.from)}"

    itself =
      if consumes.from == module,
        do: [{"K1: a contract cannot consume its own events: #{where}", consumes}],
        else: []

    none =
      if consumes.events == [],
        do: [{"K1: #{where} names no events", consumes}],
        else: []

    renames =
      case consumes.as do
        nil ->
          []

        as when is_list(as) ->
          for {old, _new} <- as, old not in consumes.events do
            {"K1: #{where} renames #{inspect(old)}, which it does not consume", consumes}
          end

        as ->
          [
            {"K1: #{where} is given as: #{inspect(as)}; a sibling's events are renamed with " <>
               "as: [old: :new]", consumes}
          ]
      end

    fields =
      if consumes.fields == [],
        do: [],
        else: [
          {"K1: #{where} declares fields; a sibling's event is read in the shape its own contract " <>
             "declares (v2 §7), never copied", consumes}
        ]

    itself ++ none ++ renames ++ fields
  end

  # The key a subscriber writes for a name as it was written before #697.
  defp key(from) do
    case Boundaries.parts(from) do
      {namespace, publication, version} ->
        Published.key_source("#{namespace}.#{publication}.v#{version}")

      nil ->
        "{namespace, publication, version}"
    end
  end
end

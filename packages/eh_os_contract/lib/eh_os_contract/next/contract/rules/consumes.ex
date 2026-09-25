defmodule EhOsContract.Next.Contract.Rules.Consumes do
  @moduledoc """
  K1 of v2 §6: what a contract takes in from a sibling contract of the same
  application, `consumes Contract, events`.

  A contract does not consume itself, and it names the events it consumes: a
  rename, `as: [old: :new]`, renames one of them. That a consumed alias does not
  collide with a local name is N1's, since both share the callback namespace.

  Whether the sibling exists and has those events is the domain-wide view a Mix
  compiler has (L3, X5), not this one: the sibling is named without a compile
  dependency (v2 §8). The other form, another application's published event by
  name, follows D11 and has its own rules.
  """

  alias EhOsContract.DslRules

  @doc false
  @spec check(map()) :: [DslRules.violation()]
  def check(declarations) do
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

    itself ++ none ++ renames
  end
end

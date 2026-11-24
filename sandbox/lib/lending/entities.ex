defmodule Lending.Entities do
  @moduledoc """
  **Invented. A stand-in for the library's card system**, which keeps the membership
  cards outside the log: a loan reads whether the card shown is suspended. Any other
  card is not in the system, `:not_found`, and the loan is refused.
  """

  @behaviour EhosContract.Entities

  @cards %{
    "card-ada" => %{card_id: "card-ada", suspended: false},
    "card-bob" => %{card_id: "card-bob", suspended: true},
    "card-cy" => %{card_id: "card-cy", suspended: false},
    "card-dora" => %{card_id: "card-dora", suspended: false}
  }

  @impl true
  def fetch(_actor, Lending.Domain, :card, id) do
    case Map.fetch(@cards, id) do
      {:ok, card} -> {:ok, card}
      :error -> :not_found
    end
  end

  # An entity of the domain nobody wrote a clause for: said by name, rather than a
  # FunctionClauseError whose log would print the actor.
  def fetch(_actor, domain, entity, _id) do
    raise ArgumentError,
          "#{inspect(__MODULE__)} keeps no #{inspect(entity)} of #{inspect(domain)}: add it " <>
            "here, beside the cards"
  end
end

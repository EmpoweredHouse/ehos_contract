defmodule Lending.Entities do
  @moduledoc """
  **Invented. A stand-in for the library's card system**, which keeps the membership
  cards outside the log: a loan reads whether the card shown is suspended. Any other
  card is not in the system, `:not_found`, and the loan is refused.
  """

  @behaviour EhOsContract.Entities

  @cards %{
    "card-ada" => %{card_id: "card-ada", suspended: false},
    "card-bob" => %{card_id: "card-bob", suspended: true}
  }

  @impl true
  def fetch(_actor, Lending.Domain, :card, id) do
    case Map.fetch(@cards, id) do
      {:ok, card} -> {:ok, card}
      :error -> :not_found
    end
  end
end

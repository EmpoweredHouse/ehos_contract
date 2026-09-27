defmodule ShreddingRig.Greet do
  @moduledoc """
  **Invented.** Greets a new member, after the dispatch transaction. It fails on a
  name starting "Crash" with a `MatchError` holding the name, and answers
  `{:error, {:bounced, name}}` on one starting "Bounce": both exist only so that a
  test can watch what Oban keeps of a failure that carries personal data.
  """

  use ShreddingRig.Members, effect: :greet

  @impl true
  def joined(%Joined{name: "Crash" <> _ = name}), do: raise(MatchError, term: name)
  def joined(%Joined{name: "Bounce" <> _ = name}), do: {:error, {:bounced, name}}
  def joined(_joined), do: :ok
end

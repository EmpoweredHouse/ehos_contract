defmodule ShreddingRig.Greet do
  @moduledoc """
  **Invented.** Greets a new member, after the dispatch transaction. It fails on a
  name starting "Crash" with a `MatchError` holding the name, answers
  `{:error, {:bounced, name}}` on one starting "Bounce", exits or throws with the
  name on "Exit" and "Throw", and crashes a linked task holding it on "Link": all
  exist only so that a test can watch what Oban keeps of a failure that carries
  personal data.
  """

  use ShreddingRig.Members, effect: :greet

  @impl true
  def joined(%Joined{name: "Crash" <> _ = name}), do: raise(MatchError, term: name)
  def joined(%Joined{name: "Bounce" <> _ = name}), do: {:error, {:bounced, name}}
  def joined(%Joined{name: "Exit" <> _ = name}), do: exit({:deliver, name})
  def joined(%Joined{name: "Throw" <> _ = name}), do: throw({:deliver, name})

  def joined(%Joined{name: "Link" <> _ = name}) do
    Task.async(fn -> Map.fetch!(%{name: name}, :phone) end) |> Task.await()
  end

  def joined(_joined), do: :ok
end

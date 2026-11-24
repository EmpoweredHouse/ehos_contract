defmodule ShreddingRig.Rejoin do
  @moduledoc """
  **Invented.** On a rename to `"Rejoin Anna"`, joins `member-anna` to a membership
  of her own — which exists only so that a test can erase Anna first and watch the
  reaction's command be refused while the rename that set it off stands.
  """

  use ShreddingRig.Members, policy: :rejoin

  @impl true
  def renamed(%Renamed{name: "Rejoin Anna"}) do
    issue(%Join{
      membership_id: "membership-anna-rejoined",
      member_id: "member-anna",
      name: "Anna Nowak",
      contacts: [],
      plan: :basic
    })
  end

  def renamed(_other), do: {:ok, []}
end

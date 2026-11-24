defmodule ShreddingRig.MembersTable do
  @moduledoc """
  **Invented.** The members read model, projected in the dispatch transaction: one
  row per membership, with the member's name in the clear. `forget/2` blanks the
  name and keeps the row, so a test can see what was forgotten and what stayed.
  """

  use ShreddingRig.Members, read_model: :members

  import Ecto.Query

  @impl true
  def joined(%Joined{membership_id: membership, member_id: member, name: name}) do
    repo().insert_all("shredding_rig_members", [
      %{membership_id: membership, member_id: member, name: name}
    ])

    :ok
  end

  @impl true
  def renamed(%Renamed{membership_id: membership, name: name}) do
    repo().update_all(from(m in "shredding_rig_members", where: m.membership_id == ^membership),
      set: [name: name]
    )

    :ok
  end

  @impl true
  def forget(:member, member) do
    repo().update_all(from(m in "shredding_rig_members", where: m.member_id == ^member),
      set: [name: nil]
    )

    # Rows a rebuild left partial: it has written, then Postgres refuses the next
    # statement, which aborts the transaction it runs in.
    if Process.get(:shredding_rig_forget_fails), do: repo().query!("SELECT 1 / 0")

    :ok
  end

  defp repo, do: Application.fetch_env!(:ehos_contract, :repo)
end

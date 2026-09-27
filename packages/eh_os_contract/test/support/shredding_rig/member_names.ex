defmodule ShreddingRig.MemberNames do
  @moduledoc """
  **Invented.** The member names read model, projected after the dispatch
  transaction, from the log in order. `forget/2` deletes the member's rows. A name
  that reads back as `EhOsContract.Erased` — an event replayed after its member was
  erased — is kept as `nil`.
  """

  use ShreddingRig.Members, read_model: :member_names

  import Ecto.Query

  @impl true
  def joined(%Joined{membership_id: membership, member_id: member, name: name}) do
    repo().insert_all("shredding_rig_member_names", [
      %{membership_id: membership, member_id: member, name: if(is_binary(name), do: name)}
    ])

    :ok
  end

  @impl true
  def forget(:member, member) do
    repo().delete_all(from(m in "shredding_rig_member_names", where: m.member_id == ^member))
    :ok
  end

  @impl true
  def reset do
    repo().delete_all("shredding_rig_member_names")
    :ok
  end

  defp repo, do: Application.fetch_env!(:eh_os_contract, :repo)
end

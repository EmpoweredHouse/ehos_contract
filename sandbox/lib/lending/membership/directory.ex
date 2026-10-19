defmodule Lending.Membership.Directory do
  @moduledoc """
  **Invented.** The member directory: one row per membership in
  `lending_member_directory`, with the member's name and e-mail in the clear, since
  the desk reads them. `forget/2` deletes an erased member's rows, so nothing of them
  is left in this table. An event replayed after its member was erased carries
  `EhOsContract.Erased` in place of each personal field, kept as `nil`.
  """

  use Lending.Contracts.Membership, read_model: :member_directory

  import Ecto.Query

  @table "lending_member_directory"

  @impl true
  def member_registered(%MemberRegistered{} = registered) do
    repo().insert_all(
      @table,
      [
        %{
          membership_id: registered.membership_id,
          member_id: registered.member_id,
          name: text(registered.name),
          email: text(registered.email)
        }
      ],
      on_conflict: :nothing
    )

    :ok
  end

  @impl true
  def email_changed(%EmailChanged{membership_id: membership, email: email}) do
    repo().update_all(from(m in @table, where: m.membership_id == ^membership),
      set: [email: text(email)]
    )

    :ok
  end

  @impl true
  def forget(:member, member) do
    repo().delete_all(from(m in @table, where: m.member_id == ^member))
    :ok
  end

  @impl true
  def reset do
    repo().delete_all(@table)
    :ok
  end

  defp text(value) when is_binary(value), do: value
  defp text(_erased), do: nil

  defp repo, do: EhOsContract.Config.fetch!(:repo)
end

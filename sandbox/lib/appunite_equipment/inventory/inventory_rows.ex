defmodule AppuniteEquipment.Inventory.InventoryRows do
  @moduledoc """
  Projects the spreadsheet's Inventory tab into `appunite_equipment_inventory`: one
  row per computer, rewritten by every event of it. A row keeps what the tab shows
  — where the computer is, whether it is set up, who has it, its asking price —
  and nothing the tab does not.
  """

  use AppuniteEquipment.Contracts.Computers, read_model: :inventory

  import Ecto.Query

  @table "appunite_equipment_inventory"

  @impl true
  def ordered(%Ordered{computer_id: id, profile: profile}) do
    repo().insert_all(
      @table,
      [
        %{
          computer_id: id,
          profile: Atom.to_string(profile),
          status: "ordered",
          set_up: false,
          reserved: false
        }
      ],
      on_conflict: :nothing
    )

    :ok
  end

  @impl true
  def received(%Received{computer_id: id, serial_number: serial, chip: chip}),
    do: rewrite(id, serial_number: serial, chip: Atom.to_string(chip), status: "in_office")

  @impl true
  def set_up(%SetUp{computer_id: id}), do: rewrite(id, set_up: true)

  @impl true
  def issued(%Issued{computer_id: id, employee_id: employee, as_replacement: replacement}),
    do:
      rewrite(id,
        status: if(replacement, do: "replacement", else: "issued"),
        employee_id: employee
      )

  @impl true
  def return_started(%ReturnStarted{computer_id: id}), do: rewrite(id, status: "returning")

  @impl true
  def returned(%Returned{computer_id: id}),
    do: rewrite(id, status: "in_office", set_up: false, employee_id: nil)

  @impl true
  def wiped(%Wiped{computer_id: id}), do: rewrite(id, set_up: false)

  @impl true
  def sent_for_service(%SentForService{computer_id: id}), do: rewrite(id, status: "in_service")

  @impl true
  def service_returned(%ServiceReturned{computer_id: id}),
    do: rewrite(id, status: "in_office", set_up: false)

  @impl true
  def listed_for_sale(%ListedForSale{computer_id: id, asking_price: price}),
    do: rewrite(id, status: "for_sale", asking_price: price)

  @impl true
  def reserved(%Reserved{computer_id: id}), do: rewrite(id, reserved: true)

  @impl true
  def reservation_dropped(%ReservationDropped{computer_id: id}), do: rewrite(id, reserved: false)

  # The tab shows no difference between the marketplace and Allegro.
  @impl true
  def listed_externally(%ListedExternally{}), do: :ok

  @impl true
  def sold(%Sold{computer_id: id}), do: rewrite(id, status: "sold", reserved: false)

  @impl true
  def donated(%Donated{computer_id: id}), do: rewrite(id, status: "donated")

  @impl true
  def disposed(%Disposed{computer_id: id}), do: rewrite(id, status: "disposed")

  @impl true
  def lost(%Lost{computer_id: id}), do: rewrite(id, status: "lost", employee_id: nil)

  @impl true
  def reset do
    repo().delete_all(@table)
    :ok
  end

  defp rewrite(id, fields) do
    repo().update_all(from(r in @table, where: r.computer_id == ^id), set: fields)
    :ok
  end

  defp repo, do: Application.fetch_env!(:eh_os_contract, :repo)
end

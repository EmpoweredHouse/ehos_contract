defmodule AppuniteEquipment.Inventory.InventoryRows do
  @moduledoc """
  Projects the spreadsheet's Inventory tab into `appunite_equipment_inventory`: one
  row per computer, rewritten by every event of it. A row keeps what the tab shows
  — where the computer is, whether it is set up, who has it, its asking price —
  and nothing the tab does not. Where it is follows the computer's lifecycle: a
  return brings a computer being returned to the office, whatever assignment it
  names (#99, decision 3).
  """

  use AppuniteEquipment.Contracts.Computers, read_model: :inventory

  import Ecto.Query

  @table "appunite_equipment_inventory"
  @ended ["sold", "donated", "disposed", "lost"]

  @impl true
  def ordered(%Ordered{computer_id: id, profile: profile, employee_id: employee}) do
    repo().insert_all(
      @table,
      [
        %{
          computer_id: id,
          profile: Atom.to_string(profile),
          status: "ordered",
          employee_id: employee,
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
  # As in the computer's lifecycle, an observation that does not fit leaves the row
  # where it is: a return only of a computer being returned, a service return only
  # of one in service, an end only of one that has not ended.
  def returned(%Returned{computer_id: id}),
    do: rewrite_when(id, ["returning"], status: "in_office", set_up: false, employee_id: nil)

  @impl true
  def wiped(%Wiped{computer_id: id}), do: rewrite(id, set_up: false)

  @impl true
  def sent_for_service(%SentForService{computer_id: id}), do: rewrite(id, status: "in_service")

  @impl true
  def service_returned(%ServiceReturned{computer_id: id}),
    do: rewrite_when(id, ["in_service"], status: "in_office", set_up: false)

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
  def sold(%Sold{computer_id: id}), do: rewrite_unless_ended(id, status: "sold", reserved: false)

  @impl true
  def donated(%Donated{computer_id: id}),
    do: rewrite_unless_ended(id, status: "donated", reserved: false)

  @impl true
  def disposed(%Disposed{computer_id: id}),
    do: rewrite_unless_ended(id, status: "disposed", reserved: false)

  # As in the lifecycle, a loss is of a computer with an employee; one recorded
  # anywhere else leaves the row where it is.
  @impl true
  def lost(%Lost{computer_id: id}),
    do:
      rewrite_when(id, ["issued", "replacement"],
        status: "lost",
        employee_id: nil,
        reserved: false
      )

  @impl true
  def reset do
    repo().delete_all(@table)
    :ok
  end

  defp rewrite(id, fields) do
    repo().update_all(from(r in @table, where: r.computer_id == ^id), set: fields)
    :ok
  end

  defp rewrite_when(id, statuses, fields) do
    repo().update_all(
      from(r in @table, where: r.computer_id == ^id and r.status in ^statuses),
      set: fields
    )

    :ok
  end

  defp rewrite_unless_ended(id, fields) do
    repo().update_all(
      from(r in @table, where: r.computer_id == ^id and r.status not in ^@ended),
      set: fields
    )

    :ok
  end

  defp repo, do: Application.fetch_env!(:eh_os_contract, :repo)
end

defmodule Fulfilment.Warehouse.PickList do
  @moduledoc """
  **Invented.** Decides a pick list: opened once, claimed once, confirmed picked (by
  its picker, which the engine checks before this runs), and packed once it is picked.
  """

  use Fulfilment.Contracts.Warehouse, aggregate: :pick_list

  @impl true
  def open_pick_list(_command, %State{opened: true}), do: reject(:opened_once)

  def open_pick_list(%OpenPickList{warehouse_id: warehouse, order_id: order}, _state),
    do: emit(%Opened{warehouse_id: warehouse, order_id: order})

  @impl true
  def claim_pick_list(%ClaimPickList{} = claim, %State{opened: true, picker_id: nil}) do
    emit(%Claimed{
      warehouse_id: claim.warehouse_id,
      order_id: claim.order_id,
      picker_id: claim.picker_id
    })
  end

  def claim_pick_list(_command, _state), do: reject(:claimed_once)

  # Who may confirm is the engine's to check (`actor_is`); what is left is whether the
  # list was picked already.
  @impl true
  def confirm_pick(%ConfirmPick{warehouse_id: warehouse, order_id: order}, %State{picked: false}),
    do: emit(%Picked{warehouse_id: warehouse, order_id: order})

  def confirm_pick(_command, _state), do: reject(:confirmed_by_its_picker)

  @impl true
  def pack_parcel(%PackParcel{} = pack, %State{picked: true, packed: false}) do
    emit(%ParcelPacked{
      warehouse_id: pack.warehouse_id,
      order_id: pack.order_id,
      weight_grams: pack.weight_grams
    })
  end

  def pack_parcel(_command, _state), do: reject(:picked_before_packed)

  @impl true
  def evolve(state, %Opened{}), do: %{state | opened: true}
  def evolve(state, %Claimed{picker_id: picker}), do: %{state | picker_id: picker}
  def evolve(state, %Picked{}), do: %{state | picked: true}
  def evolve(state, %ParcelPacked{}), do: %{state | packed: true}
end

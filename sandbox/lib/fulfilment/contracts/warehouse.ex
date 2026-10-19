defmodule Fulfilment.Contracts.Warehouse do
  @moduledoc """
  **Invented.** The warehouse: a paid order opens a pick list in its warehouse, the
  warehouse's lead assigns it to a picker, and the picker confirms it picked and packs
  the parcel.

  - **Leads and pickers are granted per warehouse** (`scope: :warehouse_id`): neither
    acts on another warehouse's pick lists, which the door refuses before anything is
    decided.
  - **A pick list is confirmed by the picker it is assigned to** (`actor_is`): a
    colleague in the same warehouse, granted the same, is refused by the business's own
    rule. The lead may assign it again until it is picked, so a list assigned to the
    wrong person, or to someone who left, is not stuck.
  - **The packed parcel's weight**, `weight_grams`, is what shipping reads to book a
    carrier, so renaming it breaks shipping's contract and its policy.
  """

  use EhOsContract.Contract,
    domain: Fulfilment.Domain,
    context: :warehouse,
    id: "fulfilment.warehouse"

  consumes Fulfilment.Contracts.Orders, :payment_confirmed

  aggregate :pick_list, "Pick list" do
    identity [:warehouse_id, order_id: {:id, :order}]

    state do
      field :opened, :boolean, default: false
      field :picker_id, :id, optional: true
      field :picked, :boolean, default: false
      field :packed, :boolean, default: false
    end

    invariant :opened_once, "A pick list is opened once"

    invariant :assigned_until_picked,
              "A pick list is assigned while it is open and not yet picked"

    invariant :confirmed_by_its_picker, "A pick list is confirmed by the picker it is assigned to"
    invariant :picked_once, "A pick list is picked once"
    invariant :picked_before_packed, "A parcel is packed once, from a picked list"

    command :open_pick_list, "Open a pick list",
      emits: :opened,
      rejects: :opened_once

    command :assign_pick_list, "Assign a pick list to a picker",
      by: :lead,
      scope: :warehouse_id,
      emits: :assigned,
      rejects: :assigned_until_picked do
      field :picker_id, :id
    end

    command :confirm_pick, "Confirm a pick list picked",
      by: :picker,
      scope: :warehouse_id,
      emits: :picked,
      rejects: [:confirmed_by_its_picker, :picked_once] do
      actor_is :picker_id, or_rejects: :confirmed_by_its_picker
    end

    command :pack_parcel, "Pack a parcel",
      by: :picker,
      scope: :warehouse_id,
      emits: :parcel_packed,
      rejects: :picked_before_packed do
      field :weight_grams, :integer
    end

    event :opened, "Pick list opened"

    event :assigned, "Pick list assigned" do
      field :picker_id, :id
    end

    event :picked, "Pick list picked"

    event :parcel_packed, "Parcel packed" do
      field :weight_grams, :integer
    end
  end

  policy :open_pick_list_when_paid, "Open a pick list for a paid order",
    handles: :payment_confirmed,
    issues: :open_pick_list,
    delivery: :at_least_once,
    idempotency: [key: :event_id, owner: :infrastructure]

  @list %{warehouse_id: "w-1", order_id: "order-1"}

  scenario "a paid order opens its pick list" do
    target :open_pick_list_when_paid
    on :payment_confirmed, %{order_id: "order-1", warehouse_id: "w-1"}
    issues :open_pick_list, @list
  end

  scenario "a pick list is opened" do
    command :open_pick_list, @list
    expect :opened
  end

  scenario "a pick list is opened once" do
    given :opened, @list
    command :open_pick_list
    rejected :opened_once
  end

  scenario "the lead assigns an open pick list" do
    given :opened, @list
    command :assign_pick_list, %{picker_id: "picker-ada"}
    expect :assigned, %{picker_id: "picker-ada"}
  end

  scenario "the lead assigns it again before it is picked" do
    given :opened, @list
    given :assigned, %{picker_id: "picker-ada"}
    command :assign_pick_list, %{picker_id: "picker-bob"}
    expect :assigned, %{picker_id: "picker-bob"}
  end

  scenario "a picked list is not assigned again" do
    given :opened, @list
    given :assigned, %{picker_id: "picker-ada"}
    given :picked
    command :assign_pick_list, %{picker_id: "picker-bob"}
    rejected :assigned_until_picked
  end

  scenario "the picker it is assigned to confirms it" do
    actor :picker
    as "picker-ada"
    given :opened, @list
    given :assigned, %{picker_id: "picker-ada"}
    command :confirm_pick
    expect :picked
  end

  scenario "a colleague does not confirm another's pick list" do
    actor :picker
    as "picker-bob"
    given :opened, @list
    given :assigned, %{picker_id: "picker-ada"}
    command :confirm_pick
    rejected :confirmed_by_its_picker
  end

  scenario "a pick list is picked once" do
    actor :picker
    as "picker-ada"
    given :opened, @list
    given :assigned, %{picker_id: "picker-ada"}
    given :picked
    command :confirm_pick
    rejected :picked_once
  end

  scenario "a picked list is packed" do
    given :opened, @list
    given :assigned, %{picker_id: "picker-ada"}
    given :picked
    command :pack_parcel, %{weight_grams: 1_200}
    expect :parcel_packed, %{weight_grams: 1_200}
  end

  scenario "a list not picked is not packed" do
    given :opened, @list
    command :pack_parcel, %{weight_grams: 1_200}
    rejected :picked_before_packed
  end
end

defmodule UpcastRig.Demands do
  @moduledoc """
  # THIS CONTRACT IS INVENTED. IT IS NOT CLIENT MATERIAL.

  A demand, recorded by a clerk. Its event is at version 3 of its fields: version 1
  called the reason `reason` and the note `remark`, and had no priority; version 2
  called the reason `why`. The demand is published with its reason and priority.
  """

  use EhosContract.Contract,
    domain: UpcastRig.Domain,
    context: :requests,
    id: "upcast_rig.demands"

  aggregate :demand, "Demand" do
    identity :demand_id

    event :demand_opened, "Demand opened", recorded_by: :clerk, schema_version: 3 do
      field :requester_id, :id, subject: :requester
      field :note, :string, personal: :requester_id, optional: true
      field :demand_reason, :string
      field :priority, :string

      upcast from: 1, rename: [reason: :why, remark: :note], default: [priority: "normal"]
      upcast from: 2, rename: [why: :demand_reason]
    end
  end

  # Plan DD, V2 (#338): a fee whose amount was stored in cents at version 1, read through
  # a function of the unit's code. The rig's function also does, on purpose, what a
  # function may not, so that the reading can be seen to refuse it.
  aggregate :fee, "Fee" do
    identity :fee_id

    event :fee_charged, "Fee charged", recorded_by: :clerk, schema_version: 2 do
      field :requester_id, :id, subject: :requester
      field :note, :string, personal: :requester_id, optional: true
      field :remark, :string, personal: :requester_id, optional: true
      field :amount, :decimal

      upcast from: 1, function: :amount_from_minor
    end
  end

  publish :demand_opened,
    as: "upcast_rig.demand.opened.v1",
    from: :demand_opened,
    fields: [:demand_id, :demand_reason, :priority]
end

defmodule ValueRig.Till do
  @moduledoc """
  # THIS CONTRACT IS INVENTED. IT IS NOT CLIENT MATERIAL.

  A till takes payments. `pay_in` carries every shape of value `ValueRig.Domain`
  declares; `short_change` is a command whose implementation decides an event with an
  amount of nothing, which dispatch has to stop; the counting machine records what it
  counted. A query asks for payments above an amount, and the domain service halves
  one. A drawer is keyed by its till and its shift, a domain value, so opening one for
  a shift that is no day is refused (#435).
  """

  use EhOsContract.Contract, domain: ValueRig.Domain, context: :till, id: "value_rig.till"

  aggregate :till, "Till" do
    identity :till_id

    command :pay_in, "Pay in", by: :cashier, emits: :paid_in do
      field :amount, :amount
      field :fees, {:list, :fee}, optional: true
      field :window, :window, optional: true
      field :payment, :payment, optional: true
    end

    command :short_change, "Give short change", by: :cashier, emits: :paid_in

    event :paid_in, "Paid in" do
      field :amount, :amount
      field :fees, {:list, :fee}, optional: true
      field :window, :window, optional: true
      field :payment, :payment, optional: true
    end

    event :counted, "Counted", recorded_by: :counter do
      field :amount, :amount
    end
  end

  aggregate :drawer, "Drawer" do
    identity [:till_id, shift_id: :shift]

    command :open_drawer, "Open a drawer", by: :cashier, emits: :drawer_opened

    event :drawer_opened, "Drawer opened"

    event :drawer_counted, "Drawer counted", recorded_by: :counter
  end

  read_model :payments, "Payments", projects: [:paid_in, :counted] do
    field :till_id, :id
    field :amount, :amount
  end

  query :payments_above, "Payments above an amount", reads: :payments, by: :cashier do
    param :above, :amount
  end

  domain_service :splitting, "Splitting" do
    function :half, "Half of an amount, rounded down" do
      argument :amount, :integer
      returns :amount, optional: true

      rule :rounded_down, "An odd amount loses its last cent", examples: [{[5], 2}, {[4], 2}]
      rule :nothing_of_one, "One cent halves into nothing", examples: [{[1], nil}]
    end
  end
end

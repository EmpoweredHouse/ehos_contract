defmodule AppuniteEquipment.Inventory.Computer do
  @moduledoc """
  Decides about one computer. Where it is follows from its history, and so does
  whether it is set up: the setup is lost when it comes back from an employee, is
  formatted, or is cleaned at the reseller, since every one of those erases the
  disk and its MDM profile with it (distillation, finding 4).
  """

  use AppuniteEquipment.Contracts.Computers, aggregate: :computer

  # The generations the team stopped issuing as too slow (T l.66, E). A decision of
  # the team that moves with the market, not of each computer.
  @withdrawn [:m1]

  @impl true
  def order_computer(%OrderComputer{} = order, _state) do
    emit(%Ordered{
      computer_id: order.computer_id,
      profile: order.profile,
      employee_id: order.employee_id
    })
  end

  @impl true
  def receive_computer(%ReceiveComputer{} = invoice, %State{status: :ordered}) do
    emit(%Received{
      computer_id: invoice.computer_id,
      serial_number: invoice.serial_number,
      chip: invoice.chip,
      price: invoice.price,
      purchased_on: invoice.purchased_on,
      invoice_number: invoice.invoice_number
    })
  end

  def receive_computer(_invoice, _state), do: reject(:received_once)

  @impl true
  def set_up_computer(%SetUpComputer{computer_id: id}, %State{status: :in_office}),
    do: emit(%SetUp{computer_id: id})

  def set_up_computer(_command, _state), do: reject(:only_from_the_office)

  @impl true
  def issue_computer(_command, %State{status: :for_sale}), do: reject(:for_sale_not_issued)

  def issue_computer(_command, %State{status: status}) when status != :in_office,
    do: reject(:only_from_the_office)

  def issue_computer(_command, %State{chip: chip}) when chip in @withdrawn,
    do: reject(:withdrawn_generation_not_issued)

  def issue_computer(_command, %State{set_up: false}), do: reject(:set_up_before_issue)

  def issue_computer(%IssueComputer{} = issue, _state) do
    emit(%Issued{
      computer_id: issue.computer_id,
      assignment_id: issue.assignment_id,
      employee_id: issue.employee_id,
      shipped_on: issue.shipped_on,
      tracking_number: issue.tracking_number,
      as_replacement: issue.as_replacement
    })
  end

  @impl true
  def start_return(%StartReturn{} = return, %State{status: :issued, assignment_id: assignment}) do
    emit(%ReturnStarted{
      computer_id: return.computer_id,
      assignment_id: assignment,
      reason: return.reason,
      returned_on: return.returned_on
    })
  end

  def start_return(_command, _state), do: reject(:only_an_issued_computer_returns)

  @impl true
  def wipe_computer(%WipeComputer{computer_id: id}, %State{status: :in_office}),
    do: emit(%Wiped{computer_id: id})

  def wipe_computer(_command, _state), do: reject(:only_from_the_office)

  @impl true
  def send_for_service(%SendForService{} = send, %State{status: :in_office}),
    do: emit(%SentForService{computer_id: send.computer_id, reason: send.reason})

  def send_for_service(_command, _state), do: reject(:only_from_the_office)

  @impl true
  def put_up_for_sale(%PutUpForSale{} = sale, %State{status: :in_office}) do
    emit(%ListedForSale{computer_id: sale.computer_id, asking_price: sale.asking_price})
  end

  def put_up_for_sale(_command, _state), do: reject(:only_from_the_office)

  @impl true
  def reserve_computer(_command, %State{status: status}) when status != :for_sale,
    do: reject(:only_a_listed_computer_is_sold)

  def reserve_computer(_command, %State{listed_externally: true}),
    do: reject(:no_reservation_after_external_listing)

  def reserve_computer(_command, %State{reserved: true}), do: reject(:first_reservation_wins)

  def reserve_computer(%ReserveComputer{} = reservation, _state) do
    emit(%Reserved{computer_id: reservation.computer_id, buyer_id: reservation.buyer_id})
  end

  @impl true
  # Only while it is for sale: a sold computer keeps the reservation it was sold on.
  def drop_reservation(_command, %State{status: status}) when status != :for_sale,
    do: reject(:only_a_reservation_is_dropped)

  def drop_reservation(%DropReservation{computer_id: id}, %State{reserved: true}),
    do: emit(%ReservationDropped{computer_id: id})

  def drop_reservation(_command, _state), do: reject(:only_a_reservation_is_dropped)

  @impl true
  def list_externally(_command, %State{status: :for_sale, reserved: true}),
    do: reject(:allegro_only_without_reservation)

  def list_externally(%ListExternally{computer_id: id}, %State{status: :for_sale}),
    do: emit(%ListedExternally{computer_id: id})

  def list_externally(_command, _state), do: reject(:only_a_listed_computer_is_sold)

  # The channel is where the computer stood when it sold: listed on Allegro, which
  # only a computer nobody reserved can be, or still on the marketplace.
  @impl true
  def sell_computer(%SellComputer{} = sale, %State{status: :for_sale} = state) do
    emit(%Sold{
      computer_id: sale.computer_id,
      price: sale.price,
      invoice_number: sale.invoice_number,
      channel: if(state.listed_externally, do: :allegro, else: :marketplace)
    })
  end

  def sell_computer(_command, _state), do: reject(:only_a_listed_computer_is_sold)

  # A computer for sale that nobody buys may still be given away or disposed of: it
  # is in the office all the same.
  @impl true
  def donate_computer(%DonateComputer{computer_id: id}, %State{status: status})
      when status in [:in_office, :for_sale],
      do: emit(%Donated{computer_id: id})

  def donate_computer(_command, _state), do: reject(:only_from_the_office)

  @impl true
  def dispose_computer(%DisposeComputer{computer_id: id}, %State{status: status})
      when status in [:in_office, :for_sale],
      do: emit(%Disposed{computer_id: id})

  def dispose_computer(_command, _state), do: reject(:only_from_the_office)

  @impl true
  def evolve(state, %Ordered{}), do: state
  def evolve(state, %Received{chip: chip}), do: %{state | status: :in_office, chip: chip}
  def evolve(state, %SetUp{}), do: %{state | set_up: true}

  def evolve(state, %Issued{assignment_id: assignment}),
    do: %{state | status: :issued, assignment_id: assignment}

  def evolve(state, %ReturnStarted{}), do: %{state | status: :returning}

  # The three observations are recorded, not decided, so nothing refuses one that
  # makes no sense — a return of a sold computer, of another assignment, a computer
  # back from Innergo it was never sent to. The log keeps them, and the report shows
  # them off the declared path; the state does not move on them, so a sold computer
  # is never issued again and an issued one never goes to a second employee.
  def evolve(%State{status: :returning, assignment_id: assignment} = state, %Returned{
        assignment_id: assignment
      }),
      do: %{state | status: :in_office, set_up: false, assignment_id: nil}

  def evolve(state, %Returned{}), do: state

  def evolve(state, %Wiped{}), do: %{state | set_up: false}
  def evolve(state, %SentForService{}), do: %{state | status: :in_service}

  def evolve(%State{status: :in_service} = state, %ServiceReturned{}),
    do: %{state | status: :in_office, set_up: false}

  def evolve(state, %ServiceReturned{}), do: state
  def evolve(state, %ListedForSale{}), do: %{state | status: :for_sale}
  def evolve(state, %Reserved{}), do: %{state | reserved: true}
  def evolve(state, %ReservationDropped{}), do: %{state | reserved: false}
  def evolve(state, %ListedExternally{}), do: %{state | listed_externally: true}
  def evolve(state, %Sold{}), do: %{state | status: :ended}
  def evolve(state, %Donated{}), do: %{state | status: :ended}
  def evolve(state, %Disposed{}), do: %{state | status: :ended}
  def evolve(state, %Lost{}), do: %{state | status: :ended}
end

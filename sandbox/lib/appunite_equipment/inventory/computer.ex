defmodule AppuniteEquipment.Inventory.Computer do
  @moduledoc """
  Decides about one computer. Where it is is the engine's: the contract's lifecycle
  follows it from the events, and refuses a command issued where it does not belong
  before any of this runs (`from:`). What is left here are the rules finer than
  where the computer is. Whether it is set up follows from its history: the setup is
  lost when it comes back from an employee, is formatted, or is cleaned at the
  reseller, since every one of those erases the disk and its MDM profile with it
  (distillation, finding 4).
  """

  use AppuniteEquipment.Contracts.Computers, aggregate: :computer

  # The generations the team stopped issuing as too slow (T l.66, E). A decision of
  # the team that moves with the market, not of each computer.
  @withdrawn [:m1]

  @impl true
  def receive_computer(%ReceiveComputer{} = invoice, _state) do
    emit(%Received{
      computer_id: invoice.computer_id,
      profile: invoice.profile,
      serial_number: invoice.serial_number,
      chip: invoice.chip,
      price: invoice.price,
      purchased_on: invoice.purchased_on,
      invoice_number: invoice.invoice_number
    })
  end

  @impl true
  def set_up_computer(%SetUpComputer{computer_id: id}, _state), do: emit(%SetUp{computer_id: id})

  @impl true
  # Issued from the office, and from sale only to be refused on its own rule: the
  # process owner says "for sale" apart from "not in the office" (A:G).
  def issue_computer(_command, %State{status: :for_sale}), do: reject(:for_sale_not_issued)

  def issue_computer(_command, %State{chip: chip}) when chip in @withdrawn,
    do: reject(:withdrawn_generation_not_issued)

  def issue_computer(_command, %State{set_up: false}), do: reject(:set_up_before_issue)

  def issue_computer(%IssueComputer{} = issue, _state) do
    emit(%Issued{
      computer_id: issue.computer_id,
      demand_id: issue.demand_id,
      assignment_id: issue.assignment_id,
      employee_id: issue.employee_id,
      shipped_on: issue.shipped_on,
      tracking_number: issue.tracking_number,
      as_replacement: issue.as_replacement
    })
  end

  @impl true
  def start_return(%StartReturn{} = return, %State{assignment_id: assignment}) do
    emit(%ReturnStarted{
      computer_id: return.computer_id,
      assignment_id: assignment,
      reason: return.reason,
      returned_on: return.returned_on
    })
  end

  @impl true
  def wipe_computer(%WipeComputer{computer_id: id}, _state), do: emit(%Wiped{computer_id: id})

  @impl true
  def send_for_service(%SendForService{} = send, _state),
    do: emit(%SentForService{computer_id: send.computer_id, reason: send.reason})

  @impl true
  def put_up_for_sale(%PutUpForSale{} = sale, _state),
    do: emit(%ListedForSale{computer_id: sale.computer_id, asking_price: sale.asking_price})

  @impl true
  def reserve_computer(_command, %State{listed_externally: true}),
    do: reject(:no_reservation_after_external_listing)

  def reserve_computer(_command, %State{reserved: true}), do: reject(:first_reservation_wins)

  def reserve_computer(%ReserveComputer{} = reservation, _state) do
    emit(%Reserved{computer_id: reservation.computer_id, buyer_id: reservation.buyer_id})
  end

  @impl true
  # Only while it is for sale (`from:`): a sold computer keeps the reservation it was
  # sold on.
  def drop_reservation(%DropReservation{computer_id: id}, %State{reserved: true}),
    do: emit(%ReservationDropped{computer_id: id})

  def drop_reservation(_command, _state), do: reject(:only_a_reservation_is_dropped)

  @impl true
  def list_externally(_command, %State{reserved: true}),
    do: reject(:allegro_only_without_reservation)

  def list_externally(%ListExternally{computer_id: id}, _state),
    do: emit(%ListedExternally{computer_id: id})

  # The channel is where the computer stood when it sold: listed on Allegro, which
  # only a computer nobody reserved can be, or still on the marketplace.
  @impl true
  def sell_computer(%SellComputer{} = sale, state) do
    emit(%Sold{
      computer_id: sale.computer_id,
      price: sale.price,
      invoice_number: sale.invoice_number,
      channel: if(state.listed_externally, do: :allegro, else: :marketplace)
    })
  end

  # A computer for sale that nobody buys may still be given away or disposed of: it
  # is in the office all the same (`from: [:in_office, :for_sale]`).
  @impl true
  def donate_computer(%DonateComputer{computer_id: id}, _state),
    do: emit(%Donated{computer_id: id})

  @impl true
  def dispose_computer(%DisposeComputer{computer_id: id}, _state),
    do: emit(%Disposed{computer_id: id})

  @impl true
  def evolve(state, %Received{chip: chip}), do: %{state | chip: chip}
  def evolve(state, %SetUp{}), do: %{state | set_up: true}
  def evolve(state, %Issued{assignment_id: assignment}), do: %{state | assignment_id: assignment}

  # The status before each event is the engine's, and an observation that does not
  # fit it — a return of a sold computer, a computer back from Innergo it was never
  # sent to — moves nothing and changes nothing here either. A return of another
  # assignment does bring the computer to the office (#99, decision 3): whether the
  # assignments match is the assignment's question, not the computer's.
  def evolve(%State{status: :returning} = state, %Returned{}),
    do: %{state | set_up: false, assignment_id: nil}

  def evolve(state, %Wiped{}), do: %{state | set_up: false}

  def evolve(%State{status: :in_service} = state, %ServiceReturned{}),
    do: %{state | set_up: false}

  def evolve(state, %Reserved{}), do: %{state | reserved: true}
  def evolve(state, %ReservationDropped{}), do: %{state | reserved: false}
  def evolve(state, %ListedExternally{}), do: %{state | listed_externally: true}
  def evolve(state, _event), do: state
end

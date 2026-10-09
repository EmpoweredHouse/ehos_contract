defmodule PersonRig.Desk do
  @moduledoc """
  # THIS CONTRACT IS INVENTED. IT IS NOT CLIENT MATERIAL.

  A ticket is assigned to a clerk, and only that clerk resolves it: another clerk with
  the same credential is refused. The night shift, the application's own code, resolves
  whatever is left, whoever it is assigned to.
  """

  use EhOsContract.Contract, domain: PersonRig.Domain, context: :desk, id: "person_rig.desk"

  aggregate :ticket, "Ticket" do
    identity :ticket_id

    state do
      field :assignee_id, :id, optional: true
    end

    invariant :only_its_assignee_resolves, "A ticket is resolved by the clerk it is assigned to"

    command :assign_ticket, "Assign the ticket", by: :clerk, emits: :assigned do
      field :assignee_id, :id
    end

    command :resolve_ticket, "Resolve the ticket",
      by: [:clerk, :night_shift],
      emits: :resolved,
      rejects: :only_its_assignee_resolves do
      actor_is :assignee_id, or_rejects: :only_its_assignee_resolves
    end

    event :assigned, "Ticket assigned" do
      field :assignee_id, :id
    end

    event :resolved, "Ticket resolved"
  end

  read_model :tickets, "Tickets", projects: [:assigned, :resolved] do
    field :ticket_id, :id
  end

  query :tickets_of_desk, "Tickets of the desk", reads: :tickets, by: :clerk

  scenario "a ticket is assigned" do
    command :assign_ticket, %{assignee_id: "clerk-ada"}
    expect :assigned, %{assignee_id: "clerk-ada"}
  end

  scenario "the clerk it is assigned to resolves it" do
    actor :clerk
    as "clerk-ada"
    given :assigned, %{assignee_id: "clerk-ada"}
    command :resolve_ticket
    expect :resolved
  end

  scenario "another clerk does not" do
    actor :clerk
    as "clerk-bo"
    given :assigned, %{assignee_id: "clerk-ada"}
    command :resolve_ticket
    rejected :only_its_assignee_resolves
  end

  scenario "the night shift resolves what is left" do
    actor :night_shift
    given :assigned, %{assignee_id: "clerk-ada"}
    command :resolve_ticket
    expect :resolved
  end

  # The read model keeps nothing: it is here so that the events have a reader.
  scenario "the desk's tickets are nothing, since nothing is kept" do
    given :assigned, %{assignee_id: "clerk-ada"}
    query :tickets_of_desk, %{}
    answers []
  end
end

defmodule PersonRig.Ticket do
  @moduledoc "**Invented.** Assigns and resolves a ticket; who may resolve it is the contract's."

  use PersonRig.Desk, aggregate: :ticket

  @impl true
  def assign_ticket(%AssignTicket{ticket_id: id, assignee_id: clerk}, _state),
    do: emit(%Assigned{ticket_id: id, assignee_id: clerk})

  @impl true
  def resolve_ticket(%ResolveTicket{ticket_id: id}, _state), do: emit(%Resolved{ticket_id: id})

  @impl true
  def evolve(state, %Assigned{assignee_id: clerk}), do: %{state | assignee_id: clerk}
  def evolve(state, %Resolved{}), do: state
end

defmodule PersonRig.Tickets do
  @moduledoc "**Invented.** Keeps nothing."

  use PersonRig.Desk, read_model: :tickets

  @impl true
  def assigned(_event), do: :ok

  @impl true
  def resolved(_event), do: :ok
end

defmodule PersonRig.TicketsOfDesk do
  @moduledoc "**Invented.** Answers nothing: nothing is kept."

  use PersonRig.Desk, query: :tickets_of_desk

  @impl true
  def tickets_of_desk(%TicketsOfDesk{}, _ctx), do: []
end

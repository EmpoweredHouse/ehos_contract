# Issue a command from a form

This page tells how to let a person issue a command from a page of your application. The form checks
what the person types by the rules of the contract. When the person submits, the form shows the
refusal of dispatch at its field. The page is for a developer who writes the pages of an application.
[The glossary](glossary.md) defines each word of the contract language.

<!-- covers: entities contract.aggregate.command -->

`EhOsContract.Form` builds an `Ecto.Changeset` from the declaration of the command. So you write each
rule one time, in the contract. The same module builds a form for two other inputs of a person:

- an event that an actor records (`recorded_by:`), for `EhOsContract.record/3`;
- the params of a query, such as a search or a filter, for `EhOsContract.query/3`.

A *form* on this page is each input that arrives as text: an HTML page, an import of a CSV file, a
console.

## Before you start

- Write a contract with the command, as [Write a domain, a contract and a process
  module](contract.md) tells.
- Write the module of each value with invariants, as [Actors, values, entities and external
  systems](domain-data.md#what-is-an-invariant-of-a-value) tells.
- Use Phoenix LiveView for the page. The examples use its function components `<.form>` and
  `<.input>`.

## Which rules does the form check?

The contract holds each rule. Examples: a required field, the members of an enum, an invariant of a
value or of a unit, a constraint of a command. The form and dispatch read the rules from
the contract.

![The form checks each field as the person types; dispatch checks the invariants of the unit, and the form shows its refusal at the field.](img/forms-refusal.svg)

1. The person types in a field. The person is the actor of the command. The LiveView gets a
   `phx-change` event.
2. The LiveView builds the changeset with `EhOsContract.Form.changeset/4`.
3. The changeset checks the shape of the input: each required field, the type of each value, and
   each invariant of a value. It asks the module of the value, as dispatch does.
4. The LiveView shows the errors of the changeset at their fields.
5. The person submits the form. The LiveView gets a `phx-submit` event.
6. The LiveView makes the command with `EhOsContract.Form.to_struct/1`, and dispatches it.
7. Dispatch reads the history of the unit. The implementation rejects the command on an invariant
   of the unit.
8. Dispatch returns the rejection to the LiveView.
9. The LiveView puts the rejection on the changeset with `EhOsContract.Form.refused/3`.
10. The LiveView shows the rejection on the form.

The changeset cannot check an invariant of a unit or a constraint of a command, because these need
the history of the unit. Only dispatch reads the history. So do not write such a rule again as a
validation in the page. A second rule can disagree with the first, and no test fails when it does.

Your application keeps these things:

- The fields that the form has and the command does not, such as a search box or an "add another
  row" button. Put them in a changeset of their own.
- Each word that a person reads. The engine puts its reason on each error and writes no message. So
  your application writes the message, in the language of its client.
- The layout of the form, and what it tells about a refusal that belongs to no field. Examples: a
  capability that the person does not have, or a field that the host cannot supply.

## 1. Declare the command

Example: an accountant issues an invoice for a month. The value `:period` is a month written
`YYYY-MM`: this is the invariant of the value. An invoice is issued one time: this is the invariant
of the unit.

```elixir
defmodule Concepts.Forms.Domain do
  use EhOsContract.Domain, name: :forms_example, language: :en

  subdomain :core, "Core", type: :core
  context :invoicing, "Invoicing", subdomain: :core
  actor :accountant, :human, "Accountant"

  value :period, :string do
    invariant :written_as_month, "A period is a month written YYYY-MM",
      violated_by: ["2026-13", "July"],
      satisfied_by: ["2026-07"]
  end
end
```

```elixir
defmodule Concepts.Forms.Period do
  use Concepts.Forms.Domain, value: :period

  @impl true
  def written_as_month(period), do: period =~ ~r/\A[0-9]{4}-(0[1-9]|1[0-2])\z/
end
```

```elixir
defmodule Concepts.Forms.Contracts.Invoicing do
  use EhOsContract.Contract,
    domain: Concepts.Forms.Domain,
    context: :invoicing,
    id: "forms_example.invoicing"

  aggregate :invoice, "Invoice" do
    identity :invoice_id

    invariant :issued_once, "An invoice is issued once"

    command :issue_invoice, "Issue an invoice",
      by: :accountant,
      emits: :invoice_issued,
      rejects: :issued_once do
      field :period, :period
      field :amount, :decimal
      field :method, {:enum, [:card, :transfer]}
      field :due_on, :date
      field :note, :string, optional: true
    end

    event :invoice_issued, "Invoice issued" do
      field :period, :period
      field :amount, :decimal
      field :method, {:enum, [:card, :transfer]}
      field :due_on, :date
      field :note, :string, optional: true
    end
  end

  scenario "an invoice is issued once" do
    given :invoice_issued, %{
      invoice_id: "inv-1",
      period: "2026-07",
      amount: "120.00",
      method: :transfer,
      due_on: "2026-08-14"
    }

    command :issue_invoice, %{
      invoice_id: "inv-1",
      period: "2026-07",
      amount: "120.00",
      method: :transfer,
      due_on: "2026-08-14"
    }

    rejected :issued_once
  end
end
```

## 2. Build the changeset in the LiveView

Build the changeset on `mount` and on each `phx-change`. Dispatch the command on `phx-submit`.

Put the identity of the invoice in `data:`. The page decides the identity, not the person. The form
ignores a value for the identity in the params.

<!-- not compiled: functions of the host's LiveView -->
```elixir
alias Concepts.Forms.Contracts.Invoicing
alias Concepts.Forms.Contracts.Invoicing.Commands.IssueInvoice

def mount(%{"id" => id}, _session, socket) do
  changeset = EhOsContract.Form.changeset(Invoicing, IssueInvoice, %{}, data: %{invoice_id: id})
  # One key per form shown, so a second submit of the same form is the same command.
  {:ok, assign(socket, invoice_id: id, form_key: Ecto.UUID.generate(), form: to_form(changeset))}
end

def handle_event("validate", %{"issue_invoice" => params}, socket) do
  changeset = EhOsContract.Form.changeset(Invoicing, IssueInvoice, params, data: data(socket))
  {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
end

def handle_event("save", %{"issue_invoice" => params}, socket) do
  changeset = EhOsContract.Form.changeset(Invoicing, IssueInvoice, params, data: data(socket))

  with {:ok, command} <- EhOsContract.Form.to_struct(changeset),
       {:ok, _receipt} <-
         EhOsContract.dispatch(Invoicing, command,
           actor: socket.assigns.actor,
           idempotency_key: socket.assigns.form_key
         ) do
    {:noreply, push_navigate(socket, to: ~p"/invoices/#{command.invoice_id}")}
  else
    {:error, %Ecto.Changeset{} = changeset} ->
      {:noreply, assign(socket, :form, to_form(changeset))}

    {:error, reason} ->
      changeset = EhOsContract.Form.refused(changeset, reason)
      {:noreply, assign(socket, :form, to_form(changeset))}
  end
end

defp data(socket), do: %{invoice_id: socket.assigns.invoice_id}
```

The idempotency key is the same for each submit of one form. If the person submits the same command
two times, dispatch appends its events one time. The second submit gets the receipt of the first.

## 3. Show the form and its errors

```heex
<.form for={@form} phx-change="validate" phx-submit="save">
  <.error :for={error <- @form[:base].errors}>{error_message(error)}</.error>
  <.input field={@form[:period]} label="Period" placeholder="2026-07" />
  <.input field={@form[:amount]} label="Amount" />
  <.input field={@form[:method]} type="select" label="Paid by" options={[Card: :card, Transfer: :transfer]} />
  <.input field={@form[:due_on]} type="date" label="Due on" />
  <.input field={@form[:note]} label="Note" />
  <.button>Issue</.button>
</.form>
```

Write the messages in your error helper. Read the reason of the engine from each error, not its
message:

<!-- not compiled: a function of the host's error helpers -->
```elixir
def error_message({_message, opts}) do
  case {opts[:validation], opts[:invariant]} do
    {:required, _} -> "Fill this in"
    {:type, _} -> "This is not a valid value"
    {:invariant, :written_as_month} -> "Write the month as YYYY-MM"
    {:rejected, :issued_once} -> "This invoice was already issued"
    {:unknown, _} -> "Nothing of that name exists"
    _other -> "This cannot be accepted"
  end
end
```

**Result:** when the person types `July` in the period, the form shows "Write the month as
YYYY-MM" at the field. When the person issues an invoice that was issued before, the form shows
"This invoice was already issued" at the top.

## Build a form that records an event, or asks a query

A form that records an event is built from the event. Its struct goes to `record/3`. A refusal comes
back through `refused/3`, as for a command.

A search form is built from the query. A query has no identity, so the form checks its params as
fields. Its struct goes to `query/3`.

<!-- not compiled: code of the host's LiveView -->
```elixir
# `InvoicesOfPeriod`: a query over a read model of invoices, which a contract declares beside the
# example's command.
changeset = EhOsContract.Form.changeset(Invoicing, Invoicing.Queries.InvoicesOfPeriod, params)

with {:ok, query} <- EhOsContract.Form.to_struct(changeset),
     {:ok, rows} <- EhOsContract.query(Invoicing, query, actor: socket.assigns.actor) do
  assign(socket, rows: rows, filter: to_form(changeset, action: :validate))
else
  {:error, %Ecto.Changeset{} = changeset} -> assign(socket, :filter, to_form(changeset))
  {:error, reason} -> assign(socket, :filter, to_form(EhOsContract.Form.refused(changeset, reason)))
end
```

If the page knows the name of a capability and not its module, build the changeset by the name:
`Form.changeset({:command, "forms_example.issue_invoice"}, params)`. The form looks for the name in
the registered contracts, or in the contracts that `contracts:` names. `EhOsContract.call/3` takes
data with the types of JSON. Send the text of a form through `Form` first.

## Show a form only to the people who can use it

A form does not ask the `EhOsContract.Authorizer`. It checks only the shape that the contract
declares. Dispatch asks if the person can issue the command, when the form is sent.

A form also does not hold the person to one unit. The `EhOsContract.Authorizer` and your application
decide who can act on which unit.

## How does the form read the input?

- **Text.** Each value arrives as text. The form reads it as its declared type: an integer, a
  boolean, a decimal, a date or a timestamp.
- **A blank field.** A field with `""` or only spaces is absent. A required field is then an error.
  An optional field is then `nil`.
- **A select.** The form looks for the text among the members of the enum. An unknown text is an
  error. The form makes no atom from the text.
- **A timestamp.** The form reads a `:timestamp` from ISO 8601 text with its offset, such as
  `2026-08-14T09:30:00Z`. `<input type="datetime-local">` sends no seconds and no offset. Add them
  in the page, or make the field a `:date`.
- **A field that the params do not have.** It keeps its value from `data:`. So an edit form does not
  need to show each field.
- **A field that the params have.** The form reads it from the params, also when it is blank. A
  `<select multiple>` or a checkbox sends nothing when the person chooses nothing. To clear the value
  from `data:`, add a hidden blank input. `<.input type="checkbox">` adds one.
- **A field that the page does not show.** Params that carry the field still set it. Put a value
  that the page decides into the struct after `to_struct/1`.

The form does not read these fields from the params:

- the identity in `data:`. The form does not show it back from the params either;
- a field that the host supplies (`supplied_by: :host`). Give it in `data:`, or pass `supply: true` to
  `dispatch/3`, which then asks the `EhOsContract.Supplier`;
- an identity that dispatch generates for a unit that the command creates.

Another field in `data:` is only a start value. The person can change it.

## How does the form read rows?

A value of fields is a row. A list of such values is one row for each item. The rows arrive as a map
keyed by their index, and the form reads them in that order.

- Each row is a changeset of its own. `<.inputs_for>` shows it with its own errors.
- An error of a field goes on its field. An invariant of the value as a whole goes on the `:base` of
  the row.
- The form reads a row whole from the params. A field of the row that the page did not show is
  absent. It does not come from `data:`.
- The form drops a blank item. A checkbox group or a list sends one, so that the field arrives when
  the person chooses nothing. A list with no rows is an empty list.
- The form does not read `items_sort[]` and `items_drop[]` of Phoenix. If the page adds, removes or
  moves rows, change the params that it passes.

A LiveView reads the whole form, each row too, on each `phx-change`. Limit what a form can send where
the host takes it: the `max_frame_size` of the socket, and the `length` of the parser.

## Which errors can a field get?

Each error carries the reason of the engine in its keyword list:

| Error | When |
| --- | --- |
| `{"can't be blank", validation: :required}` | A required field is missing or blank. |
| `{"is invalid", validation: :type}` | A value is not of its declared type, or not a member of the enum. |
| `{"is invalid", validation: :invariant, invariant: name}` | A value breaks the invariant `name` of its value. For a value of fields, the error goes on the `:base` of its row. |
| `{"does not exist", validation: :unknown}` | Dispatch found no entity with the identity in the field (`refused/3`). |
| `{"was refused", validation: :rejected, invariant: name}` | Dispatch refused on the invariant of the unit or the constraint of the command `name` (`refused/3`). |
| `{"is invalid", validation: :generated \| :supplied}` | The command carried a field that dispatch generates or the host supplies (`refused/3`). This is an error of the page, not of the person. |

## Where does a refusal go on the form?

- A rule names no field. So `refused/3` puts a rejection on `:base`, the errors of the whole form.
  To put it at a field, name the field: `refused(changeset, reason, at: [period_closed: :period])`.
- A problem at a field that the form did not send goes on `:base` too, with `field:` to name the
  field. Examples: the identity in `data:`, or a field that the host supplies. So no error shows at
  an input that is not on the page.
- A command with a field named `base` shares that key with the errors of the whole form.

Some refusals put no error on the changeset, because they belong to no field:

- a capability that the person does not have;
- an idempotency key used for another command;
- a field that the host cannot supply.

Show these from the reason that `dispatch/3` returned.

## Next steps

- [Units](units.md): invariants and constraints, which only dispatch checks.
- [Reading](reading.md): queries and read models, for a search form.
- [Authorization](authorization.md): who can issue a command.
- `EhOsContract.Form`: each function of the form, with its options.

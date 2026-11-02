# Issue a command from a form

<!-- covers: entities contract.aggregate.command -->

This page tells how to check the input of a form against the contract. It also tells how to show
the refusal of dispatch on the form. It is for a developer who writes the pages of an
application. [The glossary](glossary.md) defines each word in italics.

A command declares its fields: which fields are required, their types, the enums and values of the
domain, and the invariants of those values. Dispatch holds each command to this declaration. A
*form* is input that a person sends as text: an HTML form, a CSV import, a console. The application
must hold it to the same rules before it sends the command, and tell which field is wrong.
`EhOsContract.Form` builds an `Ecto.Changeset` from the declaration of the command. So you write the
rules one time, in the contract.

The same steps apply to an event that an actor records, and to the params of a query.

## Before you start

- A Phoenix LiveView page, with the `actor` of the person in its assigns.
- The `CoreComponents` module that Phoenix 1.8 generates, with `<.input>` and `translate_error/1`.
- A contract with the command, and a module for each domain value with invariants.

This page uses this contract. An accountant issues an invoice for a month. A period is a month
written `YYYY-MM`: this is the invariant of the value. An invoice is issued one time: this is the
invariant of the unit.

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
  def written_as_month(period), do: period =~ ~r/\A[0-9]{4}-(0[1-9]|1[0-2])\z/u
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

## Put each rule in the contract

Declare each rule in the domain or in the contract, and in no other place. Examples: a required
field, a type, the members of an enum, an invariant of a value or of a unit, a constraint of a
command.

- The changeset checks the shape of the input. It checks that each needed field is there, and that
  each value has its declared type. It asks the domain if a domain value keeps its invariants, as
  dispatch does. Example: the period of this page, written `YYYY-MM`.
- The changeset does not check an invariant of a unit, or a constraint of a command. These need the
  history of the unit, and only dispatch reads it. The rule comes back as the refusal of dispatch,
  which `EhOsContract.Form.refused/3` puts on the changeset.

Do not write an invariant of a unit again as a validation in the page. Your validation is a second
rule. It can disagree with the first, and no test fails when it does.

Keep these things in the application:

- the fields of the form that the command does not have, in a changeset of its own. Examples: a
  search box, the query of a picker, "add another row".
- each word that a person reads. The engine puts its reason on each error, and writes no message of
  its own. The application writes the message, in the language of its client.
- the layout of the form, and what it says about a refusal that belongs to no field. Examples: a
  capability that the person does not have, a field that the host did not supply.

## What occurs from a keystroke to a refusal?

![The page builds the changeset on each change; on submit, it dispatches the command, and puts the refusal of dispatch back on the form.](img/form-refusal.svg)

1. The person types in the form. The page gets a `phx-change` event.
2. The page builds the changeset with `EhOsContract.Form.changeset/4`.
3. The changeset gives the errors of the shape: a missing field, a wrong type, a broken invariant of
   a domain value.
4. The person submits the form. The page gets a `phx-submit` event.
5. `EhOsContract.Form.to_struct/1` converts a valid changeset into the struct of the command.
6. The page dispatches the command with the actor of the person.
7. Dispatch reads the history of the unit, and asks the implementation to decide.
8. The implementation rejects the command on the invariant of the unit.
9. Dispatch returns `{:error, reason}` to the page.
10. `EhOsContract.Form.refused/3` puts the reason on the changeset.
11. The page shows the error on the form, in the words of the application.

The steps below write this code.

## Build the changeset of the form

Build the changeset in `mount/3`. Put the identity of the invoice in `data:`. The page decides the
identity, not the person: when `data:` holds the identity, the changeset ignores a value of the
identity in the params.

Before you show the form, check that the person can act on this invoice. The
`EhOsContract.Authorizer` checks the capability and its scope. It does not check the unit, unless
the scope of the command is the identity of the unit.

<!-- not compiled: functions of the host's LiveView -->
```elixir
alias Concepts.Forms.Contracts.Invoicing
alias Concepts.Forms.Contracts.Invoicing.Commands.IssueInvoice

def mount(%{"id" => id}, _session, socket) do
  # Check here that this person may act on this invoice: the Authorizer does not.
  changeset = EhOsContract.Form.changeset(Invoicing, IssueInvoice, %{}, data: %{invoice_id: id})
  # One key per form shown, so a second submit of the same form is the same command.
  key = Ecto.UUID.generate()
  {:ok, assign(socket, invoice_id: id, form_key: key, form: to_form(changeset))}
end

defp data(socket), do: %{invoice_id: socket.assigns.invoice_id}
```

```heex
<.form for={@form} id="issue-invoice" phx-change="validate" phx-submit="save">
  <input type="hidden" name="form_key" value={@form_key} />
  <p :for={error <- @form[:base].errors} class="text-error">{translate_error(error)}</p>
  <.input field={@form[:period]} label="Period" placeholder="2026-07" />
  <.input field={@form[:amount]} label="Amount" />
  <.input field={@form[:method]} type="select" label="Paid by" options={[Card: :card, Transfer: :transfer]} />
  <.input field={@form[:due_on]} type="date" label="Due on" />
  <.input field={@form[:note]} label="Note" />
  <.button>Issue</.button>
</.form>
```

Give the form an `id`. Without an `id`, LiveView does not restore the form after a reconnect.

Keep the key in a hidden input of the form. After a reconnect, LiveView calls `mount/3` again, and
`mount/3` makes a new key. LiveView then sends the old inputs of the form to `phx-change`. The
`phx-change` handler takes the old key back from them. So, if the person submits again after a lost
reply, dispatch gets the same key. A new page makes a new key: a reload, also one that LiveView
starts itself, or a navigation back to the page.

**Result:** the page shows an empty form for the invoice.

## Check the form while the person types

Build the changeset again on each `phx-change`:

<!-- not compiled: a function of the host's LiveView -->
```elixir
def handle_event("validate", %{"issue_invoice" => params} = event, socket) do
  changeset = EhOsContract.Form.changeset(Invoicing, IssueInvoice, params, data: data(socket))
  socket = assign(socket, :form, to_form(changeset, action: :validate))
  {:noreply, keep_key(socket, event["form_key"])}
end

# After a reconnect, take back the key of the form. Accept only a UUID, as mount/3 makes it.
defp keep_key(socket, key) when is_binary(key) and byte_size(key) == 36 do
  case Ecto.UUID.cast(key) do
    {:ok, key} -> assign(socket, :form_key, key)
    :error -> socket
  end
end

defp keep_key(socket, _key), do: socket
```

The key comes from the browser, and dispatch writes it to the log. So `keep_key/2` accepts only a
UUID, as `mount/3` makes it.

**Result:** if the person types `July` as the period, the page shows an error at the period.

## Send the command, and put the refusal on the form

On `phx-submit`, convert the changeset into the command, and dispatch it. Give dispatch the key of
the form, so that a second submit of the same form is the same command. If dispatch accepted the
first command, it returns the receipt of that command, also if the person changed the form.

<!-- not compiled: a function of the host's LiveView -->
```elixir
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
      {:noreply, socket |> assign(:form, to_form(changeset)) |> notice(reason)}
  end
end
```

A rule of a unit names no field. So `refused/3` puts a rejection on `:base`, the errors of the whole
form. To show it at a field, name the field:
`refused(changeset, reason, at: [issued_once: :period])`.

**Result:** if the invoice was issued before, the page shows the rejection `issued_once`.

## Write the messages from the reasons

Each error carries the reason of the engine in its keyword list. Write the message from the reason,
not from the text of the error.

`<.input>` shows the errors of its field through `translate_error/1` of `CoreComponents`. Write the
messages in that function. Then `<.input>` and the errors on `:base` show the same words.

`translate_error/1` shows the errors of each form of the application. So match only the reasons of
the engine. Rename the generated function, and call it for each other error:

<!-- not compiled: functions of the host's CoreComponents -->
```elixir
def translate_error({_message, opts} = error) do
  case {opts[:validation], opts[:invariant]} do
    {:type, _} -> "This is not a valid value"
    {:invariant, :written_as_month} -> "Write the month as YYYY-MM"
    {:rejected, :issued_once} -> "This invoice was already issued"
    {:unknown, _} -> "Nothing of that name exists"
    _other -> generated_translate_error(error)
  end
end

# The translate_error/1 that Phoenix generated, with Gettext. Keep the body that your application has.
defp generated_translate_error({message, opts}) do
  if count = opts[:count] do
    Gettext.dngettext(MyAppWeb.Gettext, "errors", message, message, count, opts)
  else
    Gettext.dgettext(MyAppWeb.Gettext, "errors", message, opts)
  end
end
```

`refused/3` puts an error on the changeset only for a problem of a field and for a rejection. Tell
the person about each other refusal from its reason. The first two clauses leave what the form
already shows:

<!-- not compiled: functions of the host's LiveView -->
```elixir
defp notice(socket, {:invalid, _problems}), do: socket
defp notice(socket, %EhOsContract.Rejection{}), do: socket

defp notice(socket, reason) when reason in [:missing_capability, :unscoped_grant, :outside_scope],
  do: put_flash(socket, :error, "You cannot issue this invoice. Ask for access.")

defp notice(socket, reason) when reason in [:conflict, :not_caught_up],
  do: put_flash(socket, :error, "The invoice was not issued. Try again in a moment.")

defp notice(socket, {:not_supplied, _reason}),
  do: put_flash(socket, :error, "The invoice was not issued. Try again in a moment.")

defp notice(socket, _other), do: put_flash(socket, :error, "The invoice was not issued.")
```

| Error | When |
| --- | --- |
| `{"can't be blank", validation: :required}` | A required field is missing or blank. |
| `{"is invalid", validation: :type}` | A value does not have its declared type, or is not a member of its enum. |
| `{"is invalid", validation: :invariant, invariant: name}` | A domain value breaks its invariant `name`. For a value with fields as a whole, the error is on the `:base` of its row. |
| `{"does not exist", validation: :unknown}` | Dispatch found no entity that the field names. `refused/3` puts this error. |
| `{"was refused", validation: :rejected, invariant: name}` | Dispatch rejected the command on the invariant of the unit, or on the constraint of the command, `name`. The error is at the field that `at:` names, or at `:base`. `refused/3` puts this error. |
| `{"is invalid", validation: :generated \| :supplied}` | The command carried a field that dispatch generates or the host supplies. This is a mistake of the page, not of the person. `refused/3` puts this error. |

**Result:** the person reads each error in the language of the application.

## Record an event, or ask a query, from a form

`Form.changeset/4` also takes the module of an event that an actor records, or of a query.
`Form.to_struct/1` gives the struct that each of them takes.

- To record an event, build the changeset from the event. Its struct goes to `EhOsContract.record/3`.
  A refusal comes back through `refused/3`, as for a command.
- For a search form, or a filter over a read model, build the changeset from the query. A query has no identity:
  the changeset checks its params as fields. Its struct goes to `EhOsContract.query/3`.

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

## Build the changeset from the name of a capability

A page can know the name of a capability and not its module, as `EhOsContract.call/3` takes it.
Then build the changeset by the name:
`Form.changeset({:command, "forms_example.issue_invoice"}, params)`. `Form` looks for the name in
the registered contracts, or in the contracts that `contracts:` names.

`call/3` takes data with the types that JSON gives it. Send the text of a form through `Form`.

## What can go wrong

**The changeset does not check who can act.** `Form` does not ask the `EhOsContract.Authorizer`. It
checks only the shape that the contract declares. Examples: the fields, their types, the members of
an enum, and the names of the invariants of its values. Dispatch asks if the person can issue the
command, when the page sends it. Show a form only to the people that the page is for.

Holding the changeset to its unit does not give access. The host decides who can act on which unit.
The `EhOsContract.Authorizer` checks the capability and its scope.

**Text, as a form sends it.**

- Each value arrives as text. `Form` reads it as its declared type: an integer, a boolean, a
  decimal, a date or a timestamp.
- A blank field (`""`, or only spaces) is absent. If the field is required, this is an error. If it
  is optional, its value is `nil`.
- `Form` looks for the text of a select among the members of the enum. An unknown member is an
  error. `Form` does not make an atom from it.

**Rows, as `inputs_for` sends them.**

- A domain value with fields is a row. A list of such values is one row for each value.
- The rows arrive as a map with the index of each row as its key. `Form` reads them in the order of
  the indexes.
- Each row is a changeset of its own. `<.inputs_for>` shows it with its own errors. A problem of a
  field is at that field. An invariant of the value as a whole is on the `:base` of the row.
- `Form` reads a row that the form sends as a whole. A field of the row that the page did not show
  is absent. It does not come from `data:`.
- A checkbox group or a list sends a blank item, so that the field arrives when the person chooses
  nothing. `Form` drops this item. A list with no rows is an empty list.
- `Form` does not read `items_sort[]` and `items_drop[]` of Phoenix. If the page adds, removes or
  sorts rows, it changes the params that it gives to `Form`.

**A field that the params leave out keeps its value from `data:`.**

- An edit form does not have to show each field. A field that is not in the params keeps the value
  that the page gave it, and so do its rows.
- A field in the params, also a blank one, comes from the params. A `<select multiple>`, or a
  checkbox, sends nothing when the person chooses nothing. So it needs a hidden blank input to clear
  the value in `data:`. `<.input type="checkbox">` shows one.
- A field that the page does not show is not protected: params that carry it set it. Put a value
  that the page decides into the struct, after `to_struct/1`.

**Each change sends each row.** A LiveView reads the whole form on each `phx-change`. Limit the size
of what a form can send, where the host gets it: the `max_frame_size` of the socket, and the
`length` of the parser.

**A timestamp needs its offset.** `Form` reads a `:timestamp` from ISO 8601 text with its offset,
for example `2026-08-14T09:30:00Z`. `<input type="datetime-local">` sends no seconds and no offset,
so its text is not a timestamp. Add them in the page, or make the field a `:date`.

**Some fields do not come from the person.**

- A field that the host supplies (`supplied_by: :host`): the page fills it in `data:`, or gives
  `supply: true` to `dispatch/3`. Then dispatch asks the `EhOsContract.Supplier`.
- An identity that dispatch generates, for a unit that the command creates.
- The identity in `data:`. `Form` ignores the identity in the params, and does not show it back
  from them. Only the identity is kept this way. Another field in `data:` is a first value that the
  person can change.

**Some errors are not at an input.** A problem at a field that the form did not send goes on
`:base`. Its `field:` names the field. Examples: the identity in `data:`, a field that the host
supplies, or a field of rows, at which `inputs_for` shows nothing. So the page never shows it at an
input that is not there. If a command has a field with the name `base`, the field shares that key
with the errors of the whole form.

**Some refusals put no error on the changeset.** Each refusal other than a problem of a field and a
rejection belongs to no field. Examples: a missing capability, a conflict with another command, a
field that the host did not supply, an erased subject.

The page tells the person about them from the reason that `dispatch/3` returned, as `notice/2`
above does. `t:EhOsContract.refusal/0` lists these reasons. A rejection is an
`EhOsContract.Rejection`.

## Next steps

- [How is a call authorized?](authorization.md): how dispatch decides if the person can issue the command.
- [What are the units that decide?](units.md): the invariants of a unit, and the rejections.
- [What are read models and queries?](reading.md): the queries that a search form asks.
- [What are actors, values, entities and external systems?](domain-data.md): the values whose
  invariants the changeset checks.

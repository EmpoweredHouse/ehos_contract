# Forms: issuing a command from a page

This page covers how a page lets a person issue a command: a form checked while they type, with the
rules the contract states, and dispatch's refusal put back on the form when they submit it.

<!-- covers: entities contract.aggregate.command -->

A command declares its fields: which are required, their types, the domain's enums and values, and
the invariants of those values. Dispatch holds every command to that declaration. A form has to hold
what a person typed to the same rules, before it is sent, and say which field is wrong.
`EhOsContract.Form` builds the form's `Ecto.Changeset` from the command's declaration, so the rules are
written once, in the contract.

## The rule, from both sides

- **The contract holds the rules.** A required field, a type, an enum's members, a domain value's
  invariant, a unit's invariant and a command's constraint are declared in the domain and the contract,
  and nowhere else.
- **The changeset checks the shape of the input, and nothing more.** It asks whether each field the
  command needs is there, whether each value is of its declared type, and whether a domain value keeps
  its own invariants: a billing period written `YYYY-MM`, an amount that is not negative. Those it asks
  of the domain, as dispatch asks them.
- **A form never copies an invariant.** A unit's invariants and a command's constraints need the unit's
  history, which only dispatch reads. They reach the form as dispatch's refusal, which
  `EhOsContract.Form.refused/3` puts back on it. Writing one again as a validation in the page makes a
  second rule that can disagree with the first, and nothing fails when it does.

What stays the application's:

- the fields a form has that the command does not, a search box, a picker's query, "add another row",
  in a changeset of its own;
- every word a person reads. The engine puts its reason on each error and writes no message of its
  own, so the application says it in its client's language;
- how the page lays the form out, and what it says about a refusal that is no field's: a capability
  the person lacks, a failure to supply a field.

## An example

An accountant issues an invoice for a month. A period is a month written `YYYY-MM`, which is the
value's invariant, and an invoice is issued once, which is the unit's.

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

## The page

A LiveView builds the changeset on `mount` and on each `phx-change`, and dispatches on `phx-submit`.
The identity of the invoice is the page's, not the person's: it goes in `data:`, and a value the params
carry for it is ignored.

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

  with {:ok, command} <- EhOsContract.Form.to_command(changeset),
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
      changeset = EhOsContract.Form.refused(changeset, reason, at: [issued_once: :period])
      {:noreply, assign(socket, :form, to_form(changeset))}
  end
end

defp data(socket), do: %{invoice_id: socket.assigns.invoice_id}
```

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

The words are the application's. Its error helper reads the engine's reason from each error, not the
message:

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

## What a form reads, and what it does not

- **Text, as a form sends it.** Every value arrives as text and is read as its declared type, an
  integer, a boolean, a decimal, a date or a timestamp. A field left blank (`""`, or only spaces) is
  absent: a required one is an error, an optional one is nil. A select's text is found among an enum's
  members, and an unknown one is an error; no atom is created from it.
- **Rows, as `inputs_for` sends them.** A list arrives as a map keyed by the rows' indices, and is read
  in their order. In this version a domain value with fields, or a list of them, is checked whole: a
  problem anywhere inside it is an error at the field that holds it.
- **Not a field the host supplies** (`supplied_by: :host`), which `EhOsContract.Supplier` gives at
  dispatch; **not an identity dispatch generates** for a unit the command creates; and **not the
  identity in `data:`**, whatever the params say about it.

## The errors

Each error carries the engine's reason in its keyword list:

| Error | When |
| --- | --- |
| `{"can't be blank", validation: :required}` | A required field is missing or blank |
| `{"is invalid", validation: :type}` | A value is not of its declared type, or not one of an enum's members |
| `{"is invalid", validation: :invariant, invariant: name}` | A domain value breaks its invariant `name` |
| `{"does not exist", validation: :unknown}` | Dispatch found no entity the field names (`refused/3`) |
| `{"was refused", validation: :rejected, invariant: name}` | Dispatch refused on the unit's invariant or the command's constraint `name`, at the field `at:` names, or at `:base` (`refused/3`) |

Any other refusal, a capability the person lacks, an idempotency key used for another command, the
host failing to supply a field, puts no error on the changeset: none of them is a field's, and the page
says it from the reason `dispatch/3` answered.

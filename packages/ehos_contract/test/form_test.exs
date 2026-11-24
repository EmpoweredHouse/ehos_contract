defmodule EhosContract.FormTest do
  @moduledoc """
  #474: a form's changeset, built from a command's declaration and checked with the rules
  dispatch applies, so an application writes none of them a second time.
  """

  use ExUnit.Case, async: true

  alias EhosContract.Form
  alias FormRig.Domain.Values.{Address, Line}
  alias FormRig.Invoicing
  alias FormRig.Invoicing.Commands.IssueInvoice

  @sent %{
    "period" => "2026-07",
    "amount" => "120.50",
    "lines" => "2",
    "method" => "transfer",
    "due_on" => "2026-08-14",
    "paid" => "false",
    "sent_at" => "",
    "note" => "   "
  }

  defp changeset(params, opts \\ [data: %{invoice_id: "i-1"}]),
    do: Form.changeset(Invoicing, IssueInvoice, params, opts)

  describe "changeset/4" do
    test "reads every field from the text a form sends, and is valid when all of it fits" do
      changeset = changeset(@sent)

      assert changeset.valid?
      assert changeset.errors == []

      assert {:ok, %IssueInvoice{} = command} = Form.to_struct(changeset)

      assert command == %IssueInvoice{
               invoice_id: "i-1",
               period: "2026-07",
               amount: Decimal.new("120.50"),
               lines: 2,
               method: :transfer,
               due_on: ~D[2026-08-14],
               paid: false,
               sent_at: nil,
               note: nil
             }
    end

    test "puts each problem at its field, with the engine's reason and no words of its own" do
      changeset =
        changeset(%{
          @sent
          | "period" => "July",
            "amount" => "",
            "lines" => "two",
            "method" => "cheque"
        })

      refute changeset.valid?

      assert changeset.errors == [
               period: {"is invalid", [validation: :invariant, invariant: :written_as_month]},
               amount: {"can't be blank", [validation: :required]},
               lines: {"is invalid", [validation: :type]},
               method: {"is invalid", [validation: :type]}
             ]
    end

    test "keeps what the person typed, so the form shows it back beside its error" do
      changeset = changeset(%{@sent | "lines" => "two"})

      assert changeset.params["lines"] == "two"
      refute Map.has_key?(changeset.changes, :lines)
      assert changeset.changes.amount == Decimal.new("120.50")
    end

    test "types its fields from the declaration, an enum with its members" do
      types = changeset(@sent).types

      assert types.period == :string
      assert types.amount == :decimal
      assert types.lines == :integer
      assert types.due_on == :date
      assert types.paid == :boolean
      assert types.sent_at == EhosContract.EctoTypes.Timestamp

      assert Ecto.Type.cast(types.method, "card") == {:ok, :card}
      assert {:error, _not_a_member} = Ecto.Type.cast(types.method, "cheque")
    end

    test "reads params keyed by atoms as a form's, and creates no atom for a member's text" do
      assert changeset(Map.new(@sent, fn {k, v} -> {String.to_atom(k), v} end)).valid?

      text = "not_a_member_#{System.unique_integer([:positive])}"
      refute changeset(%{@sent | "method" => text}).valid?
      assert_raise ArgumentError, fn -> String.to_existing_atom(text) end
    end
  end

  describe "the identity" do
    test "comes from data:, and a value the params carry for it is ignored, and not shown" do
      changeset = changeset(Map.put(@sent, "invoice_id", "i-other"))

      assert {:ok, %IssueInvoice{invoice_id: "i-1"}} = Form.to_struct(changeset)
      refute Map.has_key?(changeset.params, "invoice_id")
    end

    test "is read from the params when data: holds none, as any other field" do
      assert {:ok, %IssueInvoice{invoice_id: "i-9"}} =
               Form.to_struct(changeset(Map.put(@sent, "invoice_id", "i-9"), []))

      assert [invoice_id: {"can't be blank", [validation: :required]}] =
               changeset(@sent, []).errors
    end

    test "a generated one is left to dispatch, whatever the params carry" do
      changeset =
        Form.changeset(
          BoundaryRig.Waitlist,
          BoundaryRig.Waitlist.Commands.JoinWaitlist,
          %{"entry_id" => "made-up", "course_id" => "c-1", "student_id" => "s-1"}
        )

      assert {:ok, %{entry_id: nil, course_id: "c-1", student_id: "s-1"}} =
               Form.to_struct(changeset)
    end
  end

  test "a field the host supplies is not read from the params" do
    changeset =
      Form.changeset(
        SupplyRig.Desk,
        SupplyRig.Desk.Commands.CloseVisit,
        %{"code" => "A1", "reported" => "true"},
        data: %{visit_id: "v-1"}
      )

    assert {:ok, %{visit_id: "v-1", code: "A1", reported: nil}} = Form.to_struct(changeset)
  end

  test "a domain value's invariant is asked as dispatch asks it, through the domain" do
    params = %{"amount" => "0"}

    assert [amount: {"is invalid", [validation: :invariant, invariant: :positive]}] =
             Form.changeset(ValueRig.Till, ValueRig.Till.Commands.PayIn, params,
               data: %{till_id: "till-1"}
             ).errors
  end

  describe "rows: a domain value with fields, one or a list" do
    @items %{
      "1" => %{"title" => "VAT", "quantity" => "0", "_persistent_id" => "1"},
      "0" => %{"title" => "", "quantity" => "two", "_persistent_id" => "0"},
      "2" => %{"title" => "Payroll", "quantity" => "3", "_persistent_id" => "2"}
    }

    test "puts each row's problems in that row, in the order of their indices" do
      changeset = changeset(Map.put(@sent, "items", @items))

      refute changeset.valid?
      assert changeset.errors == []

      assert [first, second, third] = changeset.changes.items

      assert first.errors == [
               title: {"can't be blank", [validation: :required]},
               quantity: {"is invalid", [validation: :type]}
             ]

      assert second.errors == [
               base: {"is invalid", [validation: :invariant, invariant: :counted]}
             ]

      assert third.valid?

      assert Ecto.Changeset.traverse_errors(changeset, fn {message, _keys} -> message end) == %{
               items: [
                 %{title: ["can't be blank"], quantity: ["is invalid"]},
                 %{base: ["is invalid"]},
                 %{}
               ]
             }
    end

    test "gives the command the rows as the structs its field carries" do
      items = %{
        "0" => %{"title" => "VAT", "quantity" => "1"},
        "1" => %{"title" => "Payroll", "quantity" => "3"}
      }

      address = %{"street" => "Main 1", "city" => ""}

      assert {:ok, %IssueInvoice{} = command} =
               Form.to_struct(
                 changeset(Map.merge(@sent, %{"items" => items, "billing_address" => address}))
               )

      assert command.items == [
               %Line{title: "VAT", quantity: 1},
               %Line{title: "Payroll", quantity: 3}
             ]

      assert command.billing_address == %Address{street: "Main 1", city: nil}
    end

    test "starts an edit form's rows from data:, and keeps them when the params leave the field out" do
      data = %{invoice_id: "i-1", items: [%Line{title: "VAT", quantity: 2}], note: "kept"}
      changeset = changeset(Map.delete(@sent, "note"), data: data)

      assert changeset.valid?
      assert [%Ecto.Changeset{data: %{title: "VAT", quantity: 2}}] = changeset.changes.items

      assert {:ok, %{items: [%Line{title: "VAT", quantity: 2}], note: "kept"}} =
               Form.to_struct(changeset)
    end

    test "a list that is no rows is the field's error, and an optional one sent blank is cleared" do
      assert [items: {"is invalid", [validation: :type]}] =
               changeset(Map.put(@sent, "items", "VAT")).errors

      assert {:ok, %{items: [], billing_address: nil}} =
               Form.to_struct(
                 changeset(Map.merge(@sent, %{"items" => "", "billing_address" => ""}))
               )
    end

    test "a value data: holds is shown as rows whatever the form sent, and cleared when sent blank" do
      held = %{
        invoice_id: "i-1",
        billing_address: %Address{street: "Main 1", city: nil},
        items: [%Line{title: "VAT", quantity: 2}]
      }

      for params <- [@sent, Map.merge(@sent, %{"items" => "x", "billing_address" => "y"})] do
        changeset = changeset(params, data: held)
        form = Phoenix.HTML.FormData.to_form(changeset, action: :validate)

        assert [_row] = Phoenix.HTML.FormData.to_form(changeset, form, :items, [])
        assert [_address] = Phoenix.HTML.FormData.to_form(changeset, form, :billing_address, [])
      end

      cleared = changeset(Map.merge(@sent, %{"items" => "", "billing_address" => ""}), data: held)
      assert {:ok, %{items: [], billing_address: nil}} = Form.to_struct(cleared)
    end

    test "an empty list of rows data: holds stays empty when the params leave it out" do
      changeset = changeset(@sent, data: %{invoice_id: "i-1", items: []})

      assert changeset.valid?
      assert {:ok, %{items: []}} = Form.to_struct(changeset)
    end

    # #486: data: holds the value's struct, as a read model's Row loads it; a map with
    # its keys is refused, as dispatch refuses one.
    test "a row data: holds is the value's struct, and a map in its place is refused" do
      address = %Address{street: "Main 1", city: nil}

      assert {:ok, %{billing_address: ^address}} =
               Form.to_struct(
                 changeset(@sent, data: %{invoice_id: "i-1", billing_address: address})
               )

      assert_raise ArgumentError, ~r/data: needs a value its field's type/, fn ->
        changeset(@sent,
          data: %{invoice_id: "i-1", billing_address: %{street: "Main 1", city: nil}}
        )
      end
    end

    test "a list sent with no rows is an empty list, and a blank item among rows is dropped" do
      for items <- [%{}, [""], ["", %{"title" => "VAT", "quantity" => "1"}]] do
        assert {:ok, %{items: rows}} = Form.to_struct(changeset(Map.put(@sent, "items", items)))
        assert rows in [[], [%Line{title: "VAT", quantity: 1}]]
      end
    end

    test "a refusal at a field of rows goes on the whole form, which inputs_for shows" do
      changeset =
        changeset(Map.put(@sent, "items", %{"0" => %{"title" => "VAT", "quantity" => "1"}}))
        |> Form.refused({:invalid, [items: :unknown, lines: :type]})

      assert changeset.errors == [
               base: {"does not exist", [validation: :unknown, field: :items]},
               lines: {"is invalid", [validation: :type]}
             ]
    end

    test "inputs_for shows each row with its own errors, named as the form sends them back" do
      changeset = changeset(Map.put(@sent, "items", @items))
      form = Phoenix.HTML.FormData.to_form(changeset, action: :validate)

      assert form.name == "issue_invoice"

      rows = Phoenix.HTML.FormData.to_form(changeset, form, :items, [])

      assert Enum.map(rows, & &1.name) ==
               ["issue_invoice[items][0]", "issue_invoice[items][1]", "issue_invoice[items][2]"]

      assert [[title: _, quantity: _], [base: _], []] = Enum.map(rows, & &1.errors)
      assert Phoenix.HTML.FormData.input_value(hd(rows).source, hd(rows), :quantity) == "two"

      [address] = Phoenix.HTML.FormData.to_form(changeset, form, :billing_address, [])
      assert address.name == "issue_invoice[billing_address]"
    end
  end

  describe "a recorded event and a query" do
    test "an event an actor records is read and checked as a command is, for record/3" do
      event = ValueRig.Till.Events.Counted

      changeset =
        Form.changeset(ValueRig.Till, event, %{"amount" => "250"}, data: %{till_id: "till-1"})

      assert {:ok, %ValueRig.Till.Events.Counted{till_id: "till-1", amount: 250}} =
               Form.to_struct(changeset)

      assert [amount: {"is invalid", [validation: :invariant, invariant: :positive]}] =
               Form.changeset(ValueRig.Till, event, %{"amount" => "0"},
                 data: %{till_id: "till-1"}
               ).errors
    end

    test "a query's params are its fields, for query/3, with no identity" do
      query = ValueRig.Till.Queries.PaymentsAbove

      assert {:ok, %ValueRig.Till.Queries.PaymentsAbove{above: 100}} =
               Form.to_struct(Form.changeset(ValueRig.Till, query, %{"above" => " 100 "}))

      assert [above: {"is invalid", [validation: :invariant, invariant: :positive]}] =
               Form.changeset(ValueRig.Till, query, %{"above" => "0"}).errors

      assert [above: {"can't be blank", [validation: :required]}] =
               Form.changeset(ValueRig.Till, query, %{"above" => ""}).errors
    end
  end

  describe "by a capability's name" do
    defp capability(contract, kind, name) do
      contract
      |> EhosContract.Model.fetch()
      |> EhosContract.Model.capabilities()
      |> Enum.find_value(fn
        {capability, %{kind: ^kind, name: ^name}} -> capability
        _other -> nil
      end)
    end

    @contracts [Invoicing, ValueRig.Till]

    test "builds the same changeset as the module would, for a command, a recording and a query" do
      issue = capability(Invoicing, :command, :issue_invoice)

      assert Form.changeset({:command, issue}, @sent,
               contracts: @contracts,
               data: %{invoice_id: "i-1"}
             ) ==
               changeset(@sent)

      # A person's recording: the registrar's; a system actor's, the counter's, has no name.
      confirmed = capability(BoundaryRig.Waitlist, :record, :place_confirmed)

      assert {:ok, %BoundaryRig.Waitlist.Events.PlaceConfirmed{entry_id: "e-1"}} =
               Form.changeset({:record, confirmed}, %{},
                 contracts: [BoundaryRig.Waitlist | @contracts],
                 data: %{entry_id: "e-1"}
               )
               |> Form.to_struct()

      above = capability(ValueRig.Till, :query, :payments_above)

      assert {:ok, %ValueRig.Till.Queries.PaymentsAbove{above: 100}} =
               Form.to_struct(
                 Form.changeset({:query, above}, %{"above" => "100"}, contracts: @contracts)
               )
    end

    test "raises for a name no contract declares as that kind" do
      issue = capability(Invoicing, :command, :issue_invoice)

      assert_raise ArgumentError, ~r/declares query/, fn ->
        Form.changeset({:query, issue}, %{}, contracts: @contracts)
      end

      assert_raise ArgumentError, ~r/declares command "nobody.nothing"/, fn ->
        Form.changeset({:command, "nobody.nothing"}, %{}, contracts: @contracts)
      end
    end
  end

  describe "to_struct/1" do
    test "answers an invalid changeset with the action that shows its errors" do
      assert {:error, %Ecto.Changeset{action: :insert, valid?: false}} =
               Form.to_struct(changeset(%{@sent | "amount" => ""}))
    end
  end

  describe "refused/3" do
    test "puts each of dispatch's field problems at its field, an unknown entity's too" do
      changeset =
        changeset(@sent)
        |> Form.refused(
          {:invalid,
           [period: {:invariant, :written_as_month}, invoice_id: :unknown, lines: :type]}
        )

      assert changeset.action == :insert
      refute changeset.valid?

      assert changeset.errors == [
               period: {"is invalid", [validation: :invariant, invariant: :written_as_month]},
               base: {"does not exist", [validation: :unknown, field: :invoice_id]},
               lines: {"is invalid", [validation: :type]}
             ]
    end

    test "puts a problem at a field the form never sent on the whole form, naming the field" do
      changeset =
        Form.changeset(
          SupplyRig.Desk,
          SupplyRig.Desk.Commands.CloseVisit,
          %{"code" => "A1"},
          data: %{visit_id: "v-1"}
        )
        |> Form.refused({:invalid, [reported: :required, visit_id: :unknown, code: :unknown]})

      assert changeset.errors == [
               base: {"can't be blank", [validation: :required, field: :reported]},
               base: {"does not exist", [validation: :unknown, field: :visit_id]},
               code: {"does not exist", [validation: :unknown]}
             ]
    end

    test "puts a rejection at the field at: names for its rule, or on the whole form" do
      rejection = %EhosContract.Rejection{invariant: :period_open}

      assert Form.refused(changeset(@sent), rejection, at: [period_open: :period]).errors == [
               period: {"was refused", [validation: :rejected, invariant: :period_open]}
             ]

      assert Form.refused(changeset(@sent), rejection).errors == [
               base: {"was refused", [validation: :rejected, invariant: :period_open]}
             ]
    end

    test "leaves what is no field's to the page, the action set so the form shows it" do
      for reason <- [:missing_capability, :idempotency_key_reused, {:not_supplied, :unavailable}] do
        changeset = Form.refused(changeset(@sent), reason)

        assert changeset.errors == []
        assert changeset.action == :insert
      end
    end

    test "keeps the errors the changeset already holds" do
      changeset =
        changeset(%{@sent | "lines" => "two"})
        |> Form.refused(%EhosContract.Rejection{invariant: :period_open})

      assert Keyword.keys(changeset.errors) == [:base, :lines]
    end

    test "raises when at: names a field the command does not have" do
      assert_raise ArgumentError, ~r/at: takes a keyword list/, fn ->
        Form.refused(changeset(@sent), %EhosContract.Rejection{invariant: :x}, at: [x: :customer])
      end
    end
  end

  describe "what it refuses" do
    test "a module that is not a contract, or not one of its commands" do
      assert_raise ArgumentError, ~r/is not a contract/, fn ->
        Form.changeset(FormRig.Domain, IssueInvoice, %{})
      end

      assert_raise ArgumentError, ~r/is not a command, a recorded event or a query of/, fn ->
        Form.changeset(Invoicing, ValueRig.Till.Commands.PayIn, %{})
      end

      # An event a command emits is no actor's to record.
      assert_raise ArgumentError, ~r/is not a command, a recorded event or a query of/, fn ->
        Form.changeset(ValueRig.Till, ValueRig.Till.Events.PaidIn, %{})
      end
    end

    test "data: holding what dispatch would refuse at a field the person never sees" do
      assert_raise ArgumentError, ~r/a value its field's type.*\[:invoice_id\]/, fn ->
        changeset(@sent, data: %{invoice_id: 42})
      end

      assert_raise ArgumentError, ~r/an identity dispatch generates.*\[:entry_id\]/, fn ->
        Form.changeset(BoundaryRig.Waitlist, BoundaryRig.Waitlist.Commands.JoinWaitlist, %{},
          data: %{entry_id: "e-1"}
        )
      end

      assert_raise ArgumentError,
                   ~r/the rest of an identity of several fields.*\[:shift_id\]/,
                   fn ->
                     Form.changeset(ValueRig.Till, ValueRig.Till.Commands.OpenDrawer, %{},
                       data: %{till_id: "t-1"}
                     )
                   end
    end

    test "data: naming a field the command does not have" do
      assert_raise ArgumentError, ~r/data: names \[:customer\]/, fn ->
        changeset(@sent, data: %{customer: "x"})
      end
    end
  end
end

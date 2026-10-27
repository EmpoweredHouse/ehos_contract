defmodule EhOsContract.FormTest do
  @moduledoc """
  #474: a form's changeset, built from a command's declaration and checked with the rules
  dispatch applies, so an application writes none of them a second time.
  """

  use ExUnit.Case, async: true

  alias EhOsContract.Form
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

      assert {:ok, %IssueInvoice{} = command} = Form.to_command(changeset)

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
      assert types.sent_at == :utc_datetime_usec

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
    test "comes from data:, and a value the params carry for it is ignored" do
      changeset = changeset(Map.put(@sent, "invoice_id", "i-other"))

      assert {:ok, %IssueInvoice{invoice_id: "i-1"}} = Form.to_command(changeset)
    end

    test "is read from the params when data: holds none, as any other field" do
      assert {:ok, %IssueInvoice{invoice_id: "i-9"}} =
               Form.to_command(changeset(Map.put(@sent, "invoice_id", "i-9"), []))

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
               Form.to_command(changeset)
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

    assert {:ok, %{visit_id: "v-1", code: "A1", reported: nil}} = Form.to_command(changeset)
  end

  test "a domain value's invariant is asked as dispatch asks it, through the domain" do
    params = %{"amount" => "0"}

    assert [amount: {"is invalid", [validation: :invariant, invariant: :positive]}] =
             Form.changeset(ValueRig.Till, ValueRig.Till.Commands.PayIn, params,
               data: %{till_id: "till-1"}
             ).errors
  end

  describe "to_command/1" do
    test "answers an invalid changeset with the action that shows its errors" do
      assert {:error, %Ecto.Changeset{action: :insert, valid?: false}} =
               Form.to_command(changeset(%{@sent | "amount" => ""}))
    end
  end

  describe "what it refuses" do
    test "a module that is not a contract, or not one of its commands" do
      assert_raise ArgumentError, ~r/is not a contract/, fn ->
        Form.changeset(FormRig.Domain, IssueInvoice, %{})
      end

      assert_raise ArgumentError, ~r/is not a command of/, fn ->
        Form.changeset(Invoicing, ValueRig.Till.Commands.PayIn, %{})
      end
    end

    test "data: naming a field the command does not have" do
      assert_raise ArgumentError, ~r/data: names \[:customer\]/, fn ->
        changeset(@sent, data: %{customer: "x"})
      end
    end
  end
end

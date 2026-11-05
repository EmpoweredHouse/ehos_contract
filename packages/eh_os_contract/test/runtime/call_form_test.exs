defmodule EhOsContract.CallFormTest do
  @moduledoc """
  #589: a page sends its form's params through `EhOsContract.call/3` with `form: true`, the
  door every caller with a credential uses, and `EhOsContract.Form` puts what it answers back
  on the changeset. On `FormRig.Invoicing`, and `SupplyRig.Desk` for a field the host supplies.
  """

  use EhOsContract.DataCase, async: false

  alias EhOsContract.{Actor, Event, Form, Receipt}
  alias FormRig.Domain.Values.Line
  alias FormRig.Invoicing
  alias FormRig.Invoicing.Commands.IssueInvoice

  @capability "form_rig.issue_invoice"
  @accountant Actor.credential("u-1", [@capability])
  @stranger Actor.credential("u-9", [])

  # As a LiveView form sends it: text at every level, blanks, and rows keyed by index.
  @sent %{
    "invoice_id" => "i-1",
    "period" => "2026-07",
    "amount" => "120.50",
    "lines" => "2",
    "method" => "transfer",
    "due_on" => "2026-08-14",
    "paid" => "false",
    "sent_at" => "",
    "note" => "   ",
    "items" => %{
      "1" => %{"title" => "Audit", "quantity" => "1"},
      "0" => %{"title" => "Review", "quantity" => "3", "_persistent_id" => "0"}
    }
  }

  defp issue(params, actor \\ @accountant, opts \\ []),
    do: EhOsContract.call({:command, @capability}, params, [actor: actor] ++ opts)

  defp repo, do: Application.fetch_env!(:eh_os_contract, :repo)

  test "reads a form's params as Form reads them, and issues the command Form would build" do
    assert {:ok, %Receipt{duplicate: false}} = issue(@sent, @accountant, form: true)

    changeset = Form.changeset(Invoicing, IssueInvoice, @sent, data: %{invoice_id: "i-1"})
    {:ok, built} = Form.to_struct(changeset)

    assert built == %IssueInvoice{
             invoice_id: "i-1",
             period: "2026-07",
             amount: Decimal.new("120.50"),
             lines: 2,
             method: :transfer,
             due_on: ~D[2026-08-14],
             paid: false,
             sent_at: nil,
             note: nil,
             items: [%Line{title: "Review", quantity: 3}, %Line{title: "Audit", quantity: 1}],
             billing_address: nil
           }

    assert [
             %Event{
               type: "form_rig.invoicing.invoice_issued",
               stream_id: "invoice:i-1",
               payload: payload
             }
           ] =
             repo().all(Event)

    assert payload == %{
             "invoice_id" => "i-1",
             "period" => "2026-07",
             "amount" => "120.50",
             "lines" => 2,
             "method" => "transfer",
             "due_on" => "2026-08-14",
             "paid" => false,
             "sent_at" => nil,
             "note" => nil,
             "items" => [
               %{"title" => "Review", "quantity" => 3},
               %{"title" => "Audit", "quantity" => 1}
             ],
             "billing_address" => nil
           }
  end

  test "without form: true, the same params are read as JSON, and the text does not fit" do
    assert {:error, {:invalid, problems}} = issue(@sent)

    assert Enum.sort(problems) == [items: :type, lines: :type, paid: :type, sent_at: :type]
    assert repo().all(Event) == []
  end

  test "asks the Authorizer before it reads the fields, as for any other caller" do
    assert issue(%{"invoice_id" => "i-1", "lines" => "two"}, @stranger, form: true) ==
             {:error, :missing_capability}

    assert issue(@sent, @stranger, form: true) == {:error, :missing_capability}
  end

  test "refuses a field the host supplies in a form's params, takes it blank as absent, and asks the Supplier" do
    clerk = Actor.credential("u-1", ["supply_rig.close_visit"])
    close = &EhOsContract.call({:command, "supply_rig.close_visit"}, &1, actor: clerk, form: true)

    assert close.(%{"visit_id" => "v-1", "code" => "A1", "reported" => "false"}) ==
             {:error, {:invalid, [reported: :supplied]}}

    assert {:ok, %Receipt{}} = close.(%{"visit_id" => "v-1", "code" => "A1", "reported" => " "})
    assert [%{payload: %{"code" => "A1", "reported" => true}}] = repo().all(Event)
  end

  test "records an event and asks a query from a form's params" do
    clerk =
      Actor.credential(
        "u-1",
        [
          "dispatch_rig.open_account",
          "dispatch_rig.balance_confirmed",
          "dispatch_rig.balances_for_branch"
        ],
        %{"dispatch_rig.balances_for_branch" => %{"branch_id" => ["b-7"]}}
      )

    call = &EhOsContract.call(&1, &2, actor: clerk, form: true)

    assert {:ok, %Receipt{}} =
             call.({:command, "dispatch_rig.open_account"}, %{
               "account_id" => "a-1",
               "branch_id" => "b-7"
             })

    assert {:ok, %Receipt{}} =
             call.({:record, "dispatch_rig.balance_confirmed"}, %{"account_id" => "a-1"})

    assert {:ok, [%{account_id: "a-1"}]} =
             call.({:query, "dispatch_rig.balances_for_branch"}, %{"branch_id" => "b-7"})
  end

  test "asks the Authorizer with the scope under either key, when another field does not decode" do
    move = "dispatch_rig.move_account"
    clerk = Actor.credential("u-1", [move], %{move => %{"branch_id" => ["b-7"]}})
    call = &EhOsContract.call({:command, move}, &1, actor: clerk, form: true)

    # An identifier sent as rows does not decode, so the scope is read as it was sent.
    for branch_id <- [:branch_id, "branch_id"] do
      assert {:error, {:invalid, _problems}} =
               call.(%{branch_id => "b-7", "account_id" => %{"0" => "a-1"}})
    end

    assert call.(%{:branch_id => "b-9", "account_id" => %{"0" => "a-1"}}) ==
             {:error, :outside_scope}
  end

  describe "data:" do
    test "holds the form to its unit: the identity replaces what the params carry, under either key" do
      params = @sent |> Map.put("invoice_id", "i-other") |> Map.put(:invoice_id, "i-other")

      assert {:ok, %Receipt{}} =
               issue(params, @accountant, form: true, data: %{invoice_id: "i-1"})

      assert [%Event{stream_id: "invoice:i-1"}] = repo().all(Event)
    end

    test "gives each other field when the params leave it out, and the params win when they carry it" do
      data = %{
        invoice_id: "i-1",
        note: "Kept",
        method: :card,
        due_on: ~D[2026-09-01],
        items: [%Line{title: "Kept", quantity: 4}]
      }

      params = Map.drop(@sent, ["invoice_id", "note", "method", "items"])

      assert {:ok, %Receipt{}} = issue(params, @accountant, form: true, data: data)

      assert [%Event{payload: payload}] = repo().all(Event)

      assert Map.take(payload, ["note", "method", "due_on", "items"]) == %{
               "note" => "Kept",
               "method" => "card",
               "due_on" => "2026-08-14",
               "items" => [%{"title" => "Kept", "quantity" => 4}]
             }
    end

    test "is the page's, held as Form holds it, and refused by the field's name" do
      assert_raise ArgumentError, ~r/data: only with form: true/, fn ->
        issue(@sent, @accountant, data: %{invoice_id: "i-1"})
      end

      assert_raise ArgumentError, ~r/data: names \[:no_such_field\]/, fn ->
        issue(@sent, @accountant, form: true, data: %{no_such_field: 1})
      end

      assert_raise ArgumentError, ~r/a value its field's type.*\[:invoice_id\]/, fn ->
        issue(@sent, @accountant, form: true, data: %{invoice_id: 42})
      end

      # Checked whatever the params are.
      assert_raise ArgumentError, ~r/a value its field's type.*\[:invoice_id\]/, fn ->
        issue("not a map", @accountant, form: true, data: %{invoice_id: 42})
      end

      any = Actor.credential("u-1", ["boundary_rig.join_waitlist", "value_rig.open_drawer"])
      call = &EhOsContract.call({:command, &1}, %{}, actor: any, form: true, data: &2)

      assert_raise ArgumentError, ~r/an identity dispatch generates.*\[:entry_id\]/, fn ->
        call.("boundary_rig.join_waitlist", %{entry_id: "e-1"})
      end

      assert_raise ArgumentError,
                   ~r/the rest of an identity of several fields.*\[:shift_id\]/,
                   fn ->
                     call.("value_rig.open_drawer", %{till_id: "t-1"})
                   end

      clerk = Actor.credential("u-1", ["supply_rig.close_visit"])

      assert_raise ArgumentError, ~r/data: for \[:reported\], which the host supplies/, fn ->
        EhOsContract.call(
          {:command, "supply_rig.close_visit"},
          %{"visit_id" => "v-1", "code" => "A1"},
          actor: clerk,
          form: true,
          data: %{reported: true}
        )
      end
    end
  end

  describe "refused/3 on what call/3 answers" do
    defp changeset(params),
      do: Form.changeset(Invoicing, IssueInvoice, params, data: %{invoice_id: "i-1"})

    test "puts each field's problem at its field, and one at the identity on the whole form" do
      params = %{@sent | "amount" => "", "invoice_id" => ""}
      assert {:error, {:invalid, problems} = reason} = issue(params, @accountant, form: true)
      assert Enum.sort(problems) == [amount: :required, invoice_id: :required]

      # The page's changeset has the identity in data:, not in the params.
      changeset = Form.refused(changeset(Map.delete(params, "invoice_id")), reason)

      # Once: the changeset already holds the error call/3 gives back.
      assert Keyword.get_values(changeset.errors, :amount) ==
               [{"can't be blank", [validation: :required]}]

      assert Keyword.get_values(changeset.errors, :base) ==
               [{"can't be blank", [validation: :required, field: :invoice_id]}]
    end

    test "puts a domain value's broken invariant at its field, as the changeset does" do
      params = %{@sent | "period" => "July"}

      assert issue(params, @accountant, form: true) ==
               {:error, {:invalid, [period: {:invariant, :written_as_month}]}}

      changeset =
        Form.refused(changeset(params), {:invalid, [period: {:invariant, :written_as_month}]})

      assert Keyword.get_values(changeset.errors, :period) ==
               [{"is invalid", [validation: :invariant, invariant: :written_as_month]}]
    end

    test "leaves every answer that is no field's to the page, the action set" do
      reasons = [
        issue(@sent, @stranger, form: true),
        issue(@sent, nil, form: true),
        issue("not a map", @accountant, form: true),
        issue(@sent, @accountant, form: true, correlation_id: "not-a-uuid"),
        EhOsContract.call({:command, "form_rig.no_such_command"}, @sent,
          actor: @accountant,
          form: true
        )
      ]

      assert reasons == [
               {:error, :missing_capability},
               {:error, :no_actor},
               {:error, :not_an_object},
               {:error, :correlation_id_is_not_a_uuid},
               {:error, :not_found}
             ]

      for {:error, reason} <- reasons do
        changeset = Form.refused(changeset(@sent), reason)

        assert changeset.errors == []
        assert changeset.action == :insert
      end
    end
  end
end

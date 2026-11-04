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

  test "refuses a field the host supplies in a form's params, and asks the Supplier for it" do
    clerk = Actor.credential("u-1", ["supply_rig.close_visit"])
    close = &EhOsContract.call({:command, "supply_rig.close_visit"}, &1, actor: clerk, form: true)

    assert close.(%{"visit_id" => "v-1", "code" => "A1", "reported" => ""}) ==
             {:error, {:invalid, [reported: :supplied]}}

    assert {:ok, %Receipt{}} = close.(%{"visit_id" => "v-1", "code" => "A1"})
    assert [%{payload: %{"code" => "A1", "reported" => true}}] = repo().all(Event)
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

      assert Keyword.get_values(changeset.errors, :amount) ==
               [
                 {"can't be blank", [validation: :required]},
                 {"can't be blank", [validation: :required]}
               ]

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
               List.duplicate(
                 {"is invalid", [validation: :invariant, invariant: :written_as_month]},
                 2
               )
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

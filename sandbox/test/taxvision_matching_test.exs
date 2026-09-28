defmodule Taxvision.MatchingTest do
  @moduledoc """
  Matching a month's turnovers with KSeF's invoices, dispatched in the host (v2 plan,
  E9c-2): the integration records an invoice, the accountant uploads a statement,
  the policy issues one match per turnover (P6), and the pairing decides each (P7).
  """

  use Taxvision.DataCase, async: false

  alias EhOsContract.{Actor, Event, Testing}
  alias Taxvision.Contracts.{AccountingMonth, DocumentIntake}
  alias Taxvision.Contracts.AccountingMonth.Commands.IngestBankStatement
  alias Taxvision.Contracts.DocumentIntake.Events.InvoicePulledFromKsef

  @number "5265877635-20260814-0A1B2C3D4E5F-9A"

  defp accountant(company) do
    Actor.credential("u-accountant", ["taxvision.ingest_bank_statement"], %{
      "taxvision.ingest_bank_statement" => %{"company_id" => [company]}
    })
  end

  defp invoice!(company, number) do
    EhOsContract.record(
      DocumentIntake,
      %InvoicePulledFromKsef{
        company_id: company,
        period_id: "2026-08",
        ksef_number: number,
        amount_minor: 12_300,
        issued_on: ~D[2026-08-14]
      },
      actor: Actor.system(:ksef_integration)
    )
  end

  defp payloads(type),
    do:
      Repo.all(from(e in Event, where: e.type == ^type, order_by: e.position, select: e.payload))

  setup do
    Testing.drain()
    :ok
  end

  test "a statement of two turnovers: the one on the invoice's amount is paired, the other flagged" do
    assert {:ok, _} = invoice!("c-1", @number)

    assert {:ok, _} =
             EhOsContract.dispatch(
               AccountingMonth,
               %IngestBankStatement{
                 company_id: "c-1",
                 period_id: "2026-08",
                 turnovers: [
                   %{turnover_id: "t-1", amount_minor: 12_300, booked_on: ~D[2026-08-20]},
                   %{turnover_id: "t-2", amount_minor: 4_500, booked_on: ~D[2026-08-21]}
                 ]
               },
               actor: accountant("c-1")
             )

    Testing.drain()

    assert [%{"turnover_id" => "t-1", "ksef_number" => @number}] =
             payloads("accounting_month.turnover_matched_with_invoice")

    assert [%{"turnover_id" => "t-2"}] =
             payloads("accounting_month.turnover_without_invoice_flagged")
  end

  test "KSeF's number is held to its format: a number missing its checksum is not recorded" do
    assert {:error, {:invalid, [ksef_number: {:invariant, :ksef_format}]}} =
             invoice!("c-1", "5265877635-20260814-0A1B2C3D4E5F")

    assert payloads("ksef_intake.invoice_pulled_from_ksef") == []
  end
end

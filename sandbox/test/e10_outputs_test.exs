defmodule EhOsContractHost.E10OutputsTest do
  @moduledoc """
  Plan E10: the L5 output and the system graph are pinned on the real sandbox
  contracts, not only on invented engine fixtures.
  """

  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  test "check reports the proven in-transaction fan-out, and not a recorded-only contract" do
    Mix.Task.reenable("eh_os_contract.check")

    output = capture_io(fn -> Mix.Tasks.EhOsContract.Check.run([]) end)

    assert output =~
             "WARN  in-transaction-policy-fan-out: policy :match_each_turnover of " <>
               "Taxvision.Contracts.AccountingMonth"

    refute output =~
             "contract-without-implementation: Taxvision.Contracts.DocumentIntake"

    assert output =~ "eh_os_contract.check: 0 errors, 29 warnings, 9 notices"
  end

  test "TaxVision's public event is the only AsyncAPI message boundary" do
    document = EhOsContract.AsyncAPI.document(Taxvision.Contracts.AccountingMonth)

    assert %{
             "month_opened" => %{
               "address" => "taxvision.accounting_month.opened.v1"
             }
           } = document["channels"]

    assert %{
             "publish_month_opened" => %{
               "action" => "send",
               "channel" => %{"$ref" => "#/channels/month_opened"},
               "messages" => [
                 %{"$ref" => "#/channels/month_opened/messages/MonthOpened"}
               ]
             }
           } = document["operations"]

    assert %{"MonthOpened" => message} = document["components"]["messages"]
    assert message["x-eh-os-contract-source-event"] == "accounting_month_opened"
    assert message["x-eh-os-contract-idempotent-on"] == ["company_id", "period_id"]
    assert message["payload"]["required"] == ["company_id", "period_id"]
  end

  test "TaxVision's OpenAPI surface contains human commands but not policy commands" do
    document = EhOsContract.OpenAPI.document(Taxvision.Contracts.AccountingMonth)

    assert Map.has_key?(document["paths"], "/commands/taxvision.open_month")
    assert Map.has_key?(document["paths"], "/commands/taxvision.ingest_bank_statement")
    refute Map.has_key?(document["paths"], "/commands/taxvision.run_matching")

    operation = document["paths"]["/commands/taxvision.open_month"]["post"]
    assert operation["x-eh-os-contract-scope"] == "company_id"
    assert operation["x-eh-os-contract-roles"] == ["taxvision.accountant"]
  end

  @tag :tmp_dir
  test "the system graph connects TaxVision's contexts, contracts and publication", %{
    tmp_dir: dir
  } do
    path = Path.join(dir, "taxvision.mmd")
    Mix.Task.reenable("eh_os_contract.graph")

    Mix.Tasks.EhOsContract.Graph.run(~w(--system taxvision --output #{path}))

    graph = File.read!(path)

    assert graph =~ ~s|subgraph context_document_intake["Przyjmowanie dokumentów · context"]|

    assert graph =~
             "contract_taxvision_contracts_document_intake -->|invoice_pulled_from_ksef| " <>
               "contract_taxvision_contracts_accounting_month"

    assert graph =~
             "contract_taxvision_contracts_accounting_month -.->|publishes " <>
               "accounting_month_opened| publication_taxvision_accounting_month_opened_v1"
  end
end

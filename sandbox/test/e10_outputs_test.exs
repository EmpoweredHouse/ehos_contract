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

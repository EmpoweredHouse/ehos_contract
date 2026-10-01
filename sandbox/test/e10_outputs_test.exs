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

  # StatutoryReporting's policy scenarios start from ClinicalDocumentation's closing,
  # a sibling's event: its personal fields are declared there, not in the consumer.
  test "no exported model carries Rehmed's personal scenario values" do
    contracts = EhOsContract.Registry.contracts()
    assert Rehmed.Contracts.StatutoryReporting in contracts

    for contract <- contracts do
      encoded = contract |> EhOsContract.Model.to_data() |> Jason.encode!()

      for personal <- ["85010112345", "M54.5", "93.39"] do
        refute encoded =~ personal, "#{inspect(contract)} exports #{personal}"
      end
    end
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
                 %{
                   "$ref" =>
                     "#/channels/month_opened/messages/taxvision.accounting_month.opened.v1"
                 }
               ]
             }
           } = document["operations"]

    assert %{"taxvision.accounting_month.opened.v1" => message} =
             document["components"]["messages"]

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

  # The sandbox's `ehos.yaml` names TaxVision, since Rehmed is registered beside it.
  @tag :tmp_dir
  test "the manifest task extends ehos.yaml with TaxVision's command authority", %{tmp_dir: dir} do
    path = Path.join(dir, "taxvision.json")
    Mix.Task.reenable("eh_os_contract.manifest")

    output = capture_io(fn -> Mix.Tasks.EhOsContract.Manifest.run(["--output", path]) end)

    assert output =~ "written: #{path}"

    assert Jason.decode!(File.read!(path)) == %{
             "schema" => "ehos.manifest/v2",
             "ehos_yaml" => "ehos.yaml/v1",
             "application" => "taxvision",
             "engine" => %{"name" => "eh_os_contract", "version" => EhOsContract.version()},
             "serves" => [%{"name" => "web", "port" => 4010}],
             "health" => %{"port" => 4011, "ready" => "/health/ready", "live" => "/health/live"},
             "offers" => %{
               "capabilities" => [
                 %{
                   "name" => "taxvision.complete_company_profile",
                   "command" => "complete_company_profile",
                   "label" => "Uzupełnij profil firmy",
                   "process" => "client",
                   "principals" => ["human"]
                 },
                 %{
                   "name" => "taxvision.ingest_bank_statement",
                   "command" => "ingest_bank_statement",
                   "label" => "Wgraj wyciąg bankowy",
                   "process" => "accounting_month",
                   "principals" => ["human"]
                 },
                 %{
                   "name" => "taxvision.open_month",
                   "command" => "open_month",
                   "label" => "Otwórz miesiąc księgowy",
                   "process" => "accounting_month",
                   "principals" => ["human"]
                 },
                 %{
                   "name" => "taxvision.retrigger_verification",
                   "command" => "retrigger_verification",
                   "label" => "Ponów weryfikację",
                   "process" => "client",
                   "principals" => ["human"]
                 }
               ],
               "roles" => [
                 %{
                   "name" => "taxvision.accountant",
                   "label" => "Księgowa",
                   "capabilities" => [
                     "taxvision.complete_company_profile",
                     "taxvision.ingest_bank_statement",
                     "taxvision.open_month",
                     "taxvision.retrigger_verification"
                   ]
                 }
               ]
             }
           }
  end

  @tag :tmp_dir
  test "the manifest task refuses to guess between TaxVision and Rehmed", %{tmp_dir: dir} do
    unnamed = Path.join(dir, "ehos.yaml")
    File.write!(unnamed, String.replace(File.read!("ehos.yaml"), "application: taxvision\n", ""))

    for args <- [["--ehos-yaml", unnamed], ["--domain", "taxvision"]] do
      Mix.Task.reenable("eh_os_contract.manifest")
      output = ["--output", Path.join(dir, "manifest.json") | args]

      error = assert_raise Mix.Error, fn -> Mix.Tasks.EhOsContract.Manifest.run(output) end

      assert error.message =~ "application: <name>"
    end

    refute File.exists?(Path.join(dir, "manifest.json"))
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

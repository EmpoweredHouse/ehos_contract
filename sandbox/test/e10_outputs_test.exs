defmodule EhosContractHost.E10OutputsTest do
  @moduledoc """
  Plan E10: the L5 output and the system graph — today the domain's `graph.v1`
  document it is drawn from — are pinned on the real sandbox contracts, not only on
  invented engine fixtures.
  """

  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  test "check reports the proven in-transaction fan-out" do
    Mix.Task.reenable("ehos_contract.check")

    output = capture_io(fn -> Mix.Tasks.EhosContract.Check.run([]) end)

    assert output =~
             "WARN  in-transaction-policy-fan-out: policy :invoice_the_period of " <>
               "Billing.Contracts.Subscriptions"

    # The library (`Lending`) gives two notices, its contexts' words no term covers. The
    # billing (`Billing`) gives three warnings and two notices. The warnings: its fan-out
    # above, its monthly billing that never ends, which it holds on purpose, and the usage
    # it records, which only its own decisions read. The notices: its contexts' words no
    # term covers. The fulfilment (`Fulfilment`) gives three notices of the same kind, and
    # no warning. The clients' trees, which gave the rest, left for a private repository in
    # the publication programme's PB4 (#386).
    assert output =~ "ehos_contract.check: 0 errors, 3 warnings, 7 notices"
  end

  # The personal values the scenarios give: the library's member, and another's e-mail.
  @personal ["Ada Lovelace", "ada@example.org", "ada@example.net", "bob@example.org"]

  # The library's membership gives a member's name and e-mail to its query's scenario.
  test "no exported model carries a personal scenario value" do
    contracts = EhosContract.Registry.contracts()
    assert Lending.Contracts.Membership in contracts

    # The check is not empty: the contract does hold the value its export must not carry.
    assert inspect(EhosContract.Model.fetch(Lending.Contracts.Membership), limit: :infinity) =~
             "Ada Lovelace"

    for contract <- contracts do
      encoded = contract |> EhosContract.Model.to_data() |> Jason.encode!()

      for personal <- @personal do
        refute encoded =~ personal, "#{inspect(contract)} exports #{personal}"
      end
    end
  end

  # Plan DD, S3 (#256): a process module carries scenarios too. It is not exported yet
  # (P2e, #220), so its model is held to the same, as what an export will be made from.
  test "no process module's model carries a personal scenario value" do
    processes = EhosContract.Registry.processes()
    assert Lending.Processes.LateFee in processes

    for process <- processes do
      model = process |> EhosContract.Model.fetch() |> inspect(limit: :infinity)

      for personal <- @personal do
        refute model =~ personal, "#{inspect(process)} carries #{personal}"
      end
    end
  end

  test "billing's invoice is the only AsyncAPI message boundary" do
    document = EhosContract.AsyncAPI.document(Billing.Contracts.Subscriptions)

    assert %{"issued" => %{"address" => "billing.invoice.issued.v1"}} = document["channels"]

    assert %{
             "publish_issued" => %{
               "action" => "send",
               "channel" => %{"$ref" => "#/channels/issued"},
               "messages" => [%{"$ref" => "#/channels/issued/messages/billing.invoice.issued.v1"}]
             }
           } = document["operations"]

    assert %{"billing.invoice.issued.v1" => message} = document["components"]["messages"]

    assert message["x-ehos-contract-source-event"] == "issued"
    assert message["x-ehos-contract-idempotent-on"] == ["subscription_id", "period_id"]
    assert message["payload"]["required"] == ["period_id", "subscription_id", "total"]
  end

  test "the warehouse's OpenAPI surface: a picker's commands scoped, and none of the policy's" do
    document = EhosContract.OpenAPI.document(Fulfilment.Contracts.Warehouse)

    assert Map.has_key?(document["paths"], "/commands/fulfilment.confirm_pick")
    refute Map.has_key?(document["paths"], "/commands/fulfilment.open_pick_list")

    operation = document["paths"]["/commands/fulfilment.confirm_pick"]["post"]
    assert operation["x-ehos-contract-scope"] == "warehouse_id"
    assert operation["x-ehos-contract-roles"] == ["fulfilment.picker"]
  end

  # The sandbox's `ehos.yaml` names the invented `Billing`, the one domain that publishes
  # among the case studies registered beside it (publication programme, PB2, #369). The
  # capabilities are the commands a person issues; what only the monthly billing and the
  # policies issue has none.
  @tag :tmp_dir
  test "the manifest task extends ehos.yaml with billing's command authority", %{tmp_dir: dir} do
    path = Path.join(dir, "billing.json")
    Mix.Task.reenable("ehos_contract.manifest")

    output = capture_io(fn -> Mix.Tasks.EhosContract.Manifest.run(["--output", path]) end)

    assert output =~ "written: #{path}"

    capability = fn command, label ->
      %{
        "name" => "billing.#{command}",
        "command" => command,
        "label" => label,
        "principals" => ["human"]
      }
    end

    assert Jason.decode!(File.read!(path)) == %{
             "schema" => "ehos.manifest/v2",
             "ehos_yaml" => "ehos.yaml/v1",
             "application" => "billing",
             "engine" => %{"name" => "ehos_contract", "version" => EhosContract.version()},
             "serves" => [%{"name" => "web", "port" => 4010}],
             "health" => %{"port" => 4011, "ready" => "/health/ready", "live" => "/health/live"},
             "offers" => %{
               "capabilities" => [
                 capability.("cancel_subscription", "Cancel a subscription"),
                 capability.("close_billing_period", "Close a billing period"),
                 capability.("record_usage", "Record usage"),
                 capability.("start_subscription", "Start a subscription"),
                 capability.("write_off_payment", "Write a payment off")
               ],
               "roles" => [
                 %{
                   "name" => "billing.account_manager",
                   "label" => "Account manager",
                   "capabilities" => [
                     "billing.cancel_subscription",
                     "billing.close_billing_period",
                     "billing.record_usage",
                     "billing.start_subscription",
                     "billing.write_off_payment"
                   ]
                 }
               ]
             }
           }
  end

  @tag :tmp_dir
  test "the manifest task refuses to guess between the sandbox's domains", %{tmp_dir: dir} do
    unnamed = Path.join(dir, "ehos.yaml")
    named = File.read!("ehos.yaml")
    assert named =~ "application: billing\n"
    File.write!(unnamed, String.replace(named, "application: billing\n", ""))

    output = ["--output", Path.join(dir, "manifest.json")]

    assert refusal(output ++ ["--ehos-yaml", unnamed]) =~
             "domains with contracts; say which one this image is in ehos.yaml, as application: <name>"

    # --domain chose the domain before v2, and is refused before any file is read.
    assert refusal(output ++ ["--domain", "billing"]) =~ "--domain is gone"

    refute File.exists?(Path.join(dir, "manifest.json"))
  end

  defp refusal(args) do
    Mix.Task.reenable("ehos_contract.manifest")
    error = assert_raise Mix.Error, fn -> Mix.Tasks.EhosContract.Manifest.run(args) end
    error.message
  end

  @tag :tmp_dir
  test "the system graph connects billing's contexts, contracts and publication", %{
    tmp_dir: dir
  } do
    alias EhosContract.Graph.Document

    path = Path.join(dir, "billing.json")
    Mix.Task.reenable("ehos_contract.graph")

    Mix.Tasks.EhosContract.Graph.run(~w(--domain billing --output #{path}))

    graph = Jason.decode!(File.read!(path))
    contract = &Document.id([:contract, &1])
    subscriptions = contract.("billing.subscriptions")
    payments = contract.("billing.payments")

    assert %{"label" => "Payments"} =
             Enum.find(graph["nodes"]["context"], &(&1["name"] == "payments"))

    assert Enum.find(graph["nodes"]["contract"], &(&1["id"] == payments))["context"] ==
             Document.id([:context, Billing.Domain, :payments])

    between =
      Enum.find(
        graph["relations"]["consumed_by"],
        &(&1["from"] == subscriptions and &1["to"] == payments)
      )

    assert Enum.map(between["events"], & &1["event"]) == ["event:billing.subscriptions:issued"]

    publication = Document.id([:publication, Billing.Domain, "billing.invoice.issued.v1"])

    assert Enum.any?(
             graph["relations"]["publishes"],
             &(&1["from"] == subscriptions and &1["to"] == publication)
           )
  end
end

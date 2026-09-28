defmodule EhOsContract.OpenAPITest do
  @moduledoc """
  E10: the v2 model's human command and query surface as OpenAPI, with the same
  JSON Schema field projection as AsyncAPI.
  """

  use ExUnit.Case, async: true

  alias EhOsContract.OpenAPI

  test "only human command and query capabilities become paths" do
    document = OpenAPI.document(DispatchRig.Ledger)
    paths = document["paths"]

    assert document["openapi"] == "3.1.2"

    assert document["jsonSchemaDialect"] ==
             "https://spec.openapis.org/oas/3.1/dialect/base"

    assert document["security"] == [%{"bearerAuth" => []}]
    assert Map.has_key?(paths, "/commands/dispatch_rig.open_account")
    assert Map.has_key?(paths, "/queries/dispatch_rig.balances_for_branch")

    refute Map.has_key?(paths, "/commands/dispatch_rig.flag_account")
    refute Map.has_key?(paths, "/records/dispatch_rig.balance_confirmed")
  end

  test "a command path carries its closed request schema and authorization metadata" do
    operation =
      OpenAPI.document(DispatchRig.Ledger)["paths"][
        "/commands/dispatch_rig.open_account"
      ]["post"]

    schema = operation["requestBody"]["content"]["application/json"]["schema"]

    assert operation["operationId"] == "command_open_account"
    assert operation["x-eh-os-contract-capability"] == "dispatch_rig.open_account"
    assert operation["x-eh-os-contract-roles"] == ["dispatch_rig.clerk"]
    assert schema["required"] == ["account_id", "branch_id"]
    assert schema["additionalProperties"] == false
    assert schema["properties"]["account_id"]["x-eh-os-contract-type"] == "id"
  end

  test "a creating command omits its generated identity and requires an idempotency key" do
    operation =
      OpenAPI.document(BoundaryRig.Waitlist)["paths"][
        "/commands/boundary_rig.join_waitlist"
      ]["post"]

    schema = operation["requestBody"]["content"]["application/json"]["schema"]
    idempotency = Enum.find(operation["parameters"], &(&1["name"] == "idempotency-key"))

    assert schema["required"] == ["course_id", "student_id"]
    refute Map.has_key?(schema["properties"], "entry_id")
    assert idempotency["required"]
  end

  test "a scoped query carries typed parameters and its read-model response" do
    operation =
      OpenAPI.document(DispatchRig.Ledger)["paths"][
        "/queries/dispatch_rig.balances_for_branch"
      ]["get"]

    assert operation["x-eh-os-contract-scope"] == "branch_id"
    assert operation["x-eh-os-contract-roles"] == ["dispatch_rig.clerk"]

    assert [parameter] = operation["parameters"]
    assert parameter["name"] == "branch_id"
    assert parameter["in"] == "query"
    assert parameter["required"]
    assert parameter["schema"]["x-eh-os-contract-type"] == "id"

    response = operation["responses"]["200"]["content"]["application/json"]["schema"]
    rows = response["properties"]["rows"]
    assert rows["type"] == "array"
    assert rows["items"]["required"] == ["account_id", "balance", "branch_id"]
  end

  test "domain values retain both their wire schema and DSL type" do
    operation =
      OpenAPI.document(ValueRig.Till)["paths"]["/commands/value_rig.pay_in"]["post"]

    schema = operation["requestBody"]["content"]["application/json"]["schema"]

    assert schema["properties"]["amount"] == %{
             "type" => "integer",
             "x-eh-os-contract-type" => "amount"
           }

    assert schema["properties"]["payment"] == %{
             "anyOf" => [
               %{
                 "type" => "object",
                 "properties" => %{
                   "amount" => %{
                     "type" => "integer",
                     "x-eh-os-contract-type" => "amount"
                   },
                   "note" => %{
                     "anyOf" => [
                       %{"type" => "string", "x-eh-os-contract-type" => "string"},
                       %{"type" => "null"}
                     ]
                   }
                 },
                 "required" => ["amount"],
                 "additionalProperties" => false,
                 "x-eh-os-contract-type" => "payment"
               },
               %{"type" => "null"}
             ]
           }
  end

  test "the digest is stable and ignores its own stored value" do
    document = OpenAPI.document(DispatchRig.Ledger)
    digest = document["info"]["x-eh-os-contract-digest"]
    tampered = put_in(document, ["info", "x-eh-os-contract-digest"], "0000deadbeef")

    assert byte_size(digest) == 12
    assert OpenAPI.digest(document) == digest
    assert OpenAPI.digest(tampered) == digest
  end
end

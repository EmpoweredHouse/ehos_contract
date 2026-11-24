defmodule EhosContract.OpenAPITest do
  @moduledoc """
  E10: the v2 model's human command and query surface as OpenAPI, with the same
  JSON Schema field projection as AsyncAPI.
  """

  use ExUnit.Case, async: true

  alias EhosContract.OpenAPI

  defmodule ListQuery do
    @moduledoc false
    use EhosContract.Contract,
      domain: DispatchRig.Domain,
      context: :ledger,
      id: "dispatch_rig.list_query"

    aggregate :account, "Account" do
      identity :account_id
      event :account_seen, "Account seen", recorded_by: :auditor
    end

    read_model :accounts, "Accounts", projects: :account_seen do
      field :account_id, :id
    end

    query :selected_accounts, "Selected accounts", reads: :accounts, by: :auditor do
      param :account_ids, {:list, :id}
    end
  end

  defmodule PersonalRows do
    @moduledoc false
    use EhosContract.Contract,
      domain: ShreddingRig.Domain,
      context: :membership,
      id: "shredding_rig.personal_rows"

    aggregate :profile, "Profile" do
      identity :profile_id

      event :profile_seen, "Profile seen", recorded_by: :clerk do
        field :member_id, :id, subject: :member
        field :name, :string, personal: :member_id
      end
    end

    read_model :profiles, "Profiles", projects: :profile_seen do
      field :profile_id, :id
      field :member_id, :id, subject: :member
      field :name, :string, personal: :member_id
    end

    query :profiles, "Profiles", reads: :profiles, by: :clerk do
      param :contact, :contact, optional: true
    end
  end

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
    assert operation["x-ehos-contract-capability"] == "dispatch_rig.open_account"
    assert operation["x-ehos-contract-roles"] == ["dispatch_rig.clerk"]
    assert schema["required"] == ["account_id", "branch_id"]
    assert schema["additionalProperties"] == false
    assert schema["properties"]["account_id"]["x-ehos-contract-type"] == "id"
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

    assert operation["x-ehos-contract-scope"] == "branch_id"
    assert operation["x-ehos-contract-roles"] == ["dispatch_rig.clerk"]

    assert [parameter] = operation["parameters"]
    assert parameter["name"] == "branch_id"
    assert parameter["in"] == "query"
    assert parameter["required"]
    assert parameter["style"] == "form"
    assert parameter["explode"]
    assert parameter["schema"]["x-ehos-contract-type"] == "id"

    response = operation["responses"]["200"]["content"]["application/json"]["schema"]
    rows = response["properties"]["rows"]
    assert rows["type"] == "array"
    assert rows["items"]["required"] == ["account_id", "balance", "branch_id"]
  end

  test "a list query parameter uses repeated form keys" do
    operation =
      OpenAPI.document(ListQuery)["paths"][
        "/queries/dispatch_rig.selected_accounts"
      ]["get"]

    assert [parameter] = operation["parameters"]
    assert parameter["name"] == "account_ids"
    assert parameter["style"] == "form"
    assert parameter["explode"]
    assert parameter["schema"]["type"] == "array"
  end

  test "an erased personal value remains a required row key but admits null" do
    operation =
      OpenAPI.document(PersonalRows)["paths"]["/queries/shredding_rig.profiles"]["get"]

    row = operation["responses"]["200"]["content"]["application/json"]["schema"]
    row = row["properties"]["rows"]["items"]

    assert "name" in row["required"]

    assert row["properties"]["name"]["anyOf"] == [
             %{
               "type" => "string",
               "x-ehos-contract-personal" => "member_id",
               "x-ehos-contract-type" => "string"
             },
             %{"type" => "null"}
           ]
  end

  test "a structured query parameter uses Plug-compatible deep-object keys" do
    operation =
      OpenAPI.document(PersonalRows)["paths"]["/queries/shredding_rig.profiles"]["get"]

    assert [parameter] = operation["parameters"]
    assert parameter["name"] == "contact"
    assert parameter["style"] == "deepObject"
    assert parameter["explode"]
  end

  test "domain values retain both their wire schema and DSL type" do
    operation =
      OpenAPI.document(ValueRig.Till)["paths"]["/commands/value_rig.pay_in"]["post"]

    schema = operation["requestBody"]["content"]["application/json"]["schema"]

    assert schema["properties"]["amount"] == %{
             "type" => "integer",
             "format" => "int64",
             "minimum" => -9_223_372_036_854_775_808,
             "maximum" => 9_223_372_036_854_775_807,
             "x-ehos-contract-type" => "amount"
           }

    assert schema["properties"]["payment"] == %{
             "anyOf" => [
               %{
                 "type" => "object",
                 "properties" => %{
                   "amount" => %{
                     "type" => "integer",
                     "format" => "int64",
                     "minimum" => -9_223_372_036_854_775_808,
                     "maximum" => 9_223_372_036_854_775_807,
                     "x-ehos-contract-type" => "amount"
                   },
                   "note" => %{
                     "anyOf" => [
                       %{"type" => "string", "x-ehos-contract-type" => "string"},
                       %{"type" => "null"}
                     ]
                   }
                 },
                 "required" => ["amount"],
                 "additionalProperties" => false,
                 "x-ehos-contract-type" => "payment"
               },
               %{"type" => "null"}
             ]
           }
  end

  test "the digest is stable and ignores its own stored value" do
    document = OpenAPI.document(DispatchRig.Ledger)
    digest = document["info"]["x-ehos-contract-digest"]
    tampered = put_in(document, ["info", "x-ehos-contract-digest"], "0000deadbeef")

    assert byte_size(digest) == 12
    assert OpenAPI.digest(document) == digest
    assert OpenAPI.digest(tampered) == digest
  end

  test "command responses describe malformed input and the nullable receipt position" do
    responses =
      OpenAPI.document(DispatchRig.Ledger)["paths"][
        "/commands/dispatch_rig.open_account"
      ]["post"]["responses"]

    assert responses["400"]["description"] =~ "Invalid JSON"
    assert responses["415"]["description"] =~ "application/json"

    receipt = responses["200"]["content"]["application/json"]["schema"]

    assert receipt["properties"]["position"]["anyOf"] == [
             %{"type" => "integer"},
             %{"type" => "null"}
           ]
  end
end

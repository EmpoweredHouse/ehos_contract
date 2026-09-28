defmodule Taxvision.IdentitySeamTest do
  @moduledoc """
  Three levels of access on one request path, each with a different answer (v2
  plan, E9c; until then through `Taxvision.Api` and a token of TaxVision's own).

  | Level | Whose | Answer on refusal |
  |---|---|---|
  | who is this | EHOS's credential, verified by `EhOsContract.Auth.Plug` | 401 |
  | may they open a month at all | the capability EHOS granted | 403 `missing_capability` |
  | may they open **this company's** month | the grant's scope (D10 for commands) | 403 `outside_scope` |

  The third row is the rule "the month is opened by the accountant of this company",
  which v1 wrote as a rule in the contract and a function in `Taxvision.Authorization`.
  It is now what the grant carries, declared on the command and checked before
  anything is decided; what the domain still decides is whether the month may open.
  """

  use Taxvision.DataCase, async: false
  use EhOsContract.Auth.Testing

  import Phoenix.ConnTest
  import Plug.Conn

  alias EhOsContract.{Actor, Event, Testing}
  alias Taxvision.Contracts.{AccountingMonth, RegistryWatch}
  alias Taxvision.Contracts.RegistryWatch.Commands.CompleteCompanyProfile

  @endpoint EhOsContractHostWeb.Endpoint
  @open "taxvision.open_month"

  defp open(token, company, period \\ "2026-08") do
    build_conn()
    |> put_req_header("authorization", "Bearer " <> token)
    |> put_req_header("content-type", "application/json")
    |> post(
      "/api/taxvision/commands/#{@open}",
      Jason.encode!(%{company_id: company, period_id: period})
    )
  end

  defp accountant(companies),
    do: credential("u-accountant", [@open], %{@open => %{"company_id" => companies}})

  defp opened,
    do: Repo.all(from(e in Event, where: e.type == "accounting_month.accounting_month_opened"))

  # c-1's profile complete and August never checked, so that past the door the
  # domain's answer is its own: no consistent check, no month.
  setup do
    Testing.drain()

    {:ok, _} =
      EhOsContract.dispatch(
        RegistryWatch,
        %CompleteCompanyProfile{company_id: "c-1", legal_form: "JDG", vat_status: "czynny"},
        actor:
          Actor.credential("u-accountant", ["taxvision.complete_company_profile"], %{
            "taxvision.complete_company_profile" => %{"company_id" => ["c-1"]}
          })
      )

    :ok
  end

  test "no credential: 401, before any decision" do
    decisions = fn -> Repo.query!("SELECT count(*) FROM eh_os_contract_auth_decisions").rows end
    before = decisions.()

    conn =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> post("/api/taxvision/commands/#{@open}", "{}")

    assert conn.status == 401
    assert decisions.() == before
  end

  test "a credential without the capability: 403, and nothing in the log" do
    conn = open(credential("u-client", []), "c-1")

    assert {conn.status, Jason.decode!(conn.resp_body)} ==
             {403, %{"refused" => "missing_capability"}}

    assert opened() == []
  end

  test "another company's accountant: 403 outside the grant, not a rule the domain decides" do
    conn = open(accountant(["c-2"]), "c-1")
    assert {conn.status, Jason.decode!(conn.resp_body)} == {403, %{"refused" => "outside_scope"}}
    assert opened() == []
  end

  test "the company's own accountant: the domain decides, and without a consistent check refuses" do
    conn = open(accountant(["c-1"]), "c-1")
    assert conn.status == 422
    assert Jason.decode!(conn.resp_body)["rejected"] == "opens_only_on_consistent_registry"
  end

  test "every entry point of TaxVision's contracts refuses a credential without its capability" do
    entries = %{
      "taxvision.complete_company_profile" => fn token ->
        command(token, "taxvision.complete_company_profile", %{
          company_id: "c-1",
          legal_form: "JDG",
          vat_status: "czynny"
        })
      end,
      "taxvision.retrigger_verification" => fn token ->
        command(token, "taxvision.retrigger_verification", %{
          company_id: "c-1",
          period_id: "2026-08"
        })
      end,
      @open => fn token -> open(token, "c-1") end
    }

    assert assert_every_entry_refuses([RegistryWatch, AccountingMonth], entries) == :ok
  end

  defp command(token, capability, body) do
    build_conn()
    |> put_req_header("authorization", "Bearer " <> token)
    |> put_req_header("content-type", "application/json")
    |> post("/api/taxvision/commands/#{capability}", Jason.encode!(body))
  end

  test "the engine holds no credentials" do
    tables =
      Repo.query!(
        "select table_name from information_schema.tables where table_schema = 'public'"
      ).rows
      |> List.flatten()

    for table <- tables,
        column <-
          Repo.query!(
            "select column_name from information_schema.columns where table_name = $1",
            [table]
          ).rows
          |> List.flatten() do
      refute column in ~w(password password_hash hashed_password encrypted_password secret credential),
             "table #{table} has a #{column} column — the engine holds credentials"
    end
  end
end

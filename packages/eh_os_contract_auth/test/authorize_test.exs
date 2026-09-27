defmodule EhOsContract.Auth.AuthorizeTest do
  @moduledoc """
  EA: `EhOsContract.Auth` as the engine's `EhOsContract.Authorizer` — `check/2`'s
  answer, and one row per decision, a refusal as carefully as an acceptance
  (`eh-os` D-34, FM-21).
  """

  use ExUnit.Case, async: true

  alias EhOsContract.{Actor, Auth, Authorizer}
  alias EhOsContract.Auth.TestRepo, as: Repo

  setup do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: false)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
  end

  defp request(capability, opts \\ []) do
    %Authorizer.Request{
      kind: Keyword.get(opts, :kind, :command),
      capability: capability,
      contract: Rehmed.Contracts.VisitSettlement,
      version: "3f2a",
      scope: Keyword.get(opts, :scope)
    }
  end

  defp rows do
    Repo.query!("""
    SELECT subject, kind, capability, contract, contract_version, scope_dimension,
           scope_value, outcome, reason
    FROM eh_os_contract_auth_decisions ORDER BY id
    """).rows
  end

  test "an allowed command has its row" do
    actor = Actor.credential("u-anna", ["rehmed.record_payment"])
    assert Auth.authorize(actor, request("rehmed.record_payment")) == :ok

    assert rows() == [
             [
               "u-anna",
               "command",
               "rehmed.record_payment",
               "Rehmed.Contracts.VisitSettlement",
               "3f2a",
               nil,
               nil,
               "allowed",
               nil
             ]
           ]
  end

  test "a refused command has its row, with the reason" do
    actor = Actor.credential("u-anna", ["rehmed.hand_over_visit"])

    assert Auth.authorize(actor, request("rehmed.record_payment")) ==
             {:error, :missing_capability}

    assert [["u-anna", "command", "rehmed.record_payment", _, _, nil, nil, "refused", reason]] =
             rows()

    assert reason == "missing_capability"
  end

  test "a scoped query's row carries the dimension and the value asked for" do
    capability = "rehmed.open_visits_for_clinic"
    scopes = %{capability => %{"clinic_id" => ["krakow"]}}
    actor = Actor.credential("u-anna", [capability], scopes)
    unscoped = Actor.credential("u-basia", [capability])

    assert Auth.authorize(
             actor,
             request(capability, kind: :query, scope: {"clinic_id", "krakow"})
           ) ==
             :ok

    assert Auth.authorize(
             actor,
             request(capability, kind: :query, scope: {"clinic_id", "gdansk"})
           ) ==
             {:error, :outside_scope}

    assert Auth.authorize(
             unscoped,
             request(capability, kind: :query, scope: {"clinic_id", "krakow"})
           ) ==
             {:error, :unscoped_grant}

    assert Enum.map(rows(), &Enum.take(&1, -4)) == [
             ["clinic_id", "krakow", "allowed", nil],
             ["clinic_id", "gdansk", "refused", "outside_scope"],
             ["clinic_id", "krakow", "refused", "unscoped_grant"]
           ]
  end

  test "it never widens what check/2 answers" do
    for {capabilities, capability} <- [
          {["rehmed.record_payment"], "rehmed.record_payment"},
          {[], "rehmed.record_payment"},
          {["rehmed.close_settlement"], "rehmed.record_payment"}
        ] do
      actor = Actor.credential("u-anna", capabilities)

      assert Auth.authorize(actor, request(capability)) ==
               Authorizer.check(actor, request(capability))
    end
  end
end

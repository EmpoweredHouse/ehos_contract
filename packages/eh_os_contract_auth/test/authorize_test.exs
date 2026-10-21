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
      contract: Clinic.Contracts.VisitSettlement,
      contract_id: "clinic.visit_settlement",
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
    actor = Actor.credential("u-anna", ["clinic.record_payment"])
    assert Auth.authorize(actor, request("clinic.record_payment")) == :ok

    assert rows() == [
             [
               "u-anna",
               "command",
               "clinic.record_payment",
               "clinic.visit_settlement",
               "3f2a",
               nil,
               nil,
               "allowed",
               nil
             ]
           ]
  end

  test "a refused command has its row, with the reason" do
    actor = Actor.credential("u-anna", ["clinic.hand_over_visit"])

    assert Auth.authorize(actor, request("clinic.record_payment")) ==
             {:error, :missing_capability}

    assert [["u-anna", "command", "clinic.record_payment", _, _, nil, nil, "refused", reason]] =
             rows()

    assert reason == "missing_capability"
  end

  test "a scoped query's row carries the dimension and the value asked for" do
    capability = "clinic.open_visits_for_clinic"
    scopes = %{capability => %{"clinic_id" => ["north"]}}
    actor = Actor.credential("u-anna", [capability], scopes)
    unscoped = Actor.credential("u-basia", [capability])

    assert Auth.authorize(
             actor,
             request(capability, kind: :query, scope: {"clinic_id", "north"})
           ) ==
             :ok

    assert Auth.authorize(
             actor,
             request(capability, kind: :query, scope: {"clinic_id", "south"})
           ) ==
             {:error, :outside_scope}

    assert Auth.authorize(
             unscoped,
             request(capability, kind: :query, scope: {"clinic_id", "north"})
           ) ==
             {:error, :unscoped_grant}

    assert Enum.map(rows(), &Enum.take(&1, -4)) == [
             ["clinic_id", "north", "allowed", nil],
             ["clinic_id", "south", "refused", "outside_scope"],
             ["clinic_id", "north", "refused", "unscoped_grant"]
           ]
  end

  # #66: a value as sent that a text column cannot hold, invalid UTF-8 from `%FF` in a query
  # string or a NUL from JSON's "\u0000", made the insert fail and the request answer 500
  # instead of a refusal. Its SHA-256 is recorded instead, and the decision stands.
  test "a scope value a text column cannot hold, or past 256 bytes, is recorded as its digest" do
    capability = "clinic.open_visits_for_clinic"

    actor =
      Actor.credential("u-anna", [capability], %{capability => %{"clinic_id" => ["north"]}})

    # A value that reads as a digest is digested too, so a recorded `sha256:` is always one.
    planted = "sha256:" <> String.duplicate("0", 64)
    values = [<<0xFF>>, "north" <> <<0>>, String.duplicate("k", 257), planted]

    for value <- values do
      assert Auth.authorize(actor, request(capability, kind: :query, scope: {"clinic_id", value})) ==
               {:error, :outside_scope}
    end

    assert Enum.map(rows(), &Enum.at(&1, 6)) ==
             Enum.map(
               values,
               &("sha256:" <> Base.encode16(:crypto.hash(:sha256, &1), case: :lower))
             )

    # The control: 256 bytes of valid text are recorded as they are.
    value = String.duplicate("k", 256)

    assert Auth.authorize(actor, request(capability, kind: :query, scope: {"clinic_id", value})) ==
             {:error, :outside_scope}

    assert rows() |> List.last() |> Enum.at(6) == value
  end

  test "it never widens what check/2 answers" do
    for {capabilities, capability} <- [
          {["clinic.record_payment"], "clinic.record_payment"},
          {[], "clinic.record_payment"},
          {["clinic.close_settlement"], "clinic.record_payment"}
        ] do
      actor = Actor.credential("u-anna", capabilities)

      assert Auth.authorize(actor, request(capability)) ==
               Authorizer.check(actor, request(capability))
    end
  end
end

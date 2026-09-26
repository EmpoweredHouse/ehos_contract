defmodule EhOsContract.DeploymentV2Test do
  @moduledoc """
  The deployment of a v2 contract (v2 §13, plan E7c-2): which version is deployed,
  since when, and what its wiring is — the steps the contract declares, and which
  module implements each declaration.
  """

  use EhOsContract.DataCase, async: false

  alias EhOsContract.{Conformance, Deployment, Report}
  alias ProcessShapes.Next.Promised
  alias ProcessShapes.Seed

  defp row(contract),
    do: Repo.one!(from(d in Deployment, where: d.contract == ^inspect(contract)))

  test "the boot records a v2 contract, its steps as its paths, and its wiring" do
    Deployment.record!()

    row = row(Promised)

    assert row.contract_version == Promised.__eh_os_contract_model__().version
    assert "request_received" in row.events
    assert "command:submit_request->event:request_received" in row.edges

    assert "event:request_refused->policy:notify_on_refusal->command:notify_refusal" in row.edges

    # The wiring is the steps and which module implements each declaration: the
    # same steps under other modules are another wiring.
    refute row.wiring_version == EhOsContract.Digest.hash(row.edges)
    assert Map.has_key?(row.declaration_digests, "promise:completed_or_refusal_notified")
  end

  test "a promise's digest is its rule: confirming it or citing it anew is no change" do
    [promise] = Promised.__eh_os_contract_model__().process.promises
    digest = Deployment.promise_digest(promise)

    assert Deployment.promise_digest(%{promise | unverified: true, source: "W1 00:01:02"}) ==
             digest

    refute Deployment.promise_digest(%{promise | within: %{amount: 3, unit: :day}}) == digest
    refute Deployment.promise_digest(%{promise | or_else: nil}) == digest
  end

  test "a v2 report says since when its version is in force" do
    Seed.deploy(:v2)
    Deployment.record!()

    EhOsContract.Clock.at(~U[2026-09-02 09:00:00.000000Z], fn ->
      Seed.request(:v2, "r-1", :request_approved)
    end)

    report = Conformance.report(Promised)

    assert report.deployment.deployed.since == ~U[2026-09-02 09:00:00.000000Z]
    assert Report.render(report) =~ "in force since 2026-09-02"
  end

  test "a promise that changed does not judge the runs before it" do
    Seed.deploy(:v2)

    for {id, at} <- [
          {"r-old", ~U[2026-08-02 09:00:00.000000Z]},
          {"r-new", ~U[2026-08-09 09:00:00.000000Z]}
        ] do
      EhOsContract.Clock.at(at, fn -> Seed.request(:v2, id, :request_approved) end)
    end

    for {digest, seen} <- [
          {"aaaaaaaaaaaa", ~U[2026-08-01 00:00:00.000000Z]},
          {"bbbbbbbbbbbb", ~U[2026-08-05 09:00:00.000000Z]}
        ] do
      Repo.insert!(%Deployment{
        contract: inspect(Promised),
        contract_version: Promised.__eh_os_contract_model__().version,
        wiring_version: "wiring-#{digest}",
        events: [],
        edges: [],
        declaration_digests: %{"promise:completed_or_refusal_notified" => digest},
        first_seen_at: seen
      })
    end

    [process] = Conformance.report(Promised).processes
    [promise] = process.promises

    assert promise.declaration_changed_at == ~U[2026-08-05 09:00:00.000000Z]
    assert promise.under_earlier_declaration == 1
    assert promise.instances == 1
  end
end

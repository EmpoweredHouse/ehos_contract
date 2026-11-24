defmodule EhosContract.DeploymentTest do
  @moduledoc """
  The deployment of a v2 contract (v2 §13, plan E7c-2): which version is deployed,
  since when, and what its wiring is — the steps the contract declares, and which
  module implements each declaration. The promise is a process module's since plan DD,
  P2g (#228), `ProcessShapes.Handling`, recorded in a row of its own under its id.
  """

  use EhosContract.DataCase, async: false

  alias EhosContract.{Conformance, Deployment, Report}
  alias ProcessShapes.{Handling, Promised, Seed}

  @handling "process:process_shapes.handling"

  defp row(contract),
    do:
      Repo.one!(
        from(d in Deployment, where: d.contract == ^EhosContract.Model.fetch(contract).id)
      )

  test "the boot records a v2 contract, its steps as its paths, and its wiring" do
    Deployment.record!()

    row = row(Promised)

    assert row.contract_version == Promised.__ehos_contract_model__().version
    assert "request_received" in row.events
    assert "command:submit_request->event:request_received" in row.edges

    assert "event:request_refused->policy:notify_on_refusal->command:notify_refusal" in row.edges

    # The wiring is the steps and which module implements each declaration: the
    # same steps under other modules are another wiring.
    refute row.wiring_version == EhosContract.Digest.hash(row.edges)

    process = Repo.one!(from(d in Deployment, where: d.contract == @handling))
    assert Map.has_key?(process.declaration_digests, "promise:completed_or_refusal_notified")
  end

  test "the wiring holds which module checks each value of the contract's domain" do
    Deployment.record!()
    before = row(ValueRig.Till).wiring_version

    apps = Enum.uniq(List.wrap(Application.get_env(:ehos_contract, :applications)))
    key = {EhosContract.Implementations, apps}
    index = EhosContract.Implementations.index(nil)
    on_exit(fn -> :persistent_term.put(key, index) end)

    # The amount's check moves to another module: what dispatch accepts may change,
    # and the contract's declarations do not.
    declarations =
      Map.put(index.declarations, {ValueRig.Domain, :value, :amount}, [ValueRig.Fee])

    :persistent_term.put(key, %{index | declarations: declarations})
    Deployment.record!()

    wirings =
      Repo.all(
        from(d in Deployment, where: d.contract == "value_rig.till", select: d.wiring_version)
      )

    assert length(wirings) == 2
    assert before in wirings
  end

  test "a promise's digest is its rule: confirming it or citing it anew is no change" do
    [promise] = EhosContract.Model.process(Handling).promises
    digest = Deployment.promise_digest(promise)

    assert Deployment.promise_digest(%{promise | unverified: true, source: "W1 00:01:02"}) ==
             digest

    refute Deployment.promise_digest(%{promise | within: %{amount: 3, unit: :day}}) == digest
    refute Deployment.promise_digest(%{promise | or_else: nil}) == digest
  end

  test "a v2 report says since when its version is in force" do
    Seed.deploy()
    Deployment.record!()

    EhosContract.Clock.at(~U[2026-09-02 09:00:00.000000Z], fn ->
      Seed.request("r-1", :request_approved)
    end)

    report = Conformance.report(Promised)

    assert report.deployment.deployed.since == ~U[2026-09-02 09:00:00.000000Z]
    assert Report.render(report) =~ "in force since 2026-09-02"
  end

  test "a promise that changed does not judge the runs before it" do
    Seed.deploy()

    for {id, at} <- [
          {"r-old", ~U[2026-08-02 09:00:00.000000Z]},
          {"r-new", ~U[2026-08-09 09:00:00.000000Z]}
        ] do
      EhosContract.Clock.at(at, fn -> Seed.request(id, :request_approved) end)
    end

    for {digest, seen} <- [
          {"aaaaaaaaaaaa", ~U[2026-08-01 00:00:00.000000Z]},
          {"bbbbbbbbbbbb", ~U[2026-08-05 09:00:00.000000Z]}
        ] do
      Repo.insert!(%Deployment{
        contract: @handling,
        contract_version: Handling.__ehos_contract_model__().version,
        wiring_version: "wiring-#{digest}",
        events: [],
        edges: [],
        declaration_digests: %{"promise:completed_or_refusal_notified" => digest},
        first_seen_at: seen
      })
    end

    [process] = Conformance.report(Handling).processes
    [promise] = process.promises

    assert promise.declaration_changed_at == ~U[2026-08-05 09:00:00.000000Z]
    assert promise.under_earlier_declaration == 1
    assert promise.instances == 1
  end
end

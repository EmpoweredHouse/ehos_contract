defmodule GraphLab.StatutoryReporting.SendP1Report do
  @moduledoc """
  Sends a queued report to the P1 registry and records its answer as the registry's
  integration, a system actor.

  **There is no P1 behind the sandbox**, so this send is the registry saying yes:
  it records `p1_report_sent` and nothing else. A host with the registry calls it
  here and records `p1_report_failed` on a rejection or a lost connection. The
  event's identifier is the idempotency key, and P1 keeps it (`owner: :downstream`):
  a host passes it with the report, so a second delivery is not a second report.
  Here it keys the recording, so a second delivery records nothing new.
  """

  use GraphLab.Contracts.StatutoryReporting, effect: :send_p1_report

  alias EhOsContract.Actor
  alias GraphLab.Contracts.StatutoryReporting.Events.P1ReportSent

  @impl true
  def p1_report_queued(%P1ReportQueued{visit_id: id, __meta__: meta}) do
    with {:ok, _receipt} <-
           EhOsContract.record(GraphLab.Contracts.StatutoryReporting, %P1ReportSent{visit_id: id},
             actor: Actor.system(:p1_integration),
             idempotency_key: "p1-report-sent:#{meta.id}",
             causation_id: meta.id,
             correlation_id: meta.correlation_id
           ),
         do: :ok
  end
end

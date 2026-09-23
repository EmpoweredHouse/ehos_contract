defmodule EhOsContract.Web.Live.ContractStatus do
  @moduledoc """
  Screen 1 of 3: the four questions, per contract, as HTML instead of
  `EhOsContract.Report`'s text.

  **Every sentence comes from `EhOsContract.Report.Sentence`.** This screen decides what is a
  heading, what is a list and what is red; it decides nothing about what the answer
  says. That split used to be a comment rather than a mechanism — the sentences were
  duplicated here, deliberately, on the argument that the structure was small enough
  to copy. By the time anybody ran both renderers side by side, this one was silently
  missing six answers the text one had grown: the addressee, the measured `deadline`,
  a run suspended by an external outage, a run judged under a rule that had since
  changed, which met runs reached the fallback, and queued work at all.

  No contract picker: `EhOsContract.Registry.contracts()` is the same source
  `mix eh_os_contract.report` reads, and this screen renders every contract it finds the
  same way that task does, one section per contract.
  """

  use Phoenix.LiveView

  alias EhOsContract.Conformance
  alias EhOsContract.Report.Sentence

  @impl true
  def mount(_params, _session, socket) do
    reports = Enum.map(EhOsContract.Registry.contracts(), &Conformance.report(&1, []))
    {:ok, assign(socket, :reports, reports)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <EhOsContract.Web.Layouts.nav base_path={@eh_os_contract_web_base_path} current={:contract_status} />
      <p class="access-badge">Access: {access_label(@eh_os_contract_web_access)}</p>

      <div :for={report <- @reports}>
        <h2>{inspect(report.contract)}</h2>

        <section>
          <h3>Contract</h3>
          <p>
            Version {report.deployment.deployed.contract_version}, {deployed_since(
              report.deployment.deployed.since
            )}.
          </p>
        </section>

        <section :for={process <- report.processes}>
          <h3>{process.label}</h3>
          <p :if={Sentence.accountable(process.accountable)}>
            {Sentence.accountable(process.accountable)}
          </p>
          <p>Runs in this period: {process.runs}.</p>

          <p :for={declaration <- process.declarations}>{Sentence.declaration(declaration)}</p>
          <p :for={line <- Sentence.duration(process.duration)}>{line}</p>

          <p :if={process.runs == 0}>{Sentence.no_runs()}</p>

          <div :if={process.runs > 0}>
            <h4>Declared paths never exercised</h4>
            <p :if={process.untraversed == []}>{Sentence.all_steps_carried_out()}</p>
            <ul :if={process.untraversed != []}>
              <li :for={edge <- process.untraversed}>{Sentence.step(edge)}</li>
            </ul>

            <div :if={process.in_flight != []}>
              <h4>Agreed steps whose work is queued</h4>
              <ul>
                <li :for={edge <- process.in_flight}>{Sentence.step_in_flight(edge)}</li>
              </ul>
            </div>

            <div :if={process.failing != []}>
              <h4>Agreed steps that are attempted and fail</h4>
              <ul>
                <li :for={edge <- process.failing}>{Sentence.step_failing(edge)}</li>
              </ul>
            </div>
          </div>

          <div :if={process.assertions != []}>
            <h4>Trace assertions</h4>
            <ul>
              <li :for={assertion <- process.assertions}>
                <p>{Sentence.rule(assertion)}</p>
                <p class={outcome_class(assertion)}>{Sentence.verdict(assertion)}</p>
                <p
                  :for={qualification <- Sentence.qualifications(assertion)}
                  class="outcome-qualification"
                >
                  {qualification}
                </p>
              </li>
            </ul>
          </div>
        </section>

        <section>
          <h3>Drift</h3>
          <p :if={report.drift == []}>{Sentence.no_drift()}</p>
          <ul :if={report.drift != []}>
            <li :for={edge <- report.drift}>
              {edge.from_label || edge.from} → {edge.to_label || edge.to} ({edge.count}x)
            </li>
          </ul>
        </section>
      </div>
    </div>
    """
  end

  @spec access_label(:all | :read_only) :: String.t()
  defp access_label(:all), do: "all"
  defp access_label(:read_only), do: "read only"

  @spec deployed_since(DateTime.t() | nil) :: String.t()
  defp deployed_since(nil), do: "nothing has happened under this version yet"
  defp deployed_since(at), do: "in force since #{DateTime.to_date(at)}"

  # The one line the report exists to be read from — README's own pitch for
  # it — so it is the one place color carries the answer, not just the words.
  # **The verdict only.** The clauses beside it are deliberately unstyled: one of
  # them says an outage means "this is not a breach on the client's side", and that
  # sentence printed in the breach colour says the opposite of what it means.
  @spec outcome_class(map()) :: String.t()
  defp outcome_class(a) do
    cond do
      a.instances == 0 -> ""
      a.violated > 0 -> "outcome-breached"
      a.pending > 0 -> "outcome-pending"
      true -> "outcome-ok"
    end
  end
end

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

  No contract picker: the registry's contracts are the same source
  `mix eh_os_contract.report` reads, and this screen renders every contract it finds the
  same way that task does, one section per contract. A contract's report has its
  steps, its promises, its wiring and its scenarios (v2 plan, E7c), and for an
  aggregate that declares a lifecycle, the same first two questions of its
  transitions (plan LC4b).
  """

  use Phoenix.LiveView

  alias EhOsContract.Conformance
  alias EhOsContract.Report.Sentence

  @impl true
  def mount(_params, _session, socket) do
    reports =
      Enum.map(EhOsContract.Registry.contracts(), &Conformance.report(&1, []))

    {:ok, assign(socket, :reports, reports)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <EhOsContract.Web.Layouts.nav base_path={@eh_os_contract_web_base_path} current={:contract_status} />
      <p class="access-badge">Access: {access_label(@eh_os_contract_web_access)}</p>

      <div :for={report <- @reports}>
        <h2>{report.contract}</h2>

        <section>
          <h3>Contract</h3>
          <p>
            Version {report.deployment.deployed.contract_version}, {deployed_since(
              report.deployment.deployed.since
            )}.
          </p>
          <p :if={report.wiring.version}>Wiring {report.wiring.version}.</p>
        </section>

        <section>
          <h3>Steps</h3>
          <p>{Sentence.activity(report.activity)}</p>

          <p :if={report.paths.steps == []}>{Sentence.no_steps()}</p>
          <p :if={report.paths.steps != [] and idle?(report)}>{Sentence.no_activity()}</p>

          <div :if={report.paths.steps != []}>
            <div :if={report.activity.events > 0}>
              <h4>Declared paths never exercised</h4>
              <p :if={carried_out?(report.paths)}>{Sentence.all_steps_carried_out()}</p>
              <ul :if={report.paths.untraversed != []}>
                <li :for={edge <- report.paths.untraversed}>{Sentence.step(edge)}</li>
              </ul>
            </div>

            <div :if={report.paths.in_flight != []}>
              <h4>Agreed steps whose work is queued</h4>
              <ul>
                <li :for={edge <- report.paths.in_flight}>{Sentence.step_in_flight(edge)}</li>
              </ul>
            </div>

            <div :if={report.paths.failing != []}>
              <h4>Agreed steps that are attempted and fail</h4>
              <ul>
                <li :for={edge <- report.paths.failing}>{Sentence.step_failing(edge)}</li>
              </ul>
            </div>
          </div>
        </section>

        <section :for={process <- report.processes}>
          <h3>{process.label}</h3>
          <p :if={Sentence.accountable(process.accountable)}>
            {Sentence.accountable(process.accountable)}
          </p>
          <p>Runs in this period: {process.runs}.</p>

          <p :for={declaration <- process.declarations}>{Sentence.declaration(declaration)}</p>
          <p :for={line <- Sentence.duration(process.duration)}>{line}</p>

          <div :if={process.promises != []}>
            <h4>Promises</h4>
            <ul>
              <li :for={assertion <- process.promises}>
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

        <section :for={lifecycle <- Map.get(report, :lifecycles, [])}>
          <h3>Lifecycle: {lifecycle.label}</h3>
          <p>Aggregates with an event in this period: {lifecycle.aggregates}.</p>
          <p :if={lifecycle.aggregates == 0}>{Sentence.no_aggregates()}</p>

          <div :if={lifecycle.aggregates > 0}>
            <h4 :if={lifecycle.untraversed != []}>Declared transitions never taken</h4>
            <p :if={lifecycle.untraversed == [] and lifecycle.pending == []}>
              {Sentence.all_transitions_taken()}
            </p>
            <ul :if={lifecycle.untraversed != []}>
              <li :for={transition <- lifecycle.untraversed}>{Sentence.transition(transition)}</li>
            </ul>

            <div :if={lifecycle.pending != []}>
              <h4>Not taken yet — an aggregate still stands where they can happen</h4>
              <ul>
                <li :for={transition <- lifecycle.pending}>{Sentence.transition(transition)}</li>
              </ul>
            </div>
          </div>

          <div :if={lifecycle.undeclared != []}>
            <h4>Happened, though the lifecycle does not allow it there</h4>
            <ul>
              <li :for={move <- lifecycle.undeclared}>{Sentence.transition_undeclared(move)}</li>
            </ul>
          </div>
        </section>

        <section :if={report[:scenarios]}>
          <h3>Scenarios</h3>
          <p>{Sentence.scenarios_observed(report.scenarios)}</p>
          <div :if={report.scenarios.never_observed != []}>
            <h4>Never observed</h4>
            <ul>
              <li :for={description <- report.scenarios.never_observed}>"{description}"</li>
            </ul>
          </div>
          <div :if={report.scenarios.undeclared_outcomes != []}>
            <h4>Outcomes no scenario declares</h4>
            <ul>
              <li :for={outcome <- report.scenarios.undeclared_outcomes}>
                {Sentence.outcome_undeclared(outcome)}
              </li>
            </ul>
          </div>
        </section>

        <section>
          <h3>Drift</h3>
          <p :if={report.drift == []}>{Sentence.no_drift()}</p>
          <ul :if={report.drift != []}>
            <li :for={edge <- report.drift}>{Sentence.drift(edge)}</li>
          </ul>
        </section>
      </div>
    </div>
    """
  end

  # As in the text report: a branch is several steps behind one queue, so "carried
  # out" is said only when nothing of it waits either.
  @spec carried_out?(map()) :: boolean()
  defp carried_out?(paths), do: paths.untraversed == [] and paths.in_flight == []

  # Plan DD, P1a (#183): "never" is judged when the contract recorded an event; with
  # none, and nothing waiting or failing, there is nothing to say about its steps.
  @spec idle?(map()) :: boolean()
  defp idle?(report),
    do:
      report.activity.events == 0 and report.paths.in_flight == [] and
        report.paths.failing == []

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

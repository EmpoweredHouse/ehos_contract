defmodule PNS.Web.Live.ContractStatus do
  @moduledoc """
  Screen 1 of 2: the four questions, per contract, as HTML instead of
  `PNS.Report`'s text. Same data, same reader, same wording where the wording
  is the answer to a question — a formatting choice, not a second opinion
  about what conformance means.

  No contract picker: `PNS.Registry.contracts()` is the same source
  `mix pns.report` reads, and this screen renders every contract it finds the
  same way that task does, one section per contract.
  """

  use Phoenix.LiveView

  alias PNS.Conformance

  @impl true
  def mount(_params, _session, socket) do
    reports = Enum.map(PNS.Registry.contracts(), &Conformance.report(&1, []))
    {:ok, assign(socket, :reports, reports)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <PNS.Web.Layouts.nav base_path={@pns_web_base_path} current={:contract_status} />
      <p class="access-badge">Access: {access_label(@pns_web_access)}</p>

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
          <p>Runs in this period: {process.runs}.</p>

          <p :if={process.runs == 0}>
            The agreed steps cannot be judged: there was not a single run in this period.
          </p>

          <div :if={process.runs > 0}>
            <h4>Declared paths never exercised</h4>
            <p :if={process.untraversed == []}>All agreed steps were carried out in this period.</p>
            <ul :if={process.untraversed != []}>
              <li :for={edge <- process.untraversed}>{edge.from_label} → {edge.to_label}</li>
            </ul>

            <div :if={process.failing != []}>
              <h4>Agreed steps that are attempted and fail</h4>
              <ul>
                <li :for={edge <- process.failing}>
                  {edge.from_label} → {edge.to_label} — failed in {edge.failing} run(s)
                </li>
              </ul>
            </div>
          </div>

          <div :if={process.assertions != []}>
            <h4>Trace assertions</h4>
            <ul>
              <li :for={assertion <- process.assertions}>
                <p>{rule_sentence(assertion)}</p>
                <p class={outcome_class(assertion)}>{outcome_sentence(assertion)}</p>
              </li>
            </ul>
          </div>
        </section>

        <section>
          <h3>Drift</h3>
          <p :if={report.drift == []}>None: nothing happened outside the agreement.</p>
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

  # The rule and outcome sentences mirror `PNS.Report`'s wording on purpose —
  # same fact, same reader — but live here rather than being shared with it:
  # `PNS.Duration.humanize/1` is the one piece both renderers cannot be
  # allowed to disagree on (it exists specifically to prevent that), so it is
  # reused directly; the surrounding sentence structure is presentation glue
  # for two different mediums and is small enough that duplicating it beats
  # inventing a shared renderer neither text nor HTML fully needs yet.
  @spec rule_sentence(map()) :: String.t()
  defp rule_sentence(a) do
    window = if a.within, do: " within #{PNS.Duration.humanize(a.within)}", else: ""
    alternative = if a.or_else_label, do: ~s(, or else "#{a.or_else_label}"), else: ""
    ~s(Rule: after "#{a.from_label}"#{window}, "#{a.eventually_label}" follows#{alternative}.)
  end

  @spec outcome_sentence(map()) :: String.t()
  defp outcome_sentence(a) do
    cond do
      a.instances == 0 -> "There was no run in this period on which this could be judged."
      a.violated > 0 -> "BREACHED in #{a.violated} of #{a.instances} runs."
      a.pending > 0 -> "Met in #{a.satisfied} of #{a.instances}, #{a.pending} still in progress."
      true -> "Met in all #{a.instances} runs."
    end
  end

  # The one line the report exists to be read from — README's own pitch for
  # it — so it is the one place color carries the answer, not just the words.
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

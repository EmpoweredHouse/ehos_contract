defmodule PNS.Telemetry do
  @moduledoc """
  What the engine emits, and — just as deliberately — what it does not.

  Collection, dashboards and alerts are not here and are not coming: performance
  belongs to the platform, errors to the client's error tooling, and the state of the
  business to the client's own application. This module is the seam those attach to.

  ## What is emitted

  | Event | When | Measurements |
  | --- | --- | --- |
  | `[:pns, :handler, :start]` | a handler begins | `system_time`, `monotonic_time` |
  | `[:pns, :handler, :stop]` | it returns | `duration`, `monotonic_time` |
  | `[:pns, :handler, :exception]` | it raises | `duration`, `monotonic_time` |
  | `[:pns, :contract, :violation]` | an emission is refused | `system_time` |

  Two families, and each is something **no other tool in the stack can see**: nothing
  else observes a synchronous handler, and nothing else knows what the client agreed to.

  The handler events are a `:telemetry.span/3`, so `duration` is in native time units
  and the three names follow the convention Ecto, Phoenix and Oban all use. **The first
  seam, added a day earlier for stage 2.3, invented its own shape with a `duration_us`
  measurement — that was a diagnosis mechanism written without thinking about the
  library's integrators, and it is corrected here.** A package that emits
  almost-conventional telemetry costs every integrator a special case.

  ## What is deliberately not emitted

  **Query timings.** Ecto already emits `[:taxvision, :repo, :query]`, with the SQL and
  the source table. Repeating it here would give two numbers for one query.

  **Job lifecycle.** Oban emits its own span per job, including retries and
  cancellations, and it knows things this engine does not — queue depth, scheduling lag.
  The handler span inside a job is ours; the job around it is Oban's.

  **Anything a report answers.** Untraversed paths, assertion verdicts and drift are
  computed from the log on demand. Emitting them as metrics would make a second,
  approximate copy of the product's own output, and the two would disagree the first
  time a job was slow.

  **A count of emitted events**, which was written and then removed rather than never
  considered. The log holds that count exactly, and a metric could only be emitted from
  inside the transaction — so a synchronous handler failing would roll the fact back
  while the counter kept it. A number that is wrong precisely when something is broken
  is worse than no number, and it would have been a second approximate copy, which is
  the rule two paragraphs up.

  ## The rule about metadata, which is a retention rule

  **Telemetry is a third way out of the system, and `retain` must not be walkable around
  it either.** The log and the job arguments are covered — that was settled when
  `retain` moved before storage — and a metric carrying a payload value would reopen
  exactly the hole that closed.

  So metadata carries **names, and the run key**. Names are declarations, and the run key
  is in the log by design, reproducible from it alone; both are already as public as the
  log is. Payload values are not, and never appear here.
  """

  @events [
    [:pns, :handler, :start],
    [:pns, :handler, :stop],
    [:pns, :handler, :exception],
    [:pns, :contract, :violation]
  ]

  @doc """
  Every event this engine emits.

  Public so the catalogue above can be pinned by a test rather than described. A
  library's telemetry names are an interface: renaming one silently is the same as
  renaming a public function, and a hand-maintained list of them is the second source
  of truth this project keeps finding.
  """
  @spec events() :: [[atom()]]
  def events, do: @events

  @doc """
  Runs a handler inside a `:telemetry.span/3`.

  The span emits `:stop` on a normal return and `:exception` on a raise, then re-raises
  the original — so a caller that wants to wrap the exception still can, and that is
  what the synchronous path does.
  """
  @spec handler_span(map(), (-> term())) :: term()
  def handler_span(metadata, fun) do
    :telemetry.span([:pns, :handler], metadata, fn -> {fun.(), %{}} end)
  end

  @doc """
  Records an emission refused because it contradicted the contract.

  The one family of events no other tool can produce. Ecto sees a query, Oban sees a
  job, an error tracker sees an exception — none of them can say *the code stopped
  matching what the client agreed to*, which is the entire product. A rising count here
  is drift caught while it happens, rather than in the next report.

  `kind` is one of `:payload`, `:cycle`, `:undeclared_publication`.
  """
  @spec contract_violation(atom(), map()) :: :ok
  def contract_violation(kind, metadata) do
    :telemetry.execute(
      [:pns, :contract, :violation],
      %{system_time: System.system_time()},
      Map.put(metadata, :kind, kind)
    )
  end
end

defmodule EhOsContract.Report.Sentence do
  # The sentences a conformance report is made of, without any of its layout.
  #
  # One question, one answer, one wording — whatever medium it is printed in.
  # `EhOsContract.Report` wraps these in indentation and line breaks; a dashboard wraps them in
  # HTML. Neither owns the words.
  #
  # ## Why this module exists
  #
  # The dashboard used to carry its own copy, with a comment saying the duplication
  # was deliberate and that "the surrounding sentence structure is presentation glue
  # small enough that duplicating it beats inventing a shared renderer". That was a
  # reasonable call when both copies said the same four things. By the time anybody
  # looked again, the text renderer had grown six answers the screen did not have:
  #
  #   * who a finding is addressed to (`accountable`),
  #   * the measured process `deadline`,
  #   * a run suspended by somebody else's outage,
  #   * a run judged under a rule that has since changed,
  #   * which met runs reached the fallback ending,
  #   * work sitting in a queue at all.
  #
  # A run suspended by an external outage therefore read on screen exactly like an
  # ordinary one. Two renderers of one fact, drifting silently, is the thing this
  # product detects for a living — so it does not get to live inside it.
  #
  # Returned strings carry no leading whitespace and no bullet. Anything that is a
  # list stays a list, because a medium decides what a list looks like.
  @moduledoc false

  @doc """
  What the promise says, as a sentence a process owner can be read.

  A promise has no `label`, so a technical name is all there would otherwise be — and a report saying `month_opens_or_is_blocked` does not meet
  the "readable without explanation" criterion.
  """
  @spec rule(map()) :: String.t()
  def rule(a) do
    window = if a.within, do: " within #{amount(a.within)}", else: ""
    alternative = if a.or_else_label, do: ~s(, or else "#{a.or_else_label}"), else: ""

    ~s(Rule: after "#{a.from_label}"#{window}, "#{a.eventually_label}" follows#{alternative}.)
  end

  @doc """
  Whether it was kept, with every qualification that changes what the number means.

  One string, for a medium that has one. A medium that can style parts differently
  should use `verdict/1` and `qualifications/1` instead — the qualifications are not
  the verdict, and one of them says outright that something is *not* a breach.
  """
  @spec outcome(map()) :: String.t()
  def outcome(a), do: Enum.join([verdict(a) | qualifications(a)], " ")

  @doc """
  The verdict alone: kept, breached, pending, or nothing to judge.

  This is the part a glance is supposed to answer, and the only part it is honest to
  colour. The clauses beside it qualify the number and sometimes contradict the
  colour — "an external dependency was unavailable, so this is not a breach on the
  client's side" printed in red says the opposite of what it means.
  """
  @spec verdict(map()) :: String.t()
  def verdict(a) do
    cond do
      # Two different sentences. "Nothing to judge" is an absence; "every run here
      # predates the current rule" is a fact about which promise was in force, and
      # those runs did happen.
      a.instances == 0 and a.under_earlier_declaration > 0 ->
        "No run in this period was judged under the rule as it now stands."

      a.instances == 0 ->
        "There was no run in this period on which this could be judged."

      a.violated > 0 ->
        "BREACHED in #{a.violated} of #{a.instances} runs."

      a.pending > 0 ->
        "Met in #{a.satisfied} of #{a.instances}, #{a.pending} still in progress."

      true ->
        "Met in all #{a.instances} runs."
    end
  end

  @doc """
  Everything that changes what the verdict's number means, each a whole sentence.

  Empty for most assertions. Each one exists because a count on its own would be
  read as saying more than it does.
  """
  @spec qualifications(map()) :: [String.t()]
  def qualifications(a) do
    Enum.reject([via(a), suspended(a), earlier_declaration(a)], &(&1 == nil))
  end

  @doc """
  The role a finding about this process goes to, or `nil`.

  `nil` rather than a placeholder: an invented addressee is worse than none, because
  it sends the finding to somebody who never agreed to receive it.
  """
  @spec accountable(String.t() | nil) :: String.t() | nil
  def accountable(nil), do: nil
  def accountable(role), do: "Accountable: #{role}."

  @doc """
  What one run of a process is, by the fields that tell its runs apart (its
  `correlate`), as the clause that follows a count of runs: `one per visit_id`, `one
  per payer_id and period_id`. `nil` without fields.
  """
  @spec runs_per([atom() | String.t()]) :: String.t() | nil
  def runs_per([]), do: nil

  def runs_per(fields) do
    names = Enum.map(fields, &to_string/1)

    case names do
      [one] -> "one per #{one}"
      many -> "one per #{Enum.join(Enum.drop(many, -1), ", ")} and #{List.last(many)}"
    end
  end

  @doc """
  The count of a process's runs in the period, with what one run is when its
  `correlate` is given: `Runs in this period: 3, one per visit_id.`
  """
  @spec runs_in_period(non_neg_integer(), [atom() | String.t()]) :: String.t()
  def runs_in_period(runs, correlate) do
    case runs_per(correlate) do
      nil -> "Runs in this period: #{runs}."
      clause -> "Runs in this period: #{runs}, #{clause}."
    end
  end

  @doc """
  A process module's deployment (`EhOsContract.Deployment`'s, as a process module's
  report carries it): its version and since when it is deployed, then what changed
  since the previous version. A process module stamps no event with its version, so
  it is in force since the deployment that carries it was first recorded.
  """
  @spec process_deployment(map()) :: [String.t()]
  def process_deployment(deployment) do
    since =
      case deployment.deployed.since do
        nil -> "not recorded as deployed"
        at -> "deployed since #{at |> DateTime.to_date() |> Date.to_string()}"
      end

    change =
      case deployment.changed do
        nil -> []
        c -> change(c, paths: false)
      end

    ["Version #{deployment.deployed.version}, #{since}." | change]
  end

  @doc """
  What changed since the previous deployment (`EhOsContract.Deployment`'s), as
  sentences: when the version moved, the events and, with `paths: true`, the paths
  added and removed, then the declarations and the words that changed; when only the
  words did, that the agreement did not, and whose words; when only the code did, that.

      iex> EhOsContract.Report.Sentence.change(
      ...>   %{agreement_changed: false, words: ["event:visit_completed"],
      ...>     events_added: [], events_removed: [], declarations: %{added: [], removed: [], changed: []}},
      ...>   paths: false
      ...> )
      ["Only the words changed since the previous deployment, not the agreement: 1 (event:visit_completed)."]
  """
  @spec change(map(), keyword()) :: [String.t()]
  def change(%{agreement_changed: false, words: [_ | _] = words}, _opts) do
    [
      "Only the words changed since the previous deployment, not the agreement: " <>
        "#{length(words)} (#{Enum.join(words, ", ")})."
    ]
  end

  # A new wiring under the same version and words: the code moved, and nothing the
  # contract says did.
  def change(%{agreement_changed: false, words: []}, _opts),
    do: ["Only the code changed since the previous deployment, not the agreement or its words."]

  def change(c, opts) do
    paths =
      if Keyword.fetch!(opts, :paths),
        do: ", paths added #{length(c.paths_added)}, removed #{length(c.paths_removed)}",
        else: ""

    [
      "Since the previous version: " <>
        "events added #{length(c.events_added)}, removed #{length(c.events_removed)}" <>
        paths <> "."
    ] ++ declarations_changed(c.declarations) ++ words_changed(c.words)
  end

  # Words that changed with the agreement, named as the declarations are. Not recorded
  # on either side says nothing: the agreement's change is what the reader looks for.
  defp words_changed([_ | _] = words),
    do: ["Words changed: #{length(words)} (#{Enum.join(words, ", ")})."]

  defp words_changed(_none_or_not_recorded), do: []

  @doc """
  What declarations changed since the previous version, which events and paths could
  never carry: a promise whose window moved, or an event whose field became
  `personal:`, adds and removes nothing. Named rather than counted, because "2
  declarations changed" sends the reader looking and the names end the search.
  """
  @spec declarations_changed(map() | :not_recorded) :: [String.t()]
  def declarations_changed(:not_recorded) do
    [
      "What the declarations said under the previous version was not recorded, " <>
        "so it cannot be compared."
    ]
  end

  def declarations_changed(%{added: [], removed: [], changed: []}), do: []

  def declarations_changed(d) do
    moved = d.changed ++ d.added ++ d.removed
    ["Declarations changed: #{length(moved)} (#{Enum.join(moved, ", ")})."]
  end

  @doc "A confirmed process declaration, as a sentence."
  @spec declaration(map()) :: String.t()
  def declaration(%{key: :deadline, value: value}),
    do: "Deadline: #{amount(value)} from the start."

  @doc """
  The declared duration, measured. Empty when the process declares none, has not
  confirmed it, or had no run — three different silences, none of which is a number.
  """
  @spec duration(map() | nil) :: [String.t()]
  def duration(nil), do: []
  def duration(%{runs: 0}), do: []

  def duration(d) do
    finished = d.within + d.exceeded

    # The duration itself is not repeated: `declaration/1` prints it, and
    # `EhOsContract.Duration.humanize/1` drops the numeral at a count of one precisely because
    # its callers put a word in front of it. A second copy reads "of hour".
    judged =
      cond do
        finished == 0 ->
          "No run finished in this period, so the agreed duration cannot be judged."

        d.exceeded > 0 ->
          "The agreed duration was exceeded in #{d.exceeded} of #{runs(finished)} that finished."

        true ->
          "The agreed duration was kept in all #{runs(finished)} that finished."
      end

    # Never folded into the count above: there the duration is known, here only a
    # lower bound on it is, and "took an hour" is not "has been running for an hour".
    if d.overdue > 0 do
      [judged, "#{runs(d.overdue)} still open and already past it."]
    else
      [judged]
    end
  end

  @doc """
  A step, by its business labels. The technical names are for whoever writes code.

  A step (`EhOsContract.Paths`) goes from a command to its event, or from an
  event through a consumer to a command, and says which consumer: `"Deposited →
  Flag the account for review (via: Flag an account on a large deposit)"`. An
  effect's step ends at the effect.
  """
  @spec step(map()) :: String.t()
  def step(%{from: %{} = from, via: nil, to: %{} = to}), do: "#{name(from)} → #{name(to)}"
  def step(%{from: %{} = from, via: %{} = via, to: nil}), do: "#{name(from)} → #{name(via)}"

  def step(%{from: %{} = from, via: %{} = via, to: %{} = to}),
    do: "#{name(from)} → #{name(to)} (via: #{name(via)})"

  @doc """
  A step whose work is sitting in a queue — which is not a step nobody took. It
  names each source that waits, since each goes to somebody else: events its
  consumer has not reached yet, timers scheduled, effects queued.
  """
  @spec step_in_flight(map()) :: String.t()
  def step_in_flight(%{in_flight: %{} = waiting} = s) do
    parts =
      Enum.reject(
        [
          count(waiting.lag, "event not yet taken", "events not yet taken"),
          count(waiting.timers, "timer scheduled", "timers scheduled"),
          count(waiting.effects, "effect queued", "effects queued")
        ],
        &is_nil/1
      )

    "#{step(s)} — in progress: #{Enum.join(parts, ", ")}"
  end

  @doc """
  A step that is attempted and does not succeed.

  Kept apart from "never carried out" because it is a different finding for a
  different reader: there the question is whether the step is still agreed, here the
  code is broken. Merging them puts a bug in front of the client as a question about
  their process.
  """
  @spec step_failing(map()) :: String.t()
  def step_failing(%{failing: %{} = failing} = s) do
    parts =
      Enum.reject(
        [
          count(failing.commands, "command failed", "commands failed"),
          failing.subscription && "the subscription stopped at an event it cannot apply",
          count(failing.effects, "effect job discarded", "effect jobs discarded")
        ],
        &(&1 in [nil, false])
      )

    "#{step(s)} — failing: #{Enum.join(parts, "; ")}"
  end

  @doc """
  The runs that entered a later stage before an earlier one: a heading and one line per
  pair of stages, or nothing when every run kept the order. Never which runs: those are
  the business's data.
  """
  @spec out_of_order(map()) :: {String.t(), [String.t()]} | nil
  def out_of_order(%{runs: 0}), do: nil

  def out_of_order(%{runs: n, pairs: pairs}) do
    {"Stages out of order in #{runs(n)}:",
     for(p <- pairs, do: "#{p.later_label} before #{p.earlier_label}: #{runs(p.runs)}")}
  end

  @doc "A count of runs, with the numeral where it belongs."
  @spec runs(non_neg_integer()) :: String.t()
  def runs(1), do: "1 run"
  def runs(n), do: "#{n} runs"

  @doc "What happened in a contract in the period: its events and its commands."
  @spec activity(%{events: non_neg_integer(), commands: non_neg_integer()}) :: String.t()
  def activity(%{events: events, commands: commands}),
    do:
      "Activity in this period: #{plural(events, "event", "events")}, " <>
        "#{plural(commands, "command", "commands")}."

  @doc "The sentences that stand in for a section with nothing in it."
  @spec no_activity() :: String.t()
  def no_activity,
    do: "The agreed steps cannot be judged: this contract recorded no event in this period."

  @doc false
  @spec no_steps() :: String.t()
  def no_steps, do: "The contract declares no steps."

  @doc false
  @spec all_steps_carried_out() :: String.t()
  def all_steps_carried_out, do: "All agreed steps were carried out in this period."

  @doc """
  A transition of an aggregate's lifecycle (plan LC3): the status it leaves, the event
  that moves it, the status it enters. An aggregate with no status yet is at its start.
  """
  @spec transition(map()) :: String.t()
  def transition(%{from: from, event: event, to: to}),
    do: "#{status(from)} → #{name(to)} (on: #{name(event)})"

  @doc """
  An event the lifecycle does not allow where the aggregate stood, with how often:
  it happened, and the status did not follow it.
  """
  @spec transition_undeclared(map()) :: String.t()
  def transition_undeclared(%{from: nil, event: event, count: count}),
    do: "#{name(event)} before the aggregate started — no status followed  (#{count}x)"

  def transition_undeclared(%{from: from, event: event, count: count}),
    do: "#{name(event)} in #{name(from)} — the status stayed  (#{count}x)"

  @doc false
  @spec no_aggregates() :: String.t()
  def no_aggregates,
    do: "The declared transitions cannot be judged: no aggregate had an event in this period."

  @doc false
  @spec all_transitions_taken() :: String.t()
  def all_transitions_taken, do: "All declared transitions were taken in this period."

  defp status(nil), do: "start"
  defp status(ref), do: name(ref)

  @doc """
  One thing that happened though it was not agreed: an event no declared command
  emits, by a command that does not emit it or written around dispatch.
  """
  @spec drift(map()) :: String.t()
  def drift(%{from: nil, to: %{} = to} = e),
    do: "#{name(to)} — written outside dispatch  (#{e.count}x)"

  def drift(%{from: %{} = from, to: %{} = to} = e),
    do: "#{name(from)} → #{name(to)}  (#{e.count}x)"

  @doc """
  How many of a v2 contract's command scenarios the log saw happen
  (`EhOsContract.Coverage`).
  """
  @spec scenarios_observed(map()) :: String.t()
  def scenarios_observed(%{declared: 0}),
    do: "No scenario is triggered by a command, so none can be observed in the log."

  def scenarios_observed(s),
    do: "Scenarios: #{s.observed} of #{s.declared} observed in this period."

  @doc """
  A decision the log saw that no scenario declares: the command, and what it emitted
  or the invariant it was refused on.
  """
  @spec outcome_undeclared(map()) :: String.t()
  def outcome_undeclared(%{rejected: nil} = o) do
    emitted = if o.emitted == [], do: "nothing", else: Enum.join(o.emitted, ", ")
    "#{name(o.command)} → #{emitted}"
  end

  def outcome_undeclared(o), do: "#{name(o.command)} → refused: #{o.rejected}"

  @doc false
  @spec no_drift() :: String.t()
  def no_drift, do: "None: nothing happened outside the agreement."

  # Attached to the count it qualifies, never to the sentence as a whole. Appended to
  # whatever `state` said, it produced "BREACHED in 1 of 5 runs. (including 1 via the
  # fallback ending…)", where "including" reads as qualifying the breaches.
  @spec via(map()) :: String.t() | nil
  defp via(%{satisfied_via_or_else: 0}), do: nil
  defp via(%{satisfied: 0}), do: nil

  defp via(a) do
    "Of those that were met, #{runs(a.satisfied_via_or_else)} reached the fallback " <>
      "ending, which conforms to the rule."
  end

  # Named as somebody else's outage, and **not** counted among the breaches. That is
  # the whole value of the fourth verdict: without it these runs read as "you broke
  # your own agreement" when a system they depend on stopped answering.
  @spec suspended(map()) :: String.t() | nil
  defp suspended(%{suspended: 0}), do: nil

  defp suspended(a) do
    "Suspended: #{runs(a.suspended)} — an external dependency was unavailable within the " <>
      "rule's window, so this is not a breach on the client's side."
  end

  # Runs that began before this assertion last changed were judged under a promise
  # that is no longer the declared one. Counted, not listed, with the date, so a
  # reader can narrow the period themselves.
  @spec earlier_declaration(map()) :: String.t() | nil
  defp earlier_declaration(%{under_earlier_declaration: 0}), do: nil

  defp earlier_declaration(a) do
    "#{runs(a.under_earlier_declaration)} began before this rule was last changed " <>
      "(#{Date.to_string(DateTime.to_date(a.declaration_changed_at))}) and are not counted " <>
      "here — they were judged under a different promise."
  end

  # What the business calls a node, and its name when nothing does. A timer has had a
  # label since plan N3, so a timer's step reads in the client's words too.
  @spec name(map()) :: String.t()
  defp name(%{label: label}) when is_binary(label), do: label
  defp name(%{name: name}), do: Atom.to_string(name)

  @spec count(non_neg_integer(), String.t(), String.t()) :: String.t() | nil
  defp count(0, _one, _many), do: nil
  defp count(n, one, many), do: plural(n, one, many)

  @spec plural(non_neg_integer(), String.t(), String.t()) :: String.t()
  defp plural(1, one, _many), do: "1 #{one}"
  defp plural(n, _one, many), do: "#{n} #{many}"

  @spec amount({pos_integer(), atom()}) :: String.t()
  defp amount(duration), do: EhOsContract.Duration.humanize(duration)
end

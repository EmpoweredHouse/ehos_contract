defmodule PNS.Report.Sentence do
  @moduledoc """
  The sentences a conformance report is made of, without any of its layout.

  One question, one answer, one wording — whatever medium it is printed in.
  `PNS.Report` wraps these in indentation and line breaks; a dashboard wraps them in
  HTML. Neither owns the words.

  ## Why this module exists

  The dashboard used to carry its own copy, with a comment saying the duplication
  was deliberate and that "the surrounding sentence structure is presentation glue
  small enough that duplicating it beats inventing a shared renderer". That was a
  reasonable call when both copies said the same four things. By the time anybody
  looked again, the text renderer had grown six answers the screen did not have:

    * who a finding is addressed to (`accountable`),
    * the measured process `deadline`,
    * a run suspended by somebody else's outage,
    * a run judged under a rule that has since changed,
    * which met runs reached the fallback ending,
    * work sitting in a queue at all.

  A run suspended by an external outage therefore read on screen exactly like an
  ordinary one. Two renderers of one fact, drifting silently, is the thing this
  product detects for a living — so it does not get to live inside it.

  Returned strings carry no leading whitespace and no bullet. Anything that is a
  list stays a list, because a medium decides what a list looks like.
  """

  @doc """
  What the assertion promises, as a sentence a process owner can be read.

  `trace` is the one declaration with no `label`, so a technical name is all there
  would otherwise be — and a report saying `month_opens_or_is_blocked` does not meet
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
  """
  @spec outcome(map()) :: String.t()
  def outcome(a) do
    state =
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

    state <> via(a) <> suspended(a) <> earlier_declaration(a)
  end

  @doc """
  The role a finding about this process goes to, or `nil`.

  `nil` rather than a placeholder: an invented addressee is worse than none, because
  it sends the finding to somebody who never agreed to receive it.
  """
  @spec accountable(String.t() | nil) :: String.t() | nil
  def accountable(nil), do: nil
  def accountable(role), do: "Accountable: #{role}."

  @doc "A confirmed process declaration, as a sentence."
  @spec declaration(map()) :: String.t()
  def declaration(%{key: :cadence, value: value}), do: "Due: every #{amount(value)}."

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
    # `PNS.Duration.humanize/1` drops the numeral at a count of one precisely because
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

  @doc "A step, by its business labels. The technical names are for whoever writes code."
  @spec step(map()) :: String.t()
  def step(s), do: "#{s.from_label} → #{s.to_label}"

  @doc "A step whose work is sitting in a queue — which is not a step nobody took."
  @spec step_in_flight(map()) :: String.t()
  def step_in_flight(s), do: "#{step(s)} — in progress, #{s.in_flight} queued"

  @doc """
  A step that is attempted and does not succeed.

  Kept apart from "never carried out" because it is a different finding for a
  different reader: there the question is whether the step is still agreed, here the
  code is broken. Merging them puts a bug in front of the client as a question about
  their process.
  """
  @spec step_failing(map()) :: String.t()
  def step_failing(s), do: "#{step(s)} — failed in #{runs(s.failing)}"

  @doc "A count of runs, with the numeral where it belongs."
  @spec runs(non_neg_integer()) :: String.t()
  def runs(1), do: "1 run"
  def runs(n), do: "#{n} runs"

  @doc "The sentences that stand in for a section with nothing in it."
  @spec no_runs() :: String.t()
  def no_runs, do: "The agreed steps cannot be judged: there was not a single run in this period."

  @doc false
  @spec all_steps_carried_out() :: String.t()
  def all_steps_carried_out, do: "All agreed steps were carried out in this period."

  @doc false
  @spec no_drift() :: String.t()
  def no_drift, do: "None: nothing happened outside the agreement."

  # Attached to the count it qualifies, never to the sentence as a whole. Appended to
  # whatever `state` said, it produced "BREACHED in 1 of 5 runs. (including 1 via the
  # fallback ending…)", where "including" reads as qualifying the breaches.
  @spec via(map()) :: String.t()
  defp via(%{satisfied_via_or_else: 0}), do: ""
  defp via(%{satisfied: 0}), do: ""

  defp via(a) do
    " Of those that were met, #{runs(a.satisfied_via_or_else)} reached the fallback " <>
      "ending, which conforms to the rule."
  end

  # Named as somebody else's outage, and **not** counted among the breaches. That is
  # the whole value of the fourth verdict: without it these runs read as "you broke
  # your own agreement" when a system they depend on stopped answering.
  @spec suspended(map()) :: String.t()
  defp suspended(%{suspended: 0}), do: ""

  defp suspended(a) do
    " Suspended: #{runs(a.suspended)} — an external dependency was unavailable within the " <>
      "rule's window, so this is not a breach on the client's side."
  end

  # Runs that began before this assertion last changed were judged under a promise
  # that is no longer the declared one. Counted, not listed, with the date, so a
  # reader can narrow the period themselves.
  @spec earlier_declaration(map()) :: String.t()
  defp earlier_declaration(%{under_earlier_declaration: 0}), do: ""

  defp earlier_declaration(a) do
    " #{runs(a.under_earlier_declaration)} began before this rule was last changed " <>
      "(#{Date.to_string(DateTime.to_date(a.declaration_changed_at))}) and are not counted " <>
      "here — they were judged under a different promise."
  end

  @spec amount({pos_integer(), atom()}) :: String.t()
  defp amount(duration), do: PNS.Duration.humanize(duration)
end

defmodule EhOsContract.Duration do
  @moduledoc """
  The DSL's time units — **one source of truth for the gate and for the arithmetic.**

  It exists because of a specific failure. `within: {1, :month}` passed
  compilation, because the gate had no list of allowed units, and blew up only
  **at run time**, during assertion evaluation, at the client's. A textbook shape
  of drift: the DSL accepted a word the mechanism could not compute.

  It was invisible because both our contracts count in days — TaxVision `{2, :day}`,
  and the universality gate fixture `{3, :day}` and `{90, :day}`. Writing the
  second one, the habit of the first was copied without thinking: for a treatment
  episode `{3, :month}` is more natural than 90 days. The universality gate let
  the habit through, because it checks the vocabulary rather than the mechanisms.

  **Calendar units are not here, and will not arrive quietly.** A month has no
  fixed length, so shifting by one requires calendar arithmetic and a decision
  about what a month after 31 January is. That is a decision, not an
  implementation detail — until it is taken, `within` accepts only fixed-length
  units, and a contract using `:month` **does not compile**.

  `cadence: {1, :month}` is a different matter and stays legal: cadence says how
  often an instance is due, and nothing computes it today. Once something does —
  the stalled-process monitor — the same calendar question comes back here.

  **27 September 2026, plan EM3: the decision was taken, for timers only.** The user
  chose ESDM's calendar arithmetic for a process manager's timer: `wait: {1, :month}`
  fires on the same day of the next month, and on its last day when there is no such
  day — 31 January, then the end of February (`calendar_shift/2`, which is
  `DateTime.shift/2`). `within` and `deadline` stay in fixed units, since the report
  measures elapsed time against them and a month there would make one run's window
  longer than another's. **The calendar is UTC's**, since the log is: an event at 00:30 in
  Warsaw on 31 March is 22:30 UTC on the 30th, so a month later is 22:30 UTC on 30 April,
  which is 1 May in Warsaw. A business that needs its own zone's month sets the timer
  `at:` a moment its state computes.
  """

  @seconds %{second: 1, minute: 60, hour: 3600, day: 86_400}

  @typedoc """
  A duration as a count of one supported unit.

  Zero is legal — it reads as "in the same instant" — and enforced together with the
  unit at the `trace` compile gate (`EhOsContract.Contract`). Negative is not: the deadline
  would land before the window opened.
  """
  @type t :: {non_neg_integer(), unit()}

  @typedoc "A time unit convertible to seconds without a calendar."
  @type unit :: :second | :minute | :hour | :day

  @doc "The units convertible to seconds without a calendar."
  @spec units() :: [unit()]
  def units, do: Map.keys(@seconds)

  @doc """
  A duration as English prose, for anything a person reads — the conformance
  report's sentences and the declared-shape diagram's arrows.

  A count of one drops the numeral, because both callers put a word in front of it:
  *Due: every month*, *within 2 days*.

  It lives here rather than in either caller because this module is already the one
  source of truth about units, and the two were about to disagree. The version this
  replaces listed the plurals by hand for `:month` and `:day` only, so every other
  unit fell through to a branch that produced **"within 24 hour"**. Nobody saw it
  until a contract used hours, which took until the fourth contract — the same
  shape of miss as `within: {1, :month}`, which also compiled until somebody wrote
  it.

  `:month` is accepted here although `within` refuses it: `cadence` takes it, and
  this function serves the reader rather than the evaluator.
  """
  @spec humanize({pos_integer(), atom()}) :: String.t()
  def humanize({1, unit}), do: "#{unit}"
  def humanize({n, unit}), do: "#{n} #{unit}s"

  @doc "Shifts a moment by a duration. The log is in UTC, so a day is 86 400 seconds."
  @spec shift(DateTime.t(), t()) :: DateTime.t()
  def shift(%DateTime{} = at, {n, unit}) do
    case Map.fetch(@seconds, unit) do
      {:ok, s} -> DateTime.add(at, n * s, :second)
      :error -> raise ArgumentError, message(unit)
    end
  end

  @calendar [:week, :month, :year]

  @doc "The calendar units a timer may wait for, besides the fixed ones."
  @spec calendar_units() :: [:week | :month | :year]
  def calendar_units, do: @calendar

  @doc """
  Shifts a moment by a duration that may count calendar units: a week, a month or a
  year after it, with a month after the 31st landing on the month's last day. Fixed
  units shift as `shift/2` does.
  """
  @spec calendar_shift(DateTime.t(), {non_neg_integer(), atom()}) :: DateTime.t()
  def calendar_shift(%DateTime{} = at, {n, unit}) when unit in @calendar,
    do: DateTime.shift(at, [{unit, n}])

  def calendar_shift(%DateTime{} = at, duration), do: shift(at, duration)

  @doc """
  The rejection message for an unsupported unit.

  Shared by the compile gate and by `shift/2` so the two cannot explain the same
  refusal differently.
  """
  @spec message(atom()) :: String.t()
  def message(unit) do
    "unsupported time unit #{inspect(unit)}. Allowed: #{inspect(units())}. " <>
      "A window or a deadline is measured as elapsed time, so it counts fixed units; only a " <>
      "timer's wait may count #{inspect(@calendar)}, by the calendar."
  end
end

defmodule EhOsContract.Contract.Rules.Durations do
  # R1 and R6 of v2 §6, what is left of them since a contract no longer declares a
  # process (plan DD, P2h, #221): a process, its stages, promises and deadline, is a
  # module of its own, `EhOsContract.Process`, checked by `EhOsContract.Process.Rules`.
  #
  # - **R1.** A contract declares something: a contract with nothing in it describes
  #   nothing.
  # - **R6.** A process manager's timer waits a non-negative number of a fixed unit
  #   (`EhOsContract.Duration`), or of weeks, months and years — a timer by the
  #   calendar, the user's choice of 27 September 2026 (plan EM3). `problems/2` says
  #   what is wrong with a duration, for a process module's `within` and `deadline` too.
  @moduledoc false

  alias EhOsContract.DslRules
  alias EhOsContract.Duration

  @calendar Duration.calendar_units()

  @doc false
  @spec check(map()) :: [DslRules.violation()]
  def check(declarations), do: empty(declarations) ++ waits(declarations)

  # A contract with nothing in it describes nothing; the error names the module
  # without a line, since there is no declaration to point at.
  defp empty(declarations) do
    if declarations |> Map.delete(:module) |> Map.values() |> List.flatten() == [],
      do: [
        {"R1: a contract declares what decides in it, or what reacts, and this one declares " <>
           "nothing", nil}
      ],
      else: []
  end

  defp waits(d) do
    for pm <- d.process_managers,
        t <- pm.timers,
        t.wait != nil,
        problem <- problems(t.wait, Duration.units() ++ @calendar) do
      {"R6: timer #{inspect(t.name)}: wait #{problem}", t}
    end
  end

  @doc false
  # What is wrong with a duration a rule counts in `units`, one sentence per problem
  # (R6): read by a process module's rules too (`EhOsContract.Process.Rules`).
  @spec problems(term(), [atom()]) :: [String.t()]
  def problems({n, unit}, units) do
    count =
      if is_integer(n) and n >= 0,
        do: [],
        else: ["counts #{inspect(n)}, which is not a non-negative integer"]

    unit =
      cond do
        unit in units ->
          []

        unit in @calendar ->
          [
            "is in #{inspect(unit)}, a calendar unit, which only a timer's wait may use"
          ]

        true ->
          ["is in #{inspect(unit)}, which is not one of #{inspect(units)}"]
      end

    count ++ unit
  end

  def problems(other, _units), do: ["is #{inspect(other)}, which is not {count, unit}"]
end

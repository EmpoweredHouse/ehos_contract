defmodule EhOsContract.EffectJobErrorsTest do
  @moduledoc """
  v2 plan, E8 (after the E8b review): **what Oban keeps of a failed effect.** Oban
  writes a failed attempt into `oban_jobs.errors` — the exception blamed and
  formatted with its stacktrace, or `inspect/1` of the reason — and an erasure never
  reaches that table. So an effect's failure reaches Oban without any value, on the
  invented `ShreddingRig.Greet`.
  """

  use EhOsContract.DataCase, async: false

  alias EhOsContract.{Actor, EffectJob}
  alias ShreddingRig.Members
  alias ShreddingRig.Members.Commands.Join

  defp job_for!(name) do
    {:ok, _} =
      EhOsContract.dispatch(
        Members,
        %Join{
          membership_id: "membership-#{System.unique_integer([:positive])}",
          member_id: "member-anna",
          name: name,
          contacts: [
            %ShreddingRig.Domain.Values.Contact{
              member_id: "member-anna",
              phone: "+48 600 100 200"
            }
          ],
          plan: :basic
        },
        actor: Actor.credential("u-clerk", ["shredding_rig.join"])
      )

    [job] = Repo.all(from(j in Oban.Job, where: j.worker == ^inspect(EffectJob)))
    job
  end

  # What Oban writes for a raised failure (`Oban.Job.format_attempt/1`).
  defp as_oban_keeps(kind, error, stacktrace) do
    {blamed, stacktrace} = Exception.blame(kind, error, stacktrace)
    Exception.format(kind, blamed, stacktrace)
  end

  test "an effect that raises with a name reaches Oban without it" do
    job = job_for!("Crash Anna")

    {error, stacktrace} =
      try do
        EffectJob.perform(job)
        flunk("the effect was to raise")
      rescue
        error -> {error, __STACKTRACE__}
      end

    assert error.__struct__ == EffectJob.Failure
    kept = as_oban_keeps(:error, error, stacktrace)

    assert kept =~
             "effect shredding_rig.members:effect:greet raised MatchError on the event at position"

    refute kept =~ "Crash Anna"
    assert Enum.all?(stacktrace, fn {_, _, arity, _} -> is_integer(arity) end)
  end

  # The test's own name is in the stacktrace Oban keeps, so it names the case, not
  # the value.
  for {name, what, case_name} <- [
        {"Exit Anna", "exited with {:deliver, ...}", "exits"},
        {"Throw Anna", "threw {:deliver, ...}", "throws"},
        {"Link Anna", "exited with a value", "crashes a linked task"},
        {"Spawn Anna", "had a linked process exit with a value",
         "leaves a linked process crashed"}
      ] do
    @tag :capture_log
    test "an effect that #{case_name} with a name reaches Oban without it" do
      job = job_for!(unquote(name))

      {error, stacktrace} =
        try do
          EffectJob.perform(job)
          flunk("the effect was to fail")
        rescue
          error -> {error, __STACKTRACE__}
        end

      assert error.__struct__ == EffectJob.Failure
      assert error.message =~ unquote(what)

      kept = as_oban_keeps(:error, error, stacktrace)
      refute kept =~ unquote(name)
      assert Enum.all?(stacktrace, &is_integer(elem(&1, tuple_size(&1) - 2)))

      # The job's process traps exits no longer than the effect runs.
      assert Process.info(self(), :trap_exit) == {:trap_exit, false}
    end
  end

  test "an effect that answers an error with a name reaches Oban without it" do
    job = job_for!("Bounce Anna")

    assert {:error, reason} = EffectJob.perform(job)
    assert reason =~ "answered {:error, {:bounced, ...}} on the event at position"
    refute inspect(reason) =~ "Bounce Anna"
  end

  test "control: an effect that succeeds finishes the job" do
    assert EffectJob.perform(job_for!("Anna Nowak")) == :ok
  end
end

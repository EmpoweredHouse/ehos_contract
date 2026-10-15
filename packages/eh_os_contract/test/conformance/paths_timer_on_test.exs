defmodule EhOsContract.PathsTimerOnTest.Chase do
  @moduledoc """
  THIS CONTRACT IS INVENTED. IT IS NOT CLIENT MATERIAL.

  A manager that issues one command from its timer and another from an `on` naming the
  same timer: both run on the timer's firing.
  """

  use EhOsContract.Contract,
    domain: DispatchRig.Domain,
    context: :ledger,
    id: "dispatch_rig.timer_on_paths"

  aggregate :case, "Case" do
    identity :case_id

    command :open_case, "Open a case", by: :clerk, emits: :case_opened
    command :remind, "Remind", emits: :reminded
    command :escalate, "Escalate", emits: :escalated

    event :case_opened, "Case opened"
    event :reminded, "Reminded"
    event :escalated, "Escalated"
  end

  process_manager :chase, "Chase a case" do
    correlate :case_id

    starts_on :case_opened, sets: :due
    on :due, issues: :escalate
    timer :due, "Due", wait: {1, :day}, issues: :remind

    ends_on :escalated
  end

  scenario "a case is opened" do
    command :open_case
    expect :case_opened
  end
end

defmodule EhOsContract.PathsTimerOnTest do
  # Plan DD, C1 (#304), review: what an `on` naming a timer issues runs on the timer's
  # firing, so it is a path from the timer, as what the timer itself issues is.
  use ExUnit.Case, async: true

  alias EhOsContract.Paths

  test "a command an `on` naming a timer issues is a path from that timer" do
    declared =
      for %{from: from, via: via, to: to} <- Paths.declared(EhOsContract.PathsTimerOnTest.Chase),
          do: {from.name, via && via.name, to && to.name}

    assert {:due, :chase, :remind} in declared
    assert {:due, :chase, :escalate} in declared
  end
end

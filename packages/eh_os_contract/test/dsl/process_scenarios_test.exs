defmodule EhOsContract.ProcessScenariosTest do
  @moduledoc """
  Plan DD, S2 (#251): **a process module's scenarios**, which show a promise judged:
  the events that happened and when, the moments an external system was down, and the
  verdict the promise gets at a moment. What one module can get wrong in them is
  refused at compile time (L2): S1, S2 and S3 as a contract's scenarios have them, and
  their shape under S11. Each refusal has a control beside it that compiles.

  The domain and the contracts the fixtures name do not exist: a process module names
  them without a compile dependency (v2 §8).
  """

  use EhOsContract.DslCase, async: false

  @fixtures EhOsContract.Fixtures
  @domain EhOsContract.Fixtures.ProcScenarioClinic

  setup_all do
    compile(
      """
      defmodule #{inspect(@domain)} do
        use EhOsContract.Domain, name: :clinic, language: :pl

        context :reporting, "Reports", subdomain: :core
        actor :reception, :human, "Reception", context: :reporting
        actor :register_link, :system, "Registry integration", backed_by: :register, context: :reporting
        external :register, "Medical incident registry", direction: :bidirectional
        external :mail, "Mail", direction: :outbound
        external :archive, "Archive", direction: :outbound

        subdomain :core, "Core", type: :core
      end
      """,
      "proc_scenario_clinic.ex"
    )

    :ok
  end

  # `:report_sent` depends on the register; nothing depends on the mail, which an effect
  # calls; nothing uses the archive.
  defp reporting(name) do
    """
    defmodule #{inspect(Module.concat(@fixtures, name))} do
      use EhOsContract.Contract, domain: #{inspect(@domain)}, context: :reporting, id: "clinic.#{contract_name(name)}"

      aggregate :report, "Report" do
        identity :visit_id

        command :complete_visit, "Completing the visit", by: :reception, emits: :visit_completed
        command :waive_report, "Skipping the report", by: :reception, emits: :reporting_not_required

        event :visit_completed, "Visit completed" do
          field :room, :string
        end

        event :report_sent, "Report sent", recorded_by: :register_link, depends_on: :register
        event :reporting_not_required, "Report not required"
      end

      effect :mail_report, "Sending the report by mail",
        handles: :report_sent,
        calls: :mail,
        idempotency: [key: :event_id, owner: :self]
    end
    """
  end

  # The process module `<prefix>Visit` over `<prefix>Reporting`, its promise at line 9,
  # its scenario's first given at line 17 and its outage at line 19. `waits` goes on the
  # promise's `or_else` line, so that the lines stay where they are.
  defp checked(prefix, given, outage, waits \\ "") do
    contract = inspect(Module.concat(@fixtures, "#{prefix}Reporting"))

    links([
      {"#{Macro.underscore(prefix)}_reporting.ex", reporting("#{prefix}Reporting")},
      {"#{Macro.underscore(prefix)}_visit.ex",
       process_module(
         "#{prefix}Visit",
         """
           correlate :visit_id

           stage :departure, include: [{#{contract}, :visit_completed}]
           stage :reporting, include: [{#{contract}, [:report_sent, :reporting_not_required]}]

           promise :reported_within_two_days do
             from :visit_completed
             eventually :report_sent
             within {2, :day}
             or_else :reporting_not_required#{waits}
           end

           scenario "the registry was down, report not sent — promise suspended", verdict: :suspended do
             given :visit_completed, #{given}, at: "2026-09-07T09:00:00Z"
             given :reporting_not_required, %{visit_id: "visit-anna"}, at: "2026-09-08T09:00:00Z"
             outage #{outage}, at: "2026-09-08T08:00:00Z"
             promise :reported_within_two_days, at: "2026-09-10T09:00:00Z"
           end
         """,
         domain: @domain
       )}
    ])
  end

  @process """
    correlate :visit_id

    stage :departure, include: [{Clinic.Scheduling, :visit_completed}]
    stage :reporting, include: [{Clinic.Reporting, [:report_sent, :reporting_not_required]}]

    ends_on [:report_sent, :reporting_not_required]

    promise :reported_within_two_days do
      from :visit_completed
      eventually :report_sent
      within {2, :day}
      or_else :reporting_not_required
    end

    promise :reported_at_all do
      from :visit_completed
      eventually :report_sent
    end
  """

  # Line 23 is the scenario, 26 its first given, 27 the second, 28 the outage, 29 the
  # trigger.
  @scenario """
    scenario "report sent the next day — promise kept",
      verdict: :satisfied,
      via: :eventually do
      given :visit_completed, %{visit_id: "visit-anna"}, at: "2026-09-07T09:00:00Z"
      given :report_sent, %{visit_id: "visit-anna"}, at: "2026-09-08T10:00:00Z"
      outage :registry, at: "2026-09-08T08:00:00Z"
      promise :reported_within_two_days, at: "2026-09-10T09:00:00Z"
    end
  """

  defp replace(body, from, to) do
    true = body =~ from
    String.replace(body, from, to)
  end

  defp refuse(scenario, fragment, line \\ nil) do
    source = process_module("Visit", @process <> "\n" <> scenario)
    assert_refused(source, "visit.ex", fragment, line)
  end

  describe "a scenario of a promise" do
    test "compiles into the model, each given's moment kept where it is set" do
      scenario =
        replace(
          @scenario,
          ~s|given :report_sent, %{visit_id: "visit-anna"}, at: "2026-09-08T10:00:00Z"|,
          ~s|given :report_sent, %{visit_id: "visit-anna"}|
        )

      model = compile_process("Visit", @process <> "\n" <> scenario)

      assert model.scenarios == [
               %{
                 description: "report sent the next day — promise kept",
                 verdict: :satisfied,
                 via: :eventually,
                 given: [
                   %{
                     event: :visit_completed,
                     data: %{visit_id: "visit-anna"},
                     at: "2026-09-07T09:00:00Z"
                   },
                   %{event: :report_sent, data: %{visit_id: "visit-anna"}}
                 ],
                 outages: [%{external: :registry, at: "2026-09-08T08:00:00Z"}],
                 promise: %{name: :reported_within_two_days, at: "2026-09-10T09:00:00Z"}
               }
             ]
    end

    test "a module without scenarios keeps its model and its version" do
      without = compile_process("Visit", @process)
      refute Map.has_key?(without, :scenarios)
      refute Map.has_key?(without.digests, "scenario:*")

      with_one = compile_process("Visit", @process <> "\n" <> @scenario)
      assert Map.has_key?(with_one.digests, "scenario:*")
      refute with_one.version == without.version
      assert Map.delete(with_one.digests, "scenario:*") == without.digests
    end
  end

  describe "S1: what the scenario judges" do
    test "a scenario with no promise to judge is refused" do
      scenario =
        replace(
          @scenario,
          ~s|  promise :reported_within_two_days, at: "2026-09-10T09:00:00Z"\n|,
          ""
        )

      refuse(scenario, ~r/S1: scenario "report.*" judges no promise/, 23)
    end

    test "a scenario that judges two promises is refused" do
      scenario =
        replace(
          @scenario,
          ~s|  promise :reported_within_two_days, at: "2026-09-10T09:00:00Z"\n|,
          ~s|  promise :reported_within_two_days, at: "2026-09-10T09:00:00Z"\n| <>
            ~s|    promise :reported_at_all, at: "2026-09-10T09:00:00Z"\n|
        )

      refuse(scenario, "judges 2 promises; a scenario judges exactly one", 23)
    end

    test "a promise the module does not make is refused, with the closest one" do
      scenario =
        replace(@scenario, "promise :reported_within_two_days,", "promise :reported_in_two_days,")

      refuse(
        scenario,
        "judges promise :reported_in_two_days, which process \"clinic.visit\" does not make; " <>
          "did you mean :reported_within_two_days?",
        29
      )
    end

    test "two scenarios with one description are refused" do
      refuse(@scenario <> "\n" <> @scenario, ~s|has two scenarios described "report|)
    end
  end

  describe "S2: the givens" do
    test "a given of an event the process does not include is refused" do
      scenario = replace(@scenario, "given :report_sent,", "given :report_queued,")

      refuse(
        scenario,
        "S2: scenario \"report sent the next day — promise kept\": given " <>
          ":report_queued is not an event of the run of process \"clinic.visit\"",
        27
      )
    end
  end

  describe "S3: the moments" do
    test "a given's at: that is no timestamp is refused" do
      scenario = replace(@scenario, ~s|at: "2026-09-08T10:00:00Z"|, ~s|at: "2026-09-08"|)

      refuse(
        scenario,
        ~s|given :report_sent, at: "2026-09-08" is not an ISO 8601 timestamp with an offset|,
        27
      )
    end

    test "a given earlier than the given before it is refused" do
      scenario =
        replace(@scenario, ~s|at: "2026-09-08T10:00:00Z"|, ~s|at: "2026-09-06T10:00:00Z"|)

      refuse(
        scenario,
        "S3: scenario \"report sent the next day — promise kept\": given " <>
          ":report_sent happened at 2026-09-06T10:00:00Z, before the given before it " <>
          "(2026-09-07T09:00:00Z)",
        27
      )
    end

    test "two givens at one moment compile" do
      scenario =
        replace(@scenario, ~s|at: "2026-09-08T10:00:00Z"|, ~s|at: "2026-09-07T09:00:00Z"|)

      assert %{scenarios: [_]} = compile_process("Visit", @process <> "\n" <> scenario)
    end

    test "an outage's or the trigger's at: that is no timestamp is refused" do
      outage = replace(@scenario, ~s|at: "2026-09-08T08:00:00Z"|, ~s|at: "Tuesday"|)
      refuse(outage, ~s|outage :registry, at: "Tuesday" is not an ISO 8601 timestamp|, 28)

      trigger = replace(@scenario, ~s|at: "2026-09-10T09:00:00Z"|, ~s|at: "Wednesday"|)
      refuse(trigger, ~s|promise, at: "Wednesday" is not an ISO 8601 timestamp|, 29)
    end
  end

  describe "S11: the shape" do
    test "a scenario that says no verdict is refused" do
      scenario =
        replace(@scenario, ",\n    verdict: :satisfied,\n    via: :eventually do", " do")

      refuse(
        scenario,
        "S11: scenario \"report sent the next day — promise kept\" says no verdict",
        23
      )
    end

    test "via: without a verdict is refused for the verdict alone" do
      scenario =
        replace(@scenario, "verdict: :satisfied,\n    via: :eventually", "via: :eventually")

      message = refuse(scenario, "says no verdict", 23)
      refute message =~ "via: is the route"
    end

    test "a verdict the promise cannot get is refused" do
      unexcused =
        @scenario
        |> replace("verdict: :satisfied,\n    via: :eventually", "verdict: :suspended")
        |> replace(~s|    outage :registry, at: "2026-09-08T08:00:00Z"\n|, "")

      refuse(unexcused, "verdict :suspended, and no outage excuses the promise", 23)

      unbounded =
        @scenario
        |> replace("verdict: :satisfied,\n    via: :eventually", "verdict: :violated")
        |> replace("promise :reported_within_two_days,", "promise :reported_at_all,")

      refuse(
        unbounded,
        "verdict :violated, and promise :reported_at_all has no within, so its window never " <>
          "closes; it is only :satisfied or :pending",
        23
      )
    end

    test "a verdict outside the four is refused" do
      scenario =
        replace(@scenario, "verdict: :satisfied,\n    via: :eventually", "verdict: :kept")

      refuse(
        scenario,
        "verdict :kept is not one of [:satisfied, :violated, :pending, :suspended]",
        23
      )
    end

    test "via: on a promise not kept is refused" do
      scenario = replace(@scenario, "verdict: :satisfied", "verdict: :violated")

      refuse(
        scenario,
        "via: is the route by which a promise was kept, and a promise :violated was not kept",
        23
      )
    end

    test "a route outside the two is refused" do
      scenario = replace(@scenario, "via: :eventually", "via: :registry")
      refuse(scenario, "via :registry is not one of [:eventually, :or_else]", 23)
    end

    test "via: :or_else for a promise without one is refused, and compiles for one with it" do
      without =
        @scenario
        |> replace("via: :eventually", "via: :or_else")
        |> replace("promise :reported_within_two_days,", "promise :reported_at_all,")

      refuse(
        without,
        "via :or_else, and promise :reported_at_all has no or_else; it is kept only by :report_sent",
        23
      )

      with_it = replace(@scenario, "via: :eventually", "via: :or_else")
      assert %{scenarios: [_]} = compile_process("Visit", @process <> "\n" <> with_it)
    end

    test "a scenario without the event that opens the promise is refused" do
      scenario =
        replace(
          @scenario,
          ~s|  given :visit_completed, %{visit_id: "visit-anna"}, at: "2026-09-07T09:00:00Z"\n|,
          ""
        )

      refuse(
        scenario,
        "gives no :visit_completed, which opens promise :reported_within_two_days; without it no run is judged",
        23
      )
    end

    test "a given or an outage after the moment of judgement is refused" do
      given = replace(@scenario, ~s|at: "2026-09-10T09:00:00Z"|, ~s|at: "2026-09-08T09:00:00Z"|)

      refuse(
        given,
        "S11: scenario \"report sent the next day — promise kept\": given " <>
          ":report_sent at 2026-09-08T10:00:00Z is after the moment the promise is judged, " <>
          "2026-09-08T09:00:00Z",
        27
      )

      outage = replace(@scenario, ~s|at: "2026-09-08T08:00:00Z"|, ~s|at: "2026-09-11T08:00:00Z"|)

      refuse(
        outage,
        "outage :registry at 2026-09-11T08:00:00Z is after the moment the promise is judged",
        28
      )
    end

    test "a given without at: is dated a minute after the one before, for this rule too" do
      scenario =
        @scenario
        |> replace(
          ~s|given :report_sent, %{visit_id: "visit-anna"}, at: "2026-09-08T10:00:00Z"|,
          ~s|given :report_sent, %{visit_id: "visit-anna"}|
        )
        |> replace(~s|at: "2026-09-10T09:00:00Z"|, ~s|at: "2026-09-07T09:00:30Z"|)
        |> replace(~s|outage :registry, at: "2026-09-08T08:00:00Z"\n|, "")

      refuse(scenario, "given :report_sent at 2026-09-07T09:01:00Z is after the moment", 27)
    end
  end

  describe "X9 and X4: a scenario against the contracts" do
    test "control: data the contract's event fits, and an outage of what the promise waits on" do
      assert checked("ProcScenarioFine", ~s|%{visit_id: "visit-anna", room: "12"}|, ":register") ==
               []
    end

    test "a given's data is held to the event its contract declares" do
      violations =
        checked("ProcScenarioData", ~s|%{visit_id: "visit-anna", rom: 12}|, ":register")

      assert assert_linked(violations, "X9:", "proc_scenario_data_visit.ex", 17) =~
               ~s|X9: scenario "the registry was down, report not sent — promise suspended": | <>
                 "event :visit_completed of #{inspect(@fixtures)}.ProcScenarioDataReporting: " <>
                 "no field :rom"

      assert assert_linked(violations, "needs :room", "proc_scenario_data_visit.ex", 17)

      typed = checked("ProcScenarioTyped", ~s|%{visit_id: "visit-anna", room: 12}|, ":register")
      assert assert_linked(typed, "field :room:", "proc_scenario_typed_visit.ex", 17)
    end

    test "a given that leaves out its unit's identity is refused, since runs are told apart by it" do
      violations = checked("ProcScenarioNoId", ~s|%{room: "12"}|, ":register")
      assert assert_linked(violations, "needs :visit_id", "proc_scenario_no_id_visit.ex", 17)
    end

    test "an outage of a system the promise does not wait on is refused" do
      violations = checked("ProcScenarioMail", ~s|%{visit_id: "visit-anna", room: "12"}|, ":mail")

      assert assert_linked(violations, "X4:", "proc_scenario_mail_visit.ex", 19) =~
               "outage :mail is of no external promise :reported_within_two_days waits on; its " <>
                 "eventually and or_else depend on [:register], it waits on no other, and an " <>
                 "outage of anything else excuses nothing"
    end

    test "control: an outage of a system the promise waits_on through an earlier step" do
      assert checked(
               "ProcScenarioWaits",
               ~s|%{visit_id: "visit-anna", room: "12"}|,
               ":mail",
               "; waits_on [:mail]"
             ) == []
    end

    test "waits_on names an external of the domain, and not one its events already depend on" do
      unknown =
        checked(
          "ProcScenarioWaitsPost",
          ~s|%{visit_id: "visit-anna", room: "12"}|,
          ":register",
          "; waits_on :maill"
        )

      assert assert_linked(unknown, "X4: promise", "proc_scenario_waits_post_visit.ex", 9) =~
               "X4: promise :reported_within_two_days: waits_on :maill is not an external of " <>
                 "#{inspect(@domain)}; did you mean :mail?"

      twice =
        checked(
          "ProcScenarioWaitsTwice",
          ~s|%{visit_id: "visit-anna", room: "12"}|,
          ":register",
          "; waits_on [:register]"
        )

      assert assert_linked(twice, "X4: promise", "proc_scenario_waits_twice_visit.ex", 9) =~
               "X4: promise :reported_within_two_days: waits_on :register is what its " <>
                 "eventually or or_else already depends_on, which excuses it without saying so; " <>
                 "leave it out of waits_on"
    end

    test "waits_on names a system a contract the process includes uses, or no outage reaches it" do
      unused =
        checked(
          "ProcScenarioWaitsArchive",
          ~s|%{visit_id: "visit-anna", room: "12"}|,
          ":register",
          "; waits_on [:archive]"
        )

      assert assert_linked(unused, "X4: promise", "proc_scenario_waits_archive_visit.ex", 9) =~
               "X4: promise :reported_within_two_days: waits_on :archive is used by no " <>
                 "contract the process includes: no event of one depends_on it and no effect " <>
                 "calls it"
    end
  end
end

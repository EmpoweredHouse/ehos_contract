defmodule EhOsContract.ProcessModuleTest do
  @moduledoc """
  Plan DD, P2b (#205): **a process written as a module of its own**, `use
  EhOsContract.Process`. It compiles to a model of kind `:process`, and what one module
  can get wrong is refused at compile time (L2) under the contract's codes. Each
  refusal names the declaration's file and line, and has a control beside it that
  compiles.

  The domain and the contracts the fixtures name do not exist: a process module names
  them without a compile dependency (v2 §8).
  """

  use EhOsContract.DslCase, async: false

  alias EhOsContract.Model

  # Line 4 is `correlate`, line 6 the first stage, line 12 `ends_on`, line 14 the promise.
  @body """
    correlate :visit_id

    stage :departure, include: [{Clinic.Scheduling, :visit_completed}]
    stage :closing, "Closing", include: [{Clinic.Documentation, :visit_closed_clinically}]

    stage :reporting,
      include: [{Clinic.Reporting, [:report_queued, :report_sent, :reporting_not_required]}]

    ends_on [:report_sent, :reporting_not_required]

    promise :reported_within_two_days do
      from :visit_completed
      eventually :report_sent
      within {2, :day}
      or_else :reporting_not_required
      source "Example Act, s. 12"
    end
  """

  defp replace(body, from, to) do
    true = body =~ from
    String.replace(body, from, to)
  end

  describe "a process module" do
    test "compiles, and Model.fetch/1 returns its model" do
      model =
        compile_process("ClinicalVisit", @body <> "\n  deadline {30, :day}, unverified: true\n",
          accountable: :manager,
          source: "Workshop 2"
        )

      assert %{
               format: 1,
               kind: :process,
               module: EhOsContract.Fixtures.ClinicalVisit,
               id: "clinic.clinical_visit",
               label: "Visit",
               domain: Clinic,
               accountable: :manager,
               source: "Workshop 2",
               correlate: [:visit_id],
               ends_on: [:report_sent, :reporting_not_required],
               deadline: %{amount: 30, unit: :day, unverified: true}
             } = model

      assert model.stages == [
               %{
                 name: :departure,
                 label: nil,
                 includes: [%{contract: Clinic.Scheduling, event: :visit_completed}]
               },
               %{
                 name: :closing,
                 label: "Closing",
                 includes: [%{contract: Clinic.Documentation, event: :visit_closed_clinically}]
               },
               %{
                 name: :reporting,
                 label: nil,
                 includes: [
                   %{contract: Clinic.Reporting, event: :report_queued},
                   %{contract: Clinic.Reporting, event: :report_sent},
                   %{contract: Clinic.Reporting, event: :reporting_not_required}
                 ]
               }
             ]

      assert [
               %{
                 name: :reported_within_two_days,
                 from: :visit_completed,
                 eventually: :report_sent,
                 within: %{amount: 2, unit: :day},
                 or_else: :reporting_not_required,
                 unverified: false,
                 source: "Example Act, s. 12"
               }
             ] = model.promises

      assert is_binary(model.version)

      assert Map.keys(model.digests) |> Enum.sort() ==
               ["process", "promise:reported_within_two_days"] ++
                 ["stage:closing", "stage:departure", "stage:reporting"]

      assert Model.fetch(model) == model
    end

    test "waits_on is in the model and the digest only where a promise declares it" do
      without = compile_process("WaitsOnNone", @body)
      refute Map.has_key?(hd(without.promises), :waits_on)

      body =
        replace(
          @body,
          "or_else :reporting_not_required\n",
          "or_else :reporting_not_required\n    waits_on [:register, :register]\n"
        )

      with_it = compile_process("WaitsOnRegister", body)
      assert [%{waits_on: [:register]}] = with_it.promises

      # Adding the word moved no version of a promise without it; declaring it moves its own.
      assert without.digests["promise:reported_within_two_days"] ==
               compile_process("WaitsOnNoneAgain", @body).digests[
                 "promise:reported_within_two_days"
               ]

      refute with_it.digests["promise:reported_within_two_days"] ==
               without.digests["promise:reported_within_two_days"]
    end

    test "waits_on is a set: its order moves neither the promise's digest nor the deploy's" do
      waits = fn list ->
        replace(
          @body,
          "or_else :reporting_not_required\n",
          "or_else :reporting_not_required\n    waits_on #{list}\n"
        )
      end

      one = compile_process("WaitsOnOrderOne", waits.("[:register, :mail]"))
      other = compile_process("WaitsOnOrderOther", waits.("[:mail, :register]"))

      assert [%{waits_on: [:mail, :register]} = first] = one.promises
      assert [second] = other.promises

      assert one.digests["promise:reported_within_two_days"] ==
               other.digests["promise:reported_within_two_days"]

      assert EhOsContract.Deployment.promise_digest(first) ==
               EhOsContract.Deployment.promise_digest(second)
    end

    test "without a deadline or the optional options, the model says nil" do
      model = compile_process("NoDeadline", @body)

      assert %{deadline: nil, accountable: nil, source: nil} = model
    end

    test "names its contracts without a compile dependency: none of them, nor the domain, exists" do
      model = compile_process("NamesWhatIsNotThere", @body)

      for %{includes: includes} <- model.stages,
          %{contract: contract} <- includes,
          do: refute(Code.ensure_loaded?(contract))

      refute Code.ensure_loaded?(model.domain)
    end

    test "its version does not see the order of promises or of ends_on, and does see the stages'" do
      a = compile_process("OrderA", @body)

      b =
        compile_process(
          "OrderB",
          replace(
            @body,
            "ends_on [:report_sent, :reporting_not_required]",
            "ends_on [:reporting_not_required, :report_sent]"
          ),
          id: "clinic.order_a"
        )

      assert a.version == b.version

      swapped =
        @body
        |> replace("  stage :departure,", "  stage :tmp,")
        |> replace("  stage :closing,", "  stage :departure,")
        |> replace("  stage :tmp,", "  stage :closing,")

      c = compile_process("OrderC", swapped, id: "clinic.order_a")
      refute a.version == c.version
    end

    # Plan DD, V5 (#322).
    test "its version does not see its words, and its words' digest does" do
      a = compile_process("WordsA", @body)

      b =
        compile_process(
          "WordsB",
          @body
          |> replace(~s(source "Example Act, s. 12"), ~s(source "Example Act, s. 13"))
          |> replace(~s("Closing"), ~s("Closing the visit")),
          id: "clinic.words_a"
        )

      assert a.version == b.version
      assert a.digests == b.digests
      refute a.text_digest == b.text_digest

      moved = for {key, digest} <- a.text_digests, b.text_digests[key] != digest, do: key
      assert Enum.sort(moved) == ["promise:reported_within_two_days", "stage:closing"]
    end

    test "its vocabulary is the process DSL's" do
      assert EhOsContract.Process.vocabulary() == %{
               [:correlate] => [:fields],
               [:stage] => [:name, :label, :include],
               [:ends_on] => [:events],
               [:promise] => [
                 :name,
                 :from,
                 :eventually,
                 :within,
                 :or_else,
                 :waits_on,
                 :unverified,
                 :source
               ],
               [:deadline] => [:within, :unverified],
               [:scenario] => [:description, :verdict, :via],
               [:scenario, :given] => [:event, :data, :at],
               [:scenario, :outage] => [:external, :at],
               [:scenario, :promise] => [:name, :at]
             }
    end

    test "a contract and a domain are fetched as before, and a process is no contract" do
      model = compile_process("NotAContract", @body)

      assert_raise ArgumentError, ~r/is a process, not a contract/, fn ->
        Model.version(model)
      end
    end
  end

  describe "D11: the id" do
    test "an id that is not the namespace and dotted snake_case segments is refused at the use" do
      message = refuse_process("BadId", @body, id: "Clinic.Visit")

      assert message =~
               "D11: the process's id: \"Clinic.Visit\" is not a process's name: the " <>
                 "application's namespace, then dotted snake_case segments, unversioned, at " <>
                 "most 100 bytes, like \"my-shop.settlement\" (bad_id.ex:2)"
    end

    test "one segment is refused, a namespace and a segment compile" do
      assert refuse_process("OneSegment", @body, id: "clinic") =~
               "D11: the process's id: \"clinic\""

      assert %{id: "my-shop.visit"} = compile_process("TwoSegments", @body, id: "my-shop.visit")
    end
  end

  describe "N1: names" do
    test "a stage, a promise or an included event not in snake_case is refused" do
      message =
        refuse_process(
          "NotSnake",
          @body
          |> replace("stage :closing,", "stage :Closing,")
          |> replace("promise :reported_within_two_days", "promise :ReportedInTime")
          |> replace(":report_queued,", ":ReportQueued,")
        )

      assert message =~ "N1: stage :Closing is not snake_case (not_snake.ex:7)"
      assert message =~ "N1: included event :ReportQueued is not snake_case (not_snake.ex:9)"
      assert message =~ "N1: promise :ReportedInTime is not snake_case (not_snake.ex:14)"
    end

    test "two stages or two promises of one name are refused at the second" do
      message =
        refuse_process(
          "Twice",
          @body <>
            """

              stage :departure, include: [{Clinic.Billing, :visit_billed}]

              promise :reported_within_two_days do
                from :visit_completed
                eventually :report_sent
              end
            """
        )

      assert message =~
               ~s|N1: process "clinic.twice" has two stages named :departure (twice.ex:22)|

      assert message =~
               ~s|N1: process "clinic.twice" has two promises named :reported_within_two_days (twice.ex:24)|
    end

    test "two includes resolving to one event name are refused, from one contract or two" do
      message =
        refuse_process(
          "IncludedTwice",
          replace(
            @body,
            "{Clinic.Documentation, :visit_closed_clinically}",
            "{Clinic.Documentation, :visit_completed}"
          )
        )

      assert message =~
               ~s|N1: process "clinic.included_twice" includes :visit_completed twice: from | <>
                 "Clinic.Documentation in stage :closing, and from Clinic.Scheduling in stage " <>
                 ":departure; an included event is named once in the process (included_twice.ex:7)"
    end

    test "a blank label is refused, the process's at the use and a stage's at the stage" do
      message =
        refuse_process("BlankLabels", replace(@body, ~s|"Closing"|, ~s|" "|), label: "")

      assert message =~
               ~s|N1: process "clinic.blank_labels" has a blank label; say what the business | <>
                 "calls it (blank_labels.ex:2)"

      assert message =~
               "N1: stage :closing has a blank label; say what the business calls it (blank_labels.ex:7)"
    end
  end

  describe "R2 and F9: correlate" do
    test "a process without correlate is refused at the use" do
      message = refuse_process("NoCorrelate", replace(@body, "correlate :visit_id\n", ""))

      assert message =~
               ~s|R2: process "clinic.no_correlate" correlates on no field, so every event it | <>
                 "includes would belong to one run; name the fields that tell one run from " <>
                 "another, `correlate :field` (no_correlate.ex:2)"
    end

    test "an empty correlate, or a second one, is refused where it stands" do
      message =
        refuse_process("EmptyCorrelate", replace(@body, "correlate :visit_id", "correlate []"))

      assert message =~
               ~s|R2: process "clinic.empty_correlate" correlates on no field| <>
                 ", so every event it includes would belong to one run; name the fields that " <>
                 "tell one run from another (empty_correlate.ex:4)"

      message =
        refuse_process(
          "CorrelateTwice",
          replace(@body, "correlate :visit_id", "correlate :visit_id\n  correlate :patient_id")
        )

      assert message =~
               ~s|R2: process "clinic.correlate_twice" declares correlate twice; name every | <>
                 "field in one, in order (correlate_twice.ex:5)"
    end

    test "a field named twice in correlate is refused, each field once compiles" do
      assert %{correlate: [:visit_id, :patient_id]} =
               compile_process(
                 "TwoFields",
                 replace(@body, "correlate :visit_id", "correlate [:visit_id, :patient_id]")
               )

      message =
        refuse_process(
          "FieldTwice",
          replace(@body, "correlate :visit_id", "correlate [:visit_id, :visit_id]")
        )

      assert message =~
               ~s|R2: process "clinic.field_twice" correlates on :visit_id twice; a run's key | <>
                 "names each field once (field_twice.ex:4)"
    end

    test "more than six fields are refused, six compile" do
      six = "correlate [:a, :b, :c, :d, :e, :f]"

      assert %{correlate: [:a | _]} =
               compile_process("SixFields", replace(@body, "correlate :visit_id", six))

      message =
        refuse_process(
          "SevenFields",
          replace(@body, "correlate :visit_id", "correlate [:a, :b, :c, :d, :e, :f, :g]")
        )

      assert message =~
               ~s|F9: process "clinic.seven_fields": correlate has 7 fields, and a key has at | <>
                 "most 6: it is one index entry, which more fields of an :id at its bound " <>
                 "would overflow (seven_fields.ex:4)"
    end
  end

  describe "R3: stages" do
    test "a stage that includes no event is refused at the stage" do
      message =
        refuse_process(
          "EmptyStage",
          replace(
            @body,
            ~s|stage :closing, "Closing", include: [{Clinic.Documentation, :visit_closed_clinically}]|,
            ~s|stage :closing, "Closing"|
          )
        )

      assert message =~
               ~s|R3: process "clinic.empty_stage": stage :closing includes no event; a stage | <>
                 "is a step of the run, made of the contracts' events, " <>
                 "`include: [{Contract, :event}]` (empty_stage.ex:7)"
    end

    test "a stage including a contract with an empty list of events is refused too" do
      message =
        refuse_process(
          "EmptyList",
          replace(
            @body,
            "{Clinic.Documentation, :visit_closed_clinically}",
            "{Clinic.Documentation, []}"
          )
        )

      assert message =~ ~s|R3: process "clinic.empty_list": stage :closing includes no event|
    end

    test "an entry naming no event is refused beside entries that do" do
      message =
        refuse_process(
          "EmptyEntry",
          replace(
            @body,
            "[{Clinic.Documentation, :visit_closed_clinically}]",
            "[{Clinic.Documentation, :visit_closed_clinically}, {Clinic.Billing, []}]"
          )
        )

      assert message =~
               ~s|R3: process "clinic.empty_entry": stage :closing includes Clinic.Billing with | <>
                 "no event; name the events it includes, `{Contract, :event}` (empty_entry.ex:7)"

      refute message =~ "includes no event"
    end

    test "an entry whose contract is not a module is refused; a module that does not exist compiles" do
      for {name, contract} <- [{"NilContract", "nil"}, {"AtomContract", ":documentation"}] do
        message =
          refuse_process(
            name,
            replace(
              @body,
              "{Clinic.Documentation, :visit_closed_clinically}",
              "{#{contract}, :visit_closed_clinically}"
            )
          )

        file = Macro.underscore(name)

        assert message =~
                 ~s|R3: process "clinic.#{file}": stage :closing includes #{contract}, which | <>
                   "names no contract; name the contract by its module, " <>
                   "`{Contract, :event}` (#{file}.ex:7)"
      end

      assert %{stages: [_, %{includes: [%{contract: Clinic.Nowhere}]}, _]} =
               compile_process(
                 "ModuleContract",
                 replace(@body, "{Clinic.Documentation,", "{Clinic.Nowhere,")
               )
    end

    test "a process with no stage is refused at the use" do
      message = refuse_process("NoStage", "  correlate :visit_id\n")

      assert message =~
               ~s|R3: process "clinic.no_stage" declares no stage, so its runs have no events| <>
                 "; a stage includes the contracts' events, " <>
                 "`stage :name, include: [{Contract, :event}]` (no_stage.ex:2)"
    end
  end

  describe "R5: the events of the run" do
    test "a promise's from, eventually or or_else the process does not include is refused" do
      message =
        refuse_process(
          "PromiseOutside",
          @body
          |> replace("from :visit_completed", "from :visit_booked")
          |> replace("or_else :reporting_not_required", "or_else :report_waived")
        )

      assert message =~
               "R5: promise :reported_within_two_days: from :visit_booked is not an event of the " <>
                 ~s|run of process "clinic.promise_outside", which includes | <>
                 "[:report_queued, :report_sent, :reporting_not_required, " <>
                 ":visit_closed_clinically, :visit_completed] (promise_outside.ex:14)"

      assert message =~ "R5: promise :reported_within_two_days: or_else :report_waived is not"
      refute message =~ "eventually :report_sent is not"
    end

    test "an ends_on event the process does not include is refused" do
      message =
        refuse_process(
          "EndsOutside",
          replace(@body, "ends_on [:report_sent,", "ends_on [:report_confirmed,")
        )

      assert message =~
               ~s|R5: process "clinic.ends_outside" ends on :report_confirmed, which it does | <>
                 "not include; it includes [:report_queued, :report_sent, " <>
                 ":reporting_not_required, :visit_closed_clinically, :visit_completed] " <>
                 "(ends_outside.ex:12)"
    end

    test "ends_on declared twice is refused at the second" do
      message =
        refuse_process(
          "EndsOnTwice",
          replace(
            @body,
            "ends_on [:report_sent, :reporting_not_required]",
            "ends_on :report_sent"
          ) <>
            "\n  ends_on :reporting_not_required\n"
        )

      assert message =~
               ~s|R5: process "clinic.ends_on_twice" declares ends_on twice; one lists every | <>
                 "event that ends a run (ends_on_twice.ex:22)"
    end
  end

  describe "R6: durations" do
    test "a within or a deadline in a calendar unit, negative, or not {count, unit}, is refused" do
      message =
        refuse_process(
          "BadDurations",
          replace(@body, "within {2, :day}", "within {1, :month}") <>
            "\n  deadline {-1, :day}\n"
        )

      assert message =~
               "R6: promise :reported_within_two_days: within is in :month, a calendar unit, " <>
                 "which only a timer's wait may use (bad_durations.ex:14)"

      assert message =~
               ~s|R6: process "clinic.bad_durations": deadline counts -1, which is not a | <>
                 "non-negative integer (bad_durations.ex:22)"

      message = refuse_process("NotADuration", @body <> "\n  deadline 30\n")

      assert message =~
               ~s|R6: process "clinic.not_a_duration": deadline is 30, which is not {count, unit}|
    end

    test "a within or a deadline longer than 100 years is refused" do
      message =
        refuse_process(
          "CenturyDurations",
          replace(@body, "within {2, :day}", "within {36_601, :day}") <>
            "\n  deadline {878_401, :hour}\n"
        )

      assert message =~
               "R6: promise :reported_within_two_days: within is longer than 100 years, the " <>
                 "longest a duration may be"

      assert message =~
               ~s|R6: process "clinic.century_durations": deadline is longer than 100 years|
    end

    test "control: a within and a deadline of exactly 100 years compile" do
      assert %{deadline: %{amount: 36_600, unit: :day}} =
               compile_process(
                 "CenturyDurationsKept",
                 replace(@body, "within {2, :day}", "within {36_600, :day}") <>
                   "\n  deadline {36_600, :day}\n"
               )
    end

    test "a deadline declared twice is refused at the second" do
      message =
        refuse_process(
          "DeadlineTwice",
          @body <> "\n  deadline {30, :day}\n  deadline {40, :day}\n"
        )

      assert message =~
               ~s|R6: process "clinic.deadline_twice" declares deadline twice (deadline_twice.ex:23)|
    end

    test "a deadline without ends_on is refused: it measures a run to an end, and nothing ends it" do
      body = replace(@body, "ends_on [:report_sent, :reporting_not_required]\n", "")

      assert %{deadline: nil} = compile_process("NoEndNoDeadline", body)

      message = refuse_process("DeadlineNoEnd", body <> "\n  deadline {30, :day}\n")

      assert message =~
               ~s|R6: process "clinic.deadline_no_end" declares a deadline, which measures a | <>
                 "run to its end, and nothing ends this one; name the events that do, " <>
                 "`ends_on [:event]` (deadline_no_end.ex:21)"
    end
  end
end

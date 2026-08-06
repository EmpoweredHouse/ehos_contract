defmodule PNS.UniversalityGateTest do
  @moduledoc """
  Stage 1.2: **the universality gate.**

  Until now the evidence that the DSL is not an accounting DSL read "one contract,
  one domain, one author" — which was not evidence. `UniversalityGate.TreatmentEpisode`
  is a second contract from a domain with nothing to do with accounting, and it is
  **deliberately invented** (see its moduledoc).

  The acceptance criterion is hard: **zero new words in the DSL.** The first test
  below pins the vocabulary, so the criterion is checked rather than declared.
  """

  # `DataCase`, not `ExUnit.Case`: since 5 August the gate also exercises the
  # **mechanisms**, not only the vocabulary — and those need the event log.
  use Taxvision.DataCase, async: false

  @contract UniversalityGate.TreatmentEpisode
  @taxvision Taxvision.Contracts.AccountingMonth

  describe "acceptance criterion: zero new words" do
    test "the DSL vocabulary did not grow to fit a second domain" do
      # This test is the entire criterion of stage 1.2. If it ever stops passing,
      # it means describing another domain required adding a word — that is, that
      # the DSL is badly designed, not that the test is out of date. **Then the
      # DSL gets fixed, not this test.**
      #
      # `population` was the only word that ever failed this test, and it tends to
      # come back. It is not here, and that is deliberate.
      #
      # The order carries information: **required first, then optional**, because
      # the vocabulary is derived from `schema/0`, where the two are separated.
      # They used to be two separate lists, that is, two things to drift apart.
      assert PNS.Contract.vocabulary() == %{
               event: [:label, :owner, :payload, :retain, :depends_on, :identity, :process, :stage, :terminal],
               process: [:label, :instance, :stages, :cadence, :deadline, :unverified],
               external: [:label, :expected_latency, :unavailable_looks_like],
               rule: [:label, :function, :source],
               example: [:rule, :command, :given, :then, :rejected_with],
               trace: [:from, :eventually, :within, :or_else]
             }
    end

    test "no payload type knows what anybody's business calls a thing" do
      # The other half of the criterion, and the half the gate itself cannot see.
      # "Zero new words" asks whether describing a second domain forced something to
      # be **added**; it is blind to a word that is already there and should not be.
      # `:period` passed the vocabulary test for two days while naming an accounting
      # month, and counting found it: the medical contract has fourteen payload
      # fields and used it zero times.
      #
      # Pinned as a literal, so adding a domain-specific type fails here the same
      # day. If a type below stops looking like a shape, the type goes — not the test.
      assert PNS.Contract.payload_types() == [:id, :string, :integer, :timestamp, :enum]
    end

    test "neither contract uses a type outside the closed set" do
      # The gate is a compile error, so this cannot fail without the build already
      # being red. It is here for the direction the gate does not cover: it counts
      # **which** types each domain actually needed, and a type no contract has ever
      # used is a candidate for removal on the same argument that removed `:period`.
      used =
        for contract <- [@taxvision, @contract],
            event <- contract.events(),
            {_field, type} <- event.payload,
            uniq: true,
            do: type

      assert used -- PNS.Contract.payload_types() == []
      assert :period not in used
    end

    test "both domains use the same set of macros and neither has its own" do
      macros =
        PNS.Contract.__info__(:macros)
        |> Keyword.keys()
        |> Enum.reject(&String.starts_with?(to_string(&1), "__"))
        |> Enum.sort()

      assert macros == [:event, :example, :external, :process, :rule, :trace]
    end

    test "the medical contract introduces no key outside the vocabulary" do
      # A check from the other side: the DSL rejects unknown keys at compile time,
      # so the mere fact that this module compiled is the proof. The test makes
      # sure the proof does not disappear through the file being deleted by
      # accident.
      assert function_exported?(@contract, :__pns_contract__, 0)
      assert length(@contract.events()) == 10
      assert Enum.map(@contract.processes(), & &1.name) == [:treatment_episode]
      assert Enum.map(@contract.traces(), & &1.name) == [:referral_reaches_a_decision, :episode_reaches_an_end]
      assert Enum.map(@contract.externals(), & &1.name) == [:payer_registry]
      assert Enum.map(@contract.rules(), & &1.name) == [:treatment_starts_only_on_confirmed_eligibility]
    end
  end

  describe "shapes TaxVision does not have" do
    test "the same event many times in one run is expressible" do
      # A fact's identity includes the session number, a run's identity does not.
      # Ten sessions are ten facts in one episode — not ten episodes and not one
      # fact repeated. Without separating `identity` from `instance`, one of the
      # two would be inexpressible.
      session = @contract.event(:session_completed)
      process = @contract.process(:treatment_episode)

      assert process.instance == [:episode_id]
      assert session.identity == [:episode_id, :session_no]
      assert process.instance -- session.identity == []
    end

    test "an event arriving without a command carries the run identity on its own" do
      referral = @contract.event(:referral_received)

      assert Map.has_key?(referral.payload, :episode_id)
      assert @contract.process_of(:referral_received).name == :treatment_episode
    end

    test "run identity from one field works the same as from two" do
      assert @contract.process(:treatment_episode).instance == [:episode_id]
      assert @taxvision.process(:accounting_month).instance == [:company_id, :period_id]
    end

    test "an event-driven process has no cadence, and that is a result rather than an oversight" do
      # `cadence` answers "how often is an instance due". An accounting month is
      # due every month; a treatment episode is never due — it starts when a
      # referral arrives.
      #
      # No word is missing: the word is optional and does not apply. But the
      # mechanism resting on it — the "never observed" window — has nowhere to get
      # its length from for this process, and that belongs in notes §9.
      assert @contract.process(:treatment_episode).cadence == nil
      assert @taxvision.process(:accounting_month).cadence == {1, :month}
    end
  end

  describe "the gates work on the second contract, not only on the first" do
    for {example, index} <- Enum.with_index(@contract.examples()) do
      @example example
      @rule @contract.rule(example.rule)

      test "an example is a test: #{example.description} (##{index})" do
        ContractExamples.run(@example, @rule)
      end
    end

    test "the instance gate computed a run key for an event from this domain" do
      {process, instance} =
        PNS.Instance.key(@contract, :session_completed, %{
          episode_id: "ep-7",
          session_no: 3,
          performed_at: "2026-08-05T09:00:00Z"
        })

      assert process == "treatment_episode"
      assert instance == "treatment_episode|ep-7"
    end

    test "the engine's registry sees both contracts" do
      PNS.Registry.load!()
      assert @contract in PNS.Registry.contracts()
      assert @taxvision in PNS.Registry.contracts()
    end
  end

  describe "the gate covers mechanisms, not only the vocabulary" do
    # This is a correction to the gate itself, found on 5 August. The 1.2
    # criterion proved the DSL could **describe** a second domain — not that the
    # engine would **work** on one. `PNS.Trace` and `PNS.Conformance` were getting
    # empty lists from this contract, so their universality was untested.
    #
    # Emitting events does not break the scope of 1.2: there are still no
    # handlers, and an emission is not a handler.

    # Returns the event, because `occurred_at` is set by the **engine** at emit
    # time rather than by the payload's `received_at` field. The assertion is
    # counted from the log's timestamp and the test has to count from the same
    # one, otherwise it measures something else.
    defp referral(episode) do
      PNS.emit!(@contract, :referral_received, %{
        episode_id: episode,
        patient_id: "p-1",
        referral_code: "ref-1",
        received_at: DateTime.utc_now() |> DateTime.to_iso8601()
      })
    end

    test "the second domain's assertion is satisfied through or_else, by the same code" do
      referral("ep-1")

      PNS.emit!(@contract, :payer_eligibility_denied, %{episode_id: "ep-1", reason: "eligibility expired"})

      assert [verdict] = PNS.Trace.evaluate(@contract, :referral_reaches_a_decision)
      assert verdict.verdict == :satisfied
      assert verdict.via == :or_else
      assert verdict.instance_id == "treatment_episode|ep-1"
    end

    test "the second domain's assertion can be violated" do
      event = referral("ep-2")

      # `within: {3, :day}` — a referral with no decision after four days.
      later = DateTime.add(event.occurred_at, 4, :day)

      assert [verdict] = PNS.Trace.evaluate(@contract, :referral_reaches_a_decision, now: later)
      assert verdict.verdict == :violated
    end

    test "a process with no declared path at all appears in the report rather than staying silent" do
      # The medical contract has no handlers, so it has no edges. The version that
      # grouped the report by edges skipped it entirely — and absence reads as
      # "there is nothing to discuss".
      reports = PNS.Conformance.untraversed_paths()
      medical = Enum.find(reports, &(&1.process == :treatment_episode))

      assert medical, "the second domain's whole process was absent from the report"
      assert medical.basis == :no_paths
      assert medical.paths == 0
    end
  end

  describe "a fake, with no implementation" do
    test "an unavailable payer registry is the absence of a decision, not a denial" do
      # The contract says the same thing in words in `unavailable_looks_like`.
      # Merging those two states denies a patient treatment because somebody
      # else's server broke — the same mistake ADR §11-12 warns about for public
      # registries.
      assert {:error, :unavailable} = UniversalityGate.PayerRegistry.check("unavailable")

      assert @contract.external(:payer_registry).unavailable_looks_like =~ "not denied"
    end

    test "the registry's answer enters the decision function as an argument" do
      # An adapter called **inside** the decision function would take away its
      # ability to separate "the payer refused" from "the registry is not
      # answering".
      {:ok, answer} = UniversalityGate.PayerRegistry.check("p-1")

      emissions =
        UniversalityGate.Eligibility.decide(%{
          command: :qualify_referral,
          episode_id: "ep-1",
          patient_id: "p-1",
          identity_confirmed: true,
          payer: answer
        })

      assert :payer_eligibility_confirmed in Enum.map(emissions, & &1.name)
    end
  end
end

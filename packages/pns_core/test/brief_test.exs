defmodule PNS.BriefTest do
  @moduledoc """
  The document that goes in front of a person before anything is built.

  Its load-bearing part is the **what depends on it** column, computed from the
  contract rather than written by hand. A hand-kept column is the first thing to
  go stale, and this one carries the document's whole argument: an event nothing
  depends on is usually a field somebody fills in, not a fact.

  Rendered here against the invented contracts rather than a client's. The
  renderer's own sentences are Polish and stay Polish — that is the one exception
  in the engine — while a contract's `label` comes out verbatim in whatever
  language its author wrote it. Pointing the test at an English fixture is
  therefore not a weaker test but a clearer one: what it asserts about the Polish
  is now unambiguously the engine's, and what it asserts about the English is
  unambiguously passed through.
  """

  use ExUnit.Case, async: true

  @contract UniversalityGate.TreatmentEpisode

  defp brief(opts \\ []), do: PNS.Brief.render(@contract, :treatment_episode, opts)

  describe "the header" do
    test "names the process in the client's words and stamps the contract version" do
      html = brief()

      assert html =~ "Treatment episode: from referral to closing"
      assert html =~ @contract.version()
      assert html =~ "<code>episode_id</code>"
    end

    test "says it is a draft, and asks for the corrections outright" do
      # A document that looks agreed collects agreement. Asking for corrections in
      # the first paragraph is the cheapest thing that changes what comes back.
      assert brief() =~ "Wersja robocza"
      assert brief() =~ "Prosimy o poprawki"
    end
  end

  describe "what depends on an event" do
    test "an event that anchors assertions says which ones" do
      html = brief()

      assert html =~ "otwiera obietnicę <em>referral_reaches_a_decision</em>"
      assert html =~ "otwiera obietnicę <em>episode_reaches_an_end</em>"
    end

    test "a terminal event, a fallback and an external dependency all count" do
      html = brief()

      assert html =~ "kończy proces"
      assert html =~ "zamyka zapasowo obietnicę <em>referral_reaches_a_decision</em>"
      assert html =~ "zależy od <code>payer_registry</code>"
    end

    test "an event nothing depends on is marked, not quietly listed" do
      # `session_completed` is a fact this contract records and nothing in it
      # reads: no handler, no assertion, not terminal, no outside call. The
      # document says so instead of pretending.
      html = brief()

      assert html =~ ~s(<tr class="empty">)
      assert html =~ "nic — sprawdzić, czy to fakt, czy pole na wizycie"
    end
  end

  describe "the promises" do
    test "each one is a sentence with its number, in the client's words" do
      html = brief()

      assert html =~
               "Po <strong>Referral received</strong> w ciągu 3 days następuje " <>
                 "<strong>Eligibility confirmed</strong>"

      assert html =~ "w ciągu 90 days"
      # The fallback is part of the sentence: an assertion whose alternative
      # ending is invisible reads as a rule with no way out.
      assert html =~ "albo <strong>Eligibility denied"
    end

    test "a process with no assertion says that is normal rather than leaving a hole" do
      html = PNS.Brief.render(ProcessShapes.Bare, :batching)

      assert html =~ "nie ma żadnego terminu i nie musi mieć"
    end
  end

  describe "the rest of the document" do
    test "an outside dependency is listed with what its unavailability looks like" do
      assert brief() =~ "no answer — eligibility undecided, not denied"
    end

    test "a process with no outside dependency gets no such section" do
      refute PNS.Brief.render(ProcessShapes.Bare, :batching) =~ "Zależności poza systemem"
    end

    test "without a diagram the document says where it would have been" do
      html = brief()

      assert html =~ "Diagramu nie dołączono"
      refute html =~ "<figure>"
    end

    test "with a diagram the svg is inlined, so the file needs no network" do
      html = brief(diagram: ~s(<svg id="x"></svg>))

      assert html =~ ~s(<figure><svg id="x"></svg></figure>)
      refute html =~ "Diagramu nie dołączono"
    end

    test "a process nobody declared is an error naming the contract" do
      assert_raise ArgumentError, ~r/declares no process :nonesuch/, fn ->
        PNS.Brief.render(@contract, :nonesuch)
      end
    end
  end
end

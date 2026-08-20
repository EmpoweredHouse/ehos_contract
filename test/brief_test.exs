defmodule PNS.BriefTest do
  @moduledoc """
  The document that goes in front of a person before anything is built.

  Its load-bearing part is the **what depends on it** column, computed from the
  contract rather than written by hand. A hand-kept column is the first thing to
  go stale, and this one carries the document's whole argument: an event nothing
  depends on is usually a field somebody fills in, not a fact.
  """

  use ExUnit.Case, async: true

  @contract Rehmed.Contracts.ClinicalVisit

  defp brief(opts \\ []), do: PNS.Brief.render(@contract, :clinical_visit, opts)

  describe "the header" do
    test "names the process in the client's words and stamps the contract version" do
      html = brief()

      assert html =~ "Wizyta: wykonanie, dokumentacja i zgłoszenie zdarzenia medycznego"
      assert html =~ @contract.version()
      assert html =~ "<code>visit_id</code>"
    end

    test "says it is a draft, and says what the session is measured by" do
      # A document that looks agreed collects agreement. This one has to collect
      # corrections, so it says so above the fold.
      assert brief() =~ "Wersja robocza do weryfikacji"
      assert brief() =~ "nie liczba przytaknięć"
    end
  end

  describe "what depends on an event" do
    test "an event that anchors assertions says which ones" do
      html = brief()

      assert html =~ "otwiera obietnicę <em>reported_or_chased_within_a_day</em>"
      assert html =~ "otwiera obietnicę <em>medical_event_reported_within_statutory_window</em>"
    end

    test "a terminal event, a fallback and an external dependency all count" do
      html = brief()

      assert html =~ "kończy proces"
      assert html =~ "zamyka zapasowo obietnicę <em>reported_or_chased_within_a_day</em>"
      assert html =~ "zależy od <code>medical_event_registry</code>"
    end

    test "an event nothing depends on is marked, not quietly listed" do
      # `visit_started` is here for a reason that has not arrived yet — the
      # regulation counts from the start of a service that spans days — so nothing
      # in this contract reads it. The document says so instead of pretending.
      html = brief()

      assert html =~ ~s(<tr class="empty">)
      assert html =~ "nic — sprawdzić, czy to fakt, czy pole na wizycie"
    end
  end

  describe "the promises" do
    test "each one is a sentence with its number, in the client's words" do
      html = brief()

      assert html =~
               "Po <strong>Pacjent wyszedł z gabinetu</strong> w ciągu 24 hours następuje " <>
                 "<strong>Wysłano zgłoszenie zdarzenia medycznego do P1</strong>"

      assert html =~ "w ciągu 2 days"
      # The fallback is part of the sentence: an assertion whose alternative
      # ending is invisible reads as a rule with no way out.
      assert html =~ "albo <strong>Usługa nie podlega zgłoszeniu"
    end

    test "a process with no assertion says that is normal rather than leaving a hole" do
      html = PNS.Brief.render(Rehmed.Contracts.PayerSettlement, :payer_settlement)

      assert html =~ "nie deklaruje żadnej obietnicy czasowej"
      assert html =~ "i to jest normalne"
    end
  end

  describe "the rest of the document" do
    test "an outside dependency is listed with what its unavailability looks like" do
      assert brief() =~ "odrzucenie zgłoszenia albo brak łączności"
    end

    test "a process with no outside dependency gets no such section" do
      refute PNS.Brief.render(Rehmed.Contracts.VisitSettlement, :visit_settlement) =~
               "Zależności poza systemem"
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

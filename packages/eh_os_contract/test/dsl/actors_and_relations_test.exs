defmodule EhOsContract.ActorsAndRelationsTest do
  @moduledoc """
  Plan EP5b: **what an actor answers for, and the words a relation pairs.** An actor
  may name its `responsibility`s, prose on rung 0 that the domain's page shows. A
  relation's `terms` are pairs, the word of its first end and of its second — in a
  partnership too, where ESDM has none — and D5 refuses a word that is not a term of
  its context's glossary; the glossary says, under a term, what the other end calls
  it. A domain declaring neither hashes as before.
  """

  use EhOsContract.DslCase, async: false

  alias EhOsContract.{Glossary, Model, Pages}

  @domain EhOsContract.ActorsAndRelationsTest.Clinic

  @source """
  defmodule #{inspect(@domain)} do
    use EhOsContract.Domain, name: :clinic, language: :pl

    subdomain :core, "Core", type: :core

    context :scheduling, "Umawianie", subdomain: :core do
      term "Wizyta", definition: "Zarezerwowany termin z zasobami"
    end

    context :documentation, "Dokumentacja", subdomain: :core do
      term "Wizyta", definition: "Spotkanie kliniczne z notatką"
      term "Epizod", definition: "Seria wizyt jednego leczenia"
    end

    actor :manager, :human, "Manager gabinetu" do
      responsibility :overdue_work, "Rozlicza zaległe zgłoszenia, które widzi jako liczbę",
        source: "P-25"
    end

    actor :reception, :human, "Recepcja"

    relation :partnership,
      between: [:scheduling, :documentation],
      terms: [{"Wizyta", "Wizyta"}],
      source: "30-contexts.md"
  end
  """

  setup_all do
    compile(@source, "actors_relations_clinic.ex")
    %{domain: Model.fetch(@domain)}
  end

  describe "the model" do
    test "keeps an actor's responsibilities and a relation's pairs", %{domain: domain} do
      manager = Enum.find(domain.actors, &(&1.name == :manager))
      reception = Enum.find(domain.actors, &(&1.name == :reception))

      assert [%{name: :overdue_work, source: "P-25"}] = manager.responsibilities
      assert reception.responsibilities == []
      assert [%{type: :partnership, terms: [["Wizyta", "Wizyta"]]}] = domain.relations
    end

    test "a partnership's pairs follow its ends, whichever order they are written in" do
      compile(
        """
        defmodule EhOsContract.ActorsAndRelationsTest.Reversed do
          use EhOsContract.Domain, name: :clinic, language: :pl

          subdomain :core, "Core", type: :core

          context :scheduling, "Umawianie", subdomain: :core do
            term "Termin", definition: "Zarezerwowany czas"
          end

          context :documentation, "Dokumentacja", subdomain: :core do
            term "Wizyta", definition: "Spotkanie kliniczne"
          end

          relation :partnership, between: [:scheduling, :documentation],
            terms: [{"Termin", "Wizyta"}]
        end

        defmodule EhOsContract.ActorsAndRelationsTest.Forward do
          use EhOsContract.Domain, name: :clinic, language: :pl

          subdomain :core, "Core", type: :core

          context :scheduling, "Umawianie", subdomain: :core do
            term "Termin", definition: "Zarezerwowany czas"
          end

          context :documentation, "Dokumentacja", subdomain: :core do
            term "Wizyta", definition: "Spotkanie kliniczne"
          end

          relation :partnership, between: [:documentation, :scheduling],
            terms: [{"Wizyta", "Termin"}]
        end
        """,
        "actors_relations_order.ex"
      )

      reversed = Model.fetch(EhOsContract.ActorsAndRelationsTest.Reversed)
      forward = Model.fetch(EhOsContract.ActorsAndRelationsTest.Forward)

      assert reversed.version == forward.version
    end
  end

  describe "the rules" do
    test "D5 refuses a word its context's glossary does not define" do
      message =
        """
        defmodule EhOsContract.ActorsAndRelationsTest.Unknown do
          use EhOsContract.Domain, name: :clinic, language: :pl

          subdomain :core, "Core", type: :core

          context :scheduling, "Umawianie", subdomain: :core do
            term "Wizyta", definition: "Zarezerwowany termin"
          end

          context :documentation, "Dokumentacja", subdomain: :core

          relation :partnership, between: [:scheduling, :documentation],
            terms: [{"Wizyta", "Wizyta"}, {"Termin", "Wizyta"}]
        end
        """
        |> compile_error("actors_relations_unknown.ex")
        |> Exception.message()

      assert message =~
               ~s|D5: relation :partnership: the term "Wizyta" is not in the glossary of | <>
                 "context :documentation"

      assert message =~ ~s|the term "Termin" is not in the glossary of context :scheduling|
    end

    test "D5 leaves the word of an external end unchecked; control: a directed relation" do
      compile(
        """
        defmodule EhOsContract.ActorsAndRelationsTest.Outside do
          use EhOsContract.Domain, name: :clinic, language: :pl

          subdomain :core, "Core", type: :core

          context :reporting, "Zgłoszenia", subdomain: :core do
            term "Zgłoszenie", definition: "Zdarzenie medyczne wysłane do rejestru"
          end

          external :p1, "Rejestr P1", direction: :bidirectional

          relation :conformist, upstream: :p1, downstream: :reporting,
            terms: [{"Zdarzenie medyczne", "Zgłoszenie"}]
        end
        """,
        "actors_relations_outside.ex"
      )

      assert [%{terms: [["Zdarzenie medyczne", "Zgłoszenie"]]}] =
               Model.fetch(EhOsContract.ActorsAndRelationsTest.Outside).relations
    end

    test "D1 refuses a responsibility named twice, and one not snake_case" do
      message =
        """
        defmodule EhOsContract.ActorsAndRelationsTest.Twice do
          use EhOsContract.Domain, name: :clinic, language: :pl

          subdomain :core, "Core", type: :core
          context :scheduling, "Umawianie", subdomain: :core

          actor :manager, :human, "Manager" do
            responsibility :overdue, "Zaległe"
            responsibility :overdue, "Zaległe jeszcze raz"
            responsibility :Reports, "Raporty"
          end
        end
        """
        |> compile_error("actors_relations_twice.ex")
        |> Exception.message()

      assert message =~ "D1: actor :manager declares the responsibility :overdue twice"
      assert message =~ "D1: responsibility :Reports of actor :manager is not snake_case"
    end
  end

  describe "the readers" do
    test "the domain's page shows responsibilities and pairs", %{domain: domain} do
      text = domain |> Pages.render([]) |> Map.values() |> Enum.join("\n")

      assert text =~
               "  - responsibility `overdue_work` — Rozlicza zaległe zgłoszenia, które widzi " <>
                 "jako liczbę · _source: P-25_"

      assert text =~ ~s|· terms: "Wizyta" ↔ "Wizyta"|
    end

    test "the glossary says, under a term, what the other end calls it" do
      glossary = Glossary.render(@domain)

      assert glossary =~ "_In `documentation` (partnership): \"Wizyta\"._"
      assert glossary =~ "_In `scheduling` (partnership): \"Wizyta\"._"
      refute glossary =~ "### Epizod\n\nSeria wizyt jednego leczenia\n_In"
    end
  end
end

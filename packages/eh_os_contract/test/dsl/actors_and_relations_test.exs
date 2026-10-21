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
    use EhOsContract.Domain, name: :clinic, language: :en

    subdomain :core, "Core", type: :core

    context :scheduling, "Scheduling", subdomain: :core do
      term "Visit", definition: "A booked slot with its resources"
    end

    context :documentation, "Documentation", subdomain: :core do
      term "Visit", definition: "A clinical encounter with a note"
      term "Episode", definition: "A series of visits in one treatment"
    end

    actor :manager, :human, "Practice manager" do
      responsibility :waiting_requests, "Answers the waiting requests, which they see as a list",
        source: "S-12"
    end

    actor :reception, :human, "Reception"

    relation :partnership,
      between: [:scheduling, :documentation],
      terms: [{"Visit", "Visit"}],
      source: "contexts.md"
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

      assert [%{name: :waiting_requests, source: "S-12"}] = manager.responsibilities
      assert reception.responsibilities == []
      assert [%{type: :partnership, terms: [["Visit", "Visit"]]}] = domain.relations
    end

    test "a partnership's pairs follow its ends, whichever order they are written in" do
      compile(
        """
        defmodule EhOsContract.ActorsAndRelationsTest.Reversed do
          use EhOsContract.Domain, name: :clinic, language: :en

          subdomain :core, "Core", type: :core

          context :scheduling, "Scheduling", subdomain: :core do
            term "Slot", definition: "Booked time"
          end

          context :documentation, "Documentation", subdomain: :core do
            term "Visit", definition: "A clinical encounter"
          end

          relation :partnership, between: [:scheduling, :documentation],
            terms: [{"Slot", "Visit"}]
        end

        defmodule EhOsContract.ActorsAndRelationsTest.Forward do
          use EhOsContract.Domain, name: :clinic, language: :en

          subdomain :core, "Core", type: :core

          context :scheduling, "Scheduling", subdomain: :core do
            term "Slot", definition: "Booked time"
          end

          context :documentation, "Documentation", subdomain: :core do
            term "Visit", definition: "A clinical encounter"
          end

          relation :partnership, between: [:documentation, :scheduling],
            terms: [{"Visit", "Slot"}]
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
          use EhOsContract.Domain, name: :clinic, language: :en

          subdomain :core, "Core", type: :core

          context :scheduling, "Scheduling", subdomain: :core do
            term "Visit", definition: "A booked slot"
          end

          context :documentation, "Documentation", subdomain: :core

          relation :partnership, between: [:scheduling, :documentation],
            terms: [{"Visit", "Visit"}, {"Slot", "Visit"}]
        end
        """
        |> compile_error("actors_relations_unknown.ex")
        |> Exception.message()

      assert message =~
               ~s|D5: relation :partnership: the term "Visit" is not in the glossary of | <>
                 "context :documentation"

      assert message =~ ~s|the term "Slot" is not in the glossary of context :scheduling|
    end

    test "D5 leaves the word of an external end unchecked; control: a directed relation" do
      compile(
        """
        defmodule EhOsContract.ActorsAndRelationsTest.Outside do
          use EhOsContract.Domain, name: :clinic, language: :en

          subdomain :core, "Core", type: :core

          context :reporting, "Reporting", subdomain: :core do
            term "Report", definition: "A medical incident sent to the registry"
          end

          external :registry, "Health registry", direction: :bidirectional

          relation :conformist, upstream: :registry, downstream: :reporting,
            terms: [{"Medical incident", "Report"}]
        end
        """,
        "actors_relations_outside.ex"
      )

      outside = Model.fetch(EhOsContract.ActorsAndRelationsTest.Outside)
      assert [%{terms: [["Medical incident", "Report"]]}] = outside.relations

      # The glossary says the other end is a system, not a context with a glossary.
      assert Glossary.render(outside) =~
               ~s|_In external `registry` (conformist): "Medical incident"._|
    end

    test "D5 reads a directed relation's pair as upstream, then downstream; D1 refuses a pair twice" do
      message =
        """
        defmodule EhOsContract.ActorsAndRelationsTest.Directed do
          use EhOsContract.Domain, name: :clinic, language: :en

          subdomain :core, "Core", type: :core

          context :scheduling, "Scheduling", subdomain: :core do
            term "Slot", definition: "Booked time"
          end

          context :settlement, "Settlement", subdomain: :core do
            term "Visit", definition: "An amount due"
          end

          relation :customer_supplier, upstream: :scheduling, downstream: :settlement,
            terms: [{"Slot", "Visit"}, {"Slot", "Visit"}]
        end
        """
        |> compile_error("actors_relations_directed.ex")
        |> Exception.message()

      assert message =~ ~s|D1: relation :customer_supplier pairs {"Slot", "Visit"} twice|

      # "Slot" is the upstream's word and "Visit" the downstream's: read the other way
      # round, both would be refused.
      refute message =~ "is not in the glossary"
    end

    test "D1 refuses a responsibility named twice, and one not snake_case" do
      message =
        """
        defmodule EhOsContract.ActorsAndRelationsTest.Twice do
          use EhOsContract.Domain, name: :clinic, language: :en

          subdomain :core, "Core", type: :core
          context :scheduling, "Scheduling", subdomain: :core

          actor :manager, :human, "Manager" do
            responsibility :overdue, "Overdue"
            responsibility :overdue, "Overdue again"
            responsibility :Reports, "Reports"
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
               "  - responsibility `waiting_requests` — Answers the waiting requests, which they see " <>
                 "as a list · _source: S-12_"

      assert text =~ ~s|· terms: "Visit" ↔ "Visit"|

      # A context's page carries the same line under the term as the glossary.
      page = Pages.render(domain, []) |> Map.fetch!("scheduling/index.md")
      assert page =~ ~s|_In `documentation` (partnership): "Visit"._|
    end

    test "the glossary says, under a term, what the other end calls it" do
      glossary = Glossary.render(@domain)

      assert glossary =~ "_In `documentation` (partnership): \"Visit\"._"
      assert glossary =~ "_In `scheduling` (partnership): \"Visit\"._"
      refute glossary =~ "### Episode\n\nA series of visits in one treatment\n_In"

      # Translated, the term keeps what the other end calls it.
      compile(
        """
        defmodule EhOsContract.ActorsAndRelationsTest.Translated do
          use EhOsContract.Domain, name: :clinic, language: :pl

          subdomain :core, "Core", type: :core

          context :scheduling, "Umawianie", subdomain: :core do
            term "Wizyta", definition: "Termin" do
              translation :en, "Visit", definition: "A held slot"
            end
          end

          context :documentation, "Dokumentacja", subdomain: :core do
            term "Wizyta", definition: "Spotkanie"
          end

          relation :partnership, between: [:scheduling, :documentation],
            terms: [{"Wizyta", "Wizyta"}]
        end
        """,
        "actors_relations_translated.ex"
      )

      english = Glossary.render(EhOsContract.ActorsAndRelationsTest.Translated, language: :en)
      assert english =~ ~s|### Visit|
      assert english =~ ~s|_Translates "Wizyta"._\n_In `documentation` (partnership): "Wizyta"._|

      # An untranslated term keeps it too (CodeRabbit on #115).
      assert english =~
               ~s|_No translation into en._\n_In `scheduling` (partnership): "Wizyta"._|
    end
  end
end

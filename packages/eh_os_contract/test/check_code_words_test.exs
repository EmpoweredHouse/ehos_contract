defmodule EhOsContract.CheckCodeWordsTest do
  @moduledoc """
  Plan DD, L1: **the glossary joined to the code.** A term's word in code is its
  translation into the domain's `code_language:`; `mix eh_os_contract.check` ranks the
  words of a context's names of things that no term covers (`word-without-term`) and
  warns where a name says a term of another context only (`term-of-another-context`);
  the glossary lists, under a term, the declarations named with it.
  """

  use EhOsContract.DslCase, async: false

  alias EhOsContract.Check.{Completeness, Finding}
  alias EhOsContract.Glossary

  @domain EhOsContract.CheckCodeWordsTest.Clinic
  @scheduling EhOsContract.CheckCodeWordsTest.Scheduling
  @payers EhOsContract.CheckCodeWordsTest.Payers

  setup_all do
    compile(
      """
      defmodule #{inspect(@domain)} do
        use EhOsContract.Domain, name: :code_words, language: :pl

        subdomain :core, "Rdzeń", type: :core

        context :scheduling, "Umawianie", subdomain: :core do
          term "Wizyta", definition: "Zarezerwowany termin" do
            translation :en, "Visit", definition: "A held slot"
          end

          term "Data rozliczenia", definition: "Dzień rozliczenia" do
            translation :en, "Settlement date", definition: "The day of settlement"
          end

          term "Zrealizowana", definition: "Pacjent wyszedł z gabinetu"
        end

        context :payers, "Płatnicy", subdomain: :core do
          term "Płatnik", definition: "Kto płaci za wizytę" do
            translation :en, "Payer", definition: "Who pays for a visit"
          end

          term "Data wizyty", definition: "Dzień, za który płatnik płaci" do
            translation :en, "Visit date", definition: "The day the payer pays for"
          end
        end

        actor :reception, :human, "Recepcja"
        entity :service, "Usługa", context: :scheduling, identity: :service_id
      end

      defmodule #{inspect(@scheduling)} do
        use EhOsContract.Contract, domain: #{inspect(@domain)}, context: :scheduling,
          id: "code_words.scheduling"

        aggregate :visit, "Wizyta" do
          identity :visit_id

          command :book_visit, "Umów wizytę", by: :reception, emits: :visit_booked do
            field :slot_start, :timestamp, label: "Początek"
            field :settlement_date_set, :date, label: "Data"
            field :date_of_settlement, :date, label: "Data"
          end

          event :visit_booked, "Wizyta umówiona" do
            field :slot_start, :timestamp, label: "Początek"
          end
        end
      end

      defmodule #{inspect(@payers)} do
        use EhOsContract.Contract, domain: #{inspect(@domain)}, context: :payers,
          id: "code_words.payers"

        aggregate :payer, "Płatnik" do
          identity :payer_id

          command :charge_visit, "Obciąż płatnika", by: :reception, emits: :visit_charged do
            field :visit_ref, :string, label: "Wizyta"
            field :visit_id, :id, label: "Wizyta"
            field :visit_date, :date, label: "Data wizyty"
            field :service, {:id, :service}, label: "Usługa"
          end

          event :visit_charged, "Wizyta obciążona" do
            field :visit_ref, :string, label: "Wizyta"
          end
        end
      end
      """,
      "clinic.ex"
    )

    :ok
  end

  defp found(rule) do
    for %Finding{rule: ^rule} = f <- Completeness.findings([@scheduling, @payers]),
        do: {f.message, Finding.place(f)}
  end

  test "word-without-term: one notice per context, its uncovered words most used first" do
    # `visit` and `settlement date` are covered where they stand whole; `date` of
    # `date_of_settlement` is not, nor is `settlement`. Control: `id` and `of` are too
    # short, and `book` and `booked` stand only in a command's and an event's name.
    assert [
             {"context :scheduling of EhOsContract.CheckCodeWordsTest.Clinic names things with " <>
                "words no term of its glossary has in :en, most used first: date (1), " <>
                "set (1), settlement (1), slot (1), start (1)" = message, {"clinic.ex", 6}}
             | _payers
           ] = Enum.sort_by(found("word-without-term"), &elem(&1, 1))

    # `set` follows `settlement date`, which covers its two words and not the third.
    refute message =~ "visit"
    refute message =~ "book"
  end

  test "word-without-term: ties are alphabetical, and the payers' own term covers payer" do
    assert {message, _at} =
             Enum.find(found("word-without-term"), fn {m, _} -> m =~ "context :payers" end)

    # `visit` of `visit_date` is the payers' own "Visit date"; of `visit_ref` and
    # `visit_id`, it is not.
    assert message =~ "most used first: visit (2), ref (1)"
    refute message =~ "payer ("
  end

  test "term-of-another-context: one finding per name; control: an entity, another unit's identity, an own longer term" do
    # `visit_ref` is in a command and an event, so it is reported once, at the first.
    # Control: `service` refers to an entity, `visit_id` is the identity of scheduling's
    # visit, and `visit_date` is the payers' own "Visit date".
    assert [
             {"EhOsContract.CheckCodeWordsTest.Payers: field :visit_ref (in 2 declarations) " <>
                ~s|says "visit", the word in code of "Wizyta" of :scheduling, which context | <>
                ":payers has no term for", {"clinic.ex", 59}}
           ] = found("term-of-another-context")
  end

  test "an empty sequence of words covers nothing" do
    assert EhOsContract.CodeWords.covers(["visit", "id"], []) == MapSet.new()

    assert EhOsContract.CodeWords.covers(["visit", "date"], ["visit", "date"]) ==
             MapSet.new([0, 1])
  end

  test "a context written in the code's language is its own word in code" do
    model = %{
      language: :pl,
      code_language: :pl,
      contexts: [
        %{
          name: :scheduling,
          language: nil,
          terms: [%{text: "Wizyta", translations: [%{language: :en, text: "Visit"}]}]
        }
      ]
    }

    assert EhOsContract.CodeWords.terms(model, :scheduling) == [{"Wizyta", ["wizyta"]}]

    assert EhOsContract.CodeWords.terms(%{model | code_language: :en}, :scheduling) ==
             [{"Wizyta", ["visit"]}]

    assert EhOsContract.CodeWords.terms(%{model | code_language: :de}, :scheduling) == []
  end

  test "the glossary lists, per term, its word in code and the declarations named with it" do
    text = Glossary.render(@domain, contracts: [@scheduling, @payers], context: :scheduling)

    assert text =~
             """
             ### Wizyta

             Zarezerwowany termin
             _In code: `visit`._
             - `EhOsContract.CheckCodeWordsTest.Scheduling`: aggregate `:visit`, command `:book_visit`, event `:visit_booked`
             """

    assert text =~
             """
             _In code: `settlement_date`._
             - `EhOsContract.CheckCodeWordsTest.Scheduling`: field `:settlement_date_set`
             """

    assert text =~
             "### Zrealizowana\n\nPacjent wyszedł z gabinetu\n_No word in code: no translation into en._"

    # Control: without the contracts, the glossary is what it was.
    refute Glossary.render(@domain) =~ "In code"
  end

  test "code_language moves no version, and is in the model only when it is not English" do
    source = fn name, option ->
      """
      defmodule EhOsContract.CheckCodeWordsTest.#{name} do
        use EhOsContract.Domain, name: :versioned, language: :pl#{option}
        subdomain :core, "Rdzeń", type: :core
      end
      """
    end

    compile(source.("Plain", ""), "plain.ex")
    compile(source.("English", ", code_language: :en"), "english.ex")
    compile(source.("Polish", ", code_language: :pl"), "polish.ex")

    version =
      &EhOsContract.Model.fetch(Module.concat(EhOsContract.CheckCodeWordsTest, &1)).version

    assert version.(Plain) == version.(English)
    assert version.(Plain) == version.(Polish)

    refute Map.has_key?(
             EhOsContract.Model.fetch(EhOsContract.CheckCodeWordsTest.English),
             :code_language
           )

    assert EhOsContract.Model.fetch(EhOsContract.CheckCodeWordsTest.Polish).code_language == :pl
  end
end

defmodule EhosContract.CheckAvoidedTermsTest do
  @moduledoc """
  Plan EL2, rule 2 of the prose review: **a label that uses a word its context's glossary says
  to avoid**, whole words in any case, at the declaration of the label.
  """

  use EhosContract.DslCase, async: false

  alias EhosContract.Check.{Completeness, Finding}

  setup_all do
    compile(
      """
      defmodule EhosContract.CheckAvoidedTermsTest.Clinic do
        use EhosContract.Domain, name: :avoided, language: :pl

        subdomain :core, "Rdzeń", type: :core

        context :scheduling, "Umawianie", subdomain: :core do
          term "Zrealizowana", definition: "Pacjent wyszedł z gabinetu" do
            avoid "Zakończona", reason: "Zakończona bywa też wizyta odwołana"
            avoid ""

            translation :en, "Completed", definition: "The patient has left" do
              avoid "Done"
            end
          end

          term "Zaliczka na podatek", definition: "Kwota płacona co miesiąc" do
            avoid "Zaliczka"
          end
        end

        actor :reception, :human, "Recepcja"
      end

      defmodule EhosContract.CheckAvoidedTermsTest.Visits do
        use EhosContract.Contract,
          domain: EhosContract.CheckAvoidedTermsTest.Clinic,
          context: :scheduling, id: "avoided.visits"

        aggregate :visit, "Wizyta" do
          identity :visit_id
          command :close, "Oznacz wizytę jako zrealizowaną", by: :reception, emits: :closed
          event :closed, "Wizyta ZAKOŃCZONA"
          command :finish, "Zakończonawizyta nie jest słowem", by: :reception, emits: :finished

          event :finished, "Done - pacjent wyszedł" do
            field :state, {:enum, [done: "Zakończona", open: "Otwarta"]}
          end

          command :advance, "Zaliczka na podatek wyliczona", by: :reception, emits: :advanced
          event :advanced, "Zrealizowana"
        end
      end
      """,
      "clinic.ex"
    )

    :ok
  end

  test "a label and an enum member's label saying the word; control: the term itself, a blank word, a translation's word" do
    found =
      for %Finding{rule: "label-with-avoided-term"} = f <-
            Completeness.findings([EhosContract.CheckAvoidedTermsTest.Visits]),
          do: {f.message, Finding.place(f)}

    assert [
             {~s|EhosContract.CheckAvoidedTermsTest.Visits: the label "Wizyta ZAKOŃCZONA" says "Zakończona", | <>
                ~s|which context :scheduling avoids in favour of "Zrealizowana"|,
              {"clinic.ex", 32}},
             {~s|EhosContract.CheckAvoidedTermsTest.Visits: the label "Zakończona" says "Zakończona"| <>
                _, {"clinic.ex", 36}}
           ] = Enum.sort_by(found, &elem(&1, 1))
  end
end

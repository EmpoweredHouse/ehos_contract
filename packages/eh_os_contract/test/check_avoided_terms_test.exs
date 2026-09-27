defmodule EhOsContract.CheckAvoidedTermsTest do
  @moduledoc """
  Plan EL2, "Po EL2" rule 2: **a label that uses a word its context's glossary says
  to avoid**, whole words in any case, at the declaration of the label.
  """

  use EhOsContract.DslCase, async: false

  alias EhOsContract.Check.{Completeness, Finding}

  setup_all do
    compile(
      """
      defmodule EhOsContract.CheckAvoidedTermsTest.Clinic do
        use EhOsContract.Domain, name: :avoided, language: :pl

        subdomain :core, "Rdzeń", type: :core

        context :scheduling, "Umawianie", subdomain: :core do
          term "Zrealizowana", definition: "Pacjent wyszedł z gabinetu" do
            avoid "Zakończona", reason: "Zakończona bywa też wizyta odwołana"
          end
        end

        actor :reception, :human, "Recepcja"
      end

      defmodule EhOsContract.CheckAvoidedTermsTest.Visits do
        use EhOsContract.Next.Contract,
          domain: EhOsContract.CheckAvoidedTermsTest.Clinic,
          context: :scheduling

        aggregate :visit, "Wizyta" do
          identity :visit_id
          command :close, "Oznacz wizytę jako zrealizowaną", by: :reception, emits: :closed
          event :closed, "Wizyta ZAKOŃCZONA"
          command :finish, "Zakończonawizyta nie jest słowem", by: :reception, emits: :finished
          event :finished, "Pacjent wyszedł"
        end

        process :visit, "Wizyta" do
          correlate :visit_id
        end
      end
      """,
      "clinic.ex"
    )

    :ok
  end

  test "the word in any case, at its declaration; control: the term itself, and the word inside another" do
    assert [%Finding{message: message} = finding] =
             Completeness.findings([EhOsContract.CheckAvoidedTermsTest.Visits])
             |> Enum.filter(&(&1.rule == "label-with-avoided-term"))

    assert message =~
             ~s|the label "Wizyta ZAKOŃCZONA" says "Zakończona", which context :scheduling avoids | <>
               ~s|in favour of "Zrealizowana"|

    assert Finding.place(finding) == {"clinic.ex", 23}
  end
end

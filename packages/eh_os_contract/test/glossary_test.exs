defmodule EhOsContract.GlossaryTest do
  @moduledoc """
  Plan EL2: **a domain's ubiquitous language as Markdown** (ESDM's `glossary`), one
  section per context, in the context's language or translated into another.
  """

  use EhOsContract.DslCase, async: false

  alias EhOsContract.Glossary

  @domain EhOsContract.GlossaryTest.Clinic

  setup_all do
    compile(
      """
      defmodule #{inspect(@domain)} do
        use EhOsContract.Domain, name: :clinic, language: :pl

        context :scheduling, "Umawianie", subdomain: :core do
          term "Zrealizowana", definition: "Pacjent wyszedł z gabinetu", source: "AGG-01" do
            translation :en, "Completed"
            avoid "Zakończona"
          end

          term "Wizyta", definition: "Umówione spotkanie pacjenta ze specjalistą"
        end

        context :reporting, "Raporty", subdomain: :generic, language: :en do
          term "Daily report", definition: "What was settled on one day"
        end

        context :archive, "Archiwum", subdomain: :generic
      end
      """,
      "clinic.ex"
    )

    :ok
  end

  test "a section per context, a heading per term, what to avoid and where it comes from" do
    assert Glossary.render(@domain) ==
             """
             # Glossary of `clinic`

             ## Umawianie (`scheduling`)

             ### Zrealizowana

             Pacjent wyszedł z gabinetu
             _Avoid the term "Zakończona"._
             _Source: AGG-01_

             ### Wizyta

             Umówione spotkanie pacjenta ze specjalistą

             ## Raporty (`reporting`)

             ### Daily report

             What was settled on one day

             ## Archiwum (`archive`)

             _No terms._
             """
  end

  test "in another language: a translation, a note where there is none, a context already in it" do
    text = Glossary.render(@domain, language: :en)

    assert text =~ ~s|### Completed\n\n_Translates "Zrealizowana": Pacjent wyszedł z gabinetu_\n|
    assert text =~ "### Wizyta\n\n_No translation into en._\n"
    assert text =~ "### Daily report\n\nWhat was settled on one day\n"
  end

  test "one context" do
    assert Glossary.render(@domain, context: :reporting) =~
             ~r/\A# Glossary of `clinic`\n\n## Raporty \(`reporting`\)\n\n### Daily report\n/
  end
end

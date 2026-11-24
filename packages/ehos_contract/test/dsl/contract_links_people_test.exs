defmodule EhosContract.ContractLinksPeopleTest do
  @moduledoc """
  Plan DD, A1 (#247): **X2**, the part about a person, which needs the domain to know
  who is a person. A command that names who must issue it (`actor_is`) has a `:human`
  actor in `by:`; its scenario by a person names them with `as`; `as` stands neither
  beside a `:system` actor nor on a command that names nobody.
  """

  use EhosContract.DslCase, async: false

  @fixtures EhosContract.Fixtures
  @domain EhosContract.Fixtures.PeopleClinic

  setup_all do
    compile(
      """
      defmodule #{inspect(@domain)} do
        use EhosContract.Domain, name: :clinic, language: :en

        context :documentation, "Documentation", subdomain: :core
        actor :specialist, :human, "Specialist"
        actor :night_shift, :system, "Night shift"

        subdomain :core, "Core", type: :core
      end
      """,
      "people_clinic.ex"
    )

    :ok
  end

  # The scenario refused on the invariant, which S8 asks for, by `closer`.
  defp desk(name, by, scenarios, closer \\ ~s|actor :specialist\n    as "specialist-ola"|) do
    {"#{Macro.underscore(name)}.ex",
     """
     defmodule #{inspect(Module.concat(@fixtures, name))} do
       use EhosContract.Contract, domain: #{inspect(@domain)}, context: :documentation, id: "clinic.#{contract_name(name)}"

       aggregate :visit, "Visit" do
         identity :visit_id

         state do
           field :specialist_id, :id, optional: true
         end

         invariant :own_visit, "Only one's own visit"

         command :close_visit, "Close", by: #{inspect(by)}, emits: :closed, rejects: :own_visit do
           actor_is :specialist_id, or_rejects: :own_visit
         end

         command :note_visit, "Note", by: :specialist, emits: :noted

         event :closed, "Closed"
         event :noted, "Noted"
       end

       scenario "someone else closes" do
         #{closer}
         command :close_visit
         rejected :own_visit
       end

     #{scenarios}
     end
     """}
  end

  test "control: a person in by:, and scenarios that name the person or are the application's" do
    assert links([
             desk("PeopleRight", [:specialist, :night_shift], """
               scenario "the night shift closes" do
                 actor :night_shift
                 command :close_visit
                 expect :closed
               end
             """)
           ]) == []
  end

  test "a by: that names no person" do
    violations = links([desk("PeopleNobody", [:night_shift], "", "actor :night_shift")])

    assert_linked(
      violations,
      "X2: command :close_visit names who must issue it (actor_is), and its by: " <>
        "[:night_shift] names no person, so nobody is ever compared",
      "people_nobody.ex"
    )
  end

  test "a person unnamed, as beside a system, and as on another command" do
    violations =
      links([
        desk("PeopleWrong", [:specialist, :night_shift], """
          scenario "a specialist closes" do
            actor :specialist
            command :close_visit
            expect :closed
          end

          scenario "the night shift as someone" do
            actor :night_shift
            as "specialist-ewa"
            command :close_visit
            expect :closed
          end

          scenario "a note" do
            actor :specialist
            as "specialist-ewa"
            command :note_visit
            expect :noted
          end
        """)
      ])

    for problem <- [
          ~s|X2: scenario "a specialist closes": actor :specialist is a person, and the command | <>
            "names who must issue it: say which person with as",
          ~s|X2: scenario "the night shift as someone": as "specialist-ewa" names a person beside | <>
            ":night_shift, a :system actor, whom dispatch never compares",
          ~s|X2: scenario "a note": as "specialist-ewa" names a person, and the command names | <>
            "nobody who must issue it"
        ] do
      assert_linked(violations, problem, "people_wrong.ex")
    end
  end
end

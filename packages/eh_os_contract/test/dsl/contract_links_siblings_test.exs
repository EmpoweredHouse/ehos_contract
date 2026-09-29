defmodule EhOsContract.ContractLinksSiblingsTest do
  @moduledoc """
  v2 plan, E5b: **X5–X6** (v2 §6, §7) — a subscriber checked against the sibling
  contract it consumes from, as that sibling is compiled now. A violation stands at
  the subscriber's declaration and names the publisher's event with its file and
  line; each has a control beside it that passes.
  """

  use EhOsContract.DslCase, async: false

  @fixtures EhOsContract.Fixtures
  @domain EhOsContract.Fixtures.SiblingsClinic

  setup_all do
    compile(
      """
      defmodule #{inspect(@domain)} do
        use EhOsContract.Domain, name: :clinic, language: :pl

        context :settlement, "Rozliczenia", subdomain: :core
        actor :reception, :human, "Recepcja"

        entity :visit, "Wizyta", context: :settlement, identified_by: :visit_id do
          field :visit_id, :id
        end

        value :visit_code, :id
        value :other_code, :id
        value :room_name, :string

        subdomain :core, "Core", type: :core
      end
      """,
      "siblings_clinic.ex"
    )

    :ok
  end

  # The publisher. Line 9 declares the event, line 10 its `visit_id`.
  defp publisher(name, fields, opts \\ []) do
    domain = Keyword.get(opts, :domain, inspect(@domain))

    """
    defmodule #{inspect(Module.concat(@fixtures, name))} do
      use EhOsContract.Contract, domain: #{domain}, context: :settlement

      aggregate :booking, "Rezerwacja" do
        identity :booking_id

        command :book_visit, "Rezerwacja wizyty", by: :reception, emits: :visit_booked

        event :visit_booked, "Wizyta zarezerwowana" do
    #{fields}
        end
      end

      process :booking, "Rezerwacja" do
        correlate :booking_id
      end
    end
    """
  end

  @fields """
        field :visit_id, :id
        field :room, :string
  """

  # The subscriber: it correlates its process on `visit_id` and includes the
  # publisher's event (line 15), a process manager starts on it (line 19), and a
  # boundary consults it matching `visit_id` (line 29).
  defp subscriber(name, publisher, consumes \\ ":visit_booked") do
    """
    defmodule #{inspect(Module.concat(@fixtures, name))} do
      use EhOsContract.Contract, domain: #{inspect(@domain)}, context: :settlement

      consumes #{inspect(Module.concat(@fixtures, publisher))}, #{consumes}

      aggregate :billing, "Rozliczenie" do
        identity :visit_id
        command :bill_visit, "Rozliczenie wizyty", by: :reception, emits: :visit_billed
        event :visit_billed, "Wizyta rozliczona"
      end

      process :billing, "Rozliczenie" do
        correlate :visit_id

        include :visit_booked
      end

      process_manager :chase, "Pogoń za rozliczeniem", correlate: :visit_id do
        starts_on :visit_booked, issues: :bill_visit
        ends_on :visit_billed
      end

      dcb :visit_slot, "Termin wizyty" do
        identity :visit_id

        command :hold_slot, "Wstrzymanie terminu", by: :reception, emits: :slot_held
        event :slot_held, "Termin wstrzymany"

        consults :visit_booked, match: :visit_id
      end
    end
    """
  end

  defp pair(test, fields, consumes \\ ":visit_booked") do
    links([
      {"#{test}_booking.ex", publisher("#{Macro.camelize(test)}Booking", fields)},
      {"#{test}_billing.ex",
       subscriber("#{Macro.camelize(test)}Billing", "#{Macro.camelize(test)}Booking", consumes)}
    ])
  end

  test "control: a subscriber using the publisher's fields as declared passes" do
    assert pair("sib_right", @fields) == []
  end

  test "control: a publisher naming the field an entity's identifier is the same :id" do
    # Stored as an :id either way, so correlating, starting on and matching it on the
    # subscriber's side, where it is a plain :id, is the same field (plan EM2).
    fields = String.replace(@fields, "field :visit_id, :id", "field :visit_id, {:id, :visit}")
    assert pair("sib_entity", fields) == []
  end

  test "control: a publisher naming the field by a domain value of :id is the same :id" do
    # "2026-07" as a period's identifier is a value with its own invariant, and still
    # an identifier: a subscriber correlating, starting on and matching it as a plain
    # :id reads the same field (plan E9c).
    fields = String.replace(@fields, "field :visit_id, :id", "field :visit_id, :visit_code")
    assert pair("sib_value", fields) == []
  end

  test "two different domain values of :id are not the same type" do
    # "2026-07" and a room's code both rest on :id, and are not each other: a run
    # correlated on one is not a run of the other.
    fields = String.replace(@fields, "field :visit_id, :id", "field :visit_id, :other_code")

    subscriber = """
    defmodule #{inspect(Module.concat(@fixtures, "SibTwoValuesBilling"))} do
      use EhOsContract.Contract, domain: #{inspect(@domain)}, context: :settlement

      consumes #{inspect(Module.concat(@fixtures, "SibTwoValuesBooking"))}, :visit_booked

      aggregate :billing, "Rozliczenie" do
        identity :billing_id
        command :bill_visit, "Rozliczenie wizyty", by: :reception, emits: :visit_billed

        event :visit_billed, "Wizyta rozliczona" do
          field :visit_id, :visit_code
        end
      end

      process :billing, "Rozliczenie" do
        correlate :visit_id
        include :visit_booked
      end
    end
    """

    violations =
      links([
        {"sib_two_values_booking.ex", publisher("SibTwoValuesBooking", fields)},
        {"sib_two_values_billing.ex", subscriber}
      ])

    assert Enum.any?(violations, fn %{message: message} ->
             message =~ "X6: process :billing includes :visit_booked and correlates on :visit_id" and
               message =~ "has as :other_code, not :visit_code"
           end),
           inspect(violations)
  end

  test "a publisher naming the field by a domain value of another type is not an :id" do
    fields = String.replace(@fields, "field :visit_id, :id", "field :visit_id, :room_name")
    violations = pair("sib_value_string", fields)

    assert Enum.any?(violations, fn %{message: message} ->
             message =~ "X6: dcb :visit_slot consults :visit_booked matching :visit_id" and
               message =~ "has as :room_name, not :id"
           end),
           inspect(violations)
  end

  describe "X5: the sibling and its events exist" do
    test "a module that is not a compiled v2 contract" do
      violations = links([{"sib_nowhere.ex", subscriber("SibNowhere", "Nowhere")}])

      assert assert_linked(
               violations,
               "X5: consumes #{inspect(@fixtures)}.Nowhere",
               "sib_nowhere.ex",
               4
             ) =~
               "which is not a compiled v2 contract"
    end

    test "a sibling of another domain is another application's" do
      violations =
        links([
          {"sib_other_domain_booking.ex",
           publisher("SibOtherDomainBooking", @fields, domain: "UniversalityGate.Domain")
           |> String.replace(":settlement", ":treatment")
           |> String.replace(":reception", ":attending_physician")},
          {"sib_other_domain_billing.ex",
           subscriber("SibOtherDomainBilling", "SibOtherDomainBooking")}
        ])

      assert assert_linked(violations, "X5:", "sib_other_domain_billing.ex", 4) =~
               "a contract of domain UniversalityGate.Domain, not #{inspect(@domain)}: another " <>
                 "application's events arrive only through a publish (D11)"

      # Nothing is read from a sibling that is not one.
      refute Enum.any?(violations, &(&1.message =~ "X6"))
    end

    test "an event the sibling does not declare, with a did-you-mean" do
      violations = pair("sib_no_event", @fields, "[:visit_booked, :visit_boked]")

      assert assert_linked(violations, "X5: consumes :visit_boked", "sib_no_event_billing.ex", 4) =~
               "(sib_no_event_booking.ex:2), which declares no such event; did you mean :visit_booked?"
    end
  end

  describe "X6: the fields a subscriber uses are in the publisher's schema" do
    test "a removed field breaks the include, the process manager and the boundary, naming both sides" do
      violations = pair("sib_removed", "      field :room, :string")

      assert assert_linked(
               violations,
               "X6: process :billing includes :visit_booked",
               "sib_removed_billing.ex",
               15
             ) =~
               "correlates on :visit_id, which event :visit_booked of " <>
                 "#{inspect(@fixtures)}.SibRemovedBooking (sib_removed_booking.ex:9) does not have"

      assert_linked(
        violations,
        "X6: process manager :chase handles :visit_booked",
        "sib_removed_billing.ex",
        19
      )

      assert_linked(
        violations,
        "X6: dcb :visit_slot consults :visit_booked matching :visit_id",
        "sib_removed_billing.ex",
        29
      )

      assert length(violations) == 3
    end

    test "a changed type" do
      violations =
        pair("sib_retyped", "      field :visit_id, :string\n      field :room, :string")

      assert assert_linked(violations, "X6: process :billing", "sib_retyped_billing.ex", 15) =~
               "(sib_retyped_booking.ex:9) has as :string, not :id"

      assert length(violations) == 3
    end

    test "a field made optional, or personal" do
      optional = pair("sib_optional", "      field :visit_id, :id, optional: true")

      assert assert_linked(optional, "X6: process :billing", "sib_optional_billing.ex", 15) =~
               "declares optional; a field telling which run an event belongs to cannot be"

      personal =
        pair("sib_personal", """
              field :visit_id, :id, personal: :patient_id
              field :patient_id, :id, subject: :patient
        """)

      assert_linked(personal, "declares personal", "sib_personal_billing.ex", 15)
    end

    test "an event renamed with as: is checked under its local name" do
      billing =
        "SibRenamedBilling"
        |> subscriber("SibRenamedBooking", ":visit_booked, as: [visit_booked: :booked]")
        |> String.replace("include :visit_booked", "include :booked")
        |> String.replace("starts_on :visit_booked", "starts_on :booked")
        |> String.replace("consults :visit_booked", "consults :booked")

      violations =
        links([
          {"sib_renamed_booking.ex",
           publisher("SibRenamedBooking", "      field :room, :string")},
          {"sib_renamed_billing.ex", billing}
        ])

      assert assert_linked(
               violations,
               "X6: process :billing includes :booked",
               "sib_renamed_billing.ex",
               15
             ) =~
               "which event :visit_booked of #{inspect(@fixtures)}.SibRenamedBooking " <>
                 "(sib_renamed_booking.ex:9) does not have"

      assert length(violations) == 3
    end

    test "controls: an optional field added, and a change to a field no declaration uses" do
      assert pair("sib_added", @fields <> "      field :note, :string, optional: true") == []
      assert pair("sib_unused", "      field :visit_id, :id\n      field :room, :integer") == []
    end
  end
end

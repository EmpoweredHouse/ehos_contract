defmodule EhOsContract.Next.ContractLinksScenariosTest do
  @moduledoc """
  v2 plan, E5b: **X9** (v2 §6) — scenario values L2 could not check: values of
  domain types, and the data of an event consumed from a sibling contract. Each
  violation names the scenario's declaration, and has a control that passes.
  """

  use EhOsContract.DslCase, async: false

  @fixtures EhOsContract.Next.Fixtures
  @domain EhOsContract.Next.Fixtures.ScenariosClinic

  setup_all do
    compile(
      """
      defmodule #{inspect(@domain)} do
        use EhOsContract.Domain, name: :clinic, language: :pl

        context :settlement, "Rozliczenia", subdomain: :core
        actor :reception, :human, "Recepcja"

        value :money, :integer, unit: :grosze
        value :status, {:enum, [:active, :expired]}

        value :address do
          field :street, :string
          field :city, :string
          field :apartment, :string, optional: true
        end
      end
      """,
      "scenarios_clinic.ex"
    )

    :ok
  end

  describe "values of domain types" do
    # The command's data at line 23, the expected event's at line 24.
    defp registration(name, command, expected) do
      {"#{Macro.underscore(name)}.ex",
       """
       defmodule #{inspect(Module.concat(@fixtures, name))} do
         use EhOsContract.Next.Contract, domain: #{inspect(@domain)}, context: :settlement

         aggregate :visit, "Wizyta" do
           identity :visit_id

           command :register, "Rejestracja", by: :reception, emits: :registered do
             field :status, :status
             field :address, :address
             field :amounts, {:list, :money}
           end

           event :registered, "Zarejestrowano" do
             field :status, :status
           end
         end

         process :visit, "Wizyta" do
           correlate :visit_id
         end

         scenario "rejestracja" do
           command :register, #{command}
           expect :registered, #{expected}
         end
       end
       """}
    end

    test "control: values that fit pass" do
      assert links([
               registration(
                 "ScnValuesRight",
                 ~s|%{status: :active, address: %{street: "Polna", city: "Kraków"}, amounts: [100, 200]}|,
                 "%{status: :active}"
               )
             ]) == []
    end

    test "an enum member, a value's fields, a list's items, and what is expected" do
      violations =
        links([
          registration(
            "ScnValuesWrong",
            ~s|%{status: :unknown, address: %{street: "Polna", zip: "30-001"}, amounts: [100, "200"]}|,
            "%{status: :gone}"
          )
        ])

      file = "scn_values_wrong.ex"

      assert assert_linked(violations, "field :status: :unknown", file, 23) =~
               ~s|X9: scenario "rejestracja": command :register, field :status: :unknown is not | <>
                 "one of [:active, :expired]"

      assert_linked(violations, "field :address: :address has no field :zip", file, 23)
      assert_linked(violations, "field :address: :address needs :city", file, 23)
      assert_linked(violations, ~s|field :amounts: "200" is not an :integer|, file, 23)
      assert_linked(violations, "event :registered, field :status: :gone", file, 24)
      assert length(violations) == 5
    end
  end

  describe "the data of a sibling's event" do
    defp booking(name) do
      {"#{Macro.underscore(name)}.ex",
       """
       defmodule #{inspect(Module.concat(@fixtures, name))} do
         use EhOsContract.Next.Contract, domain: #{inspect(@domain)}, context: :settlement

         aggregate :booking, "Rezerwacja" do
           identity :booking_id

           command :book_visit, "Rezerwacja wizyty", by: :reception, emits: :visit_booked

           event :visit_booked, "Wizyta zarezerwowana" do
             field :visit_id, :id
             field :room, :string
             field :note, :string, optional: true
           end
         end

         process :booking, "Rezerwacja" do
           correlate :booking_id
         end
       end
       """}
    end

    # The delivered event's data at line 20.
    defp billing(name, booking, data) do
      {"#{Macro.underscore(name)}.ex",
       """
       defmodule #{inspect(Module.concat(@fixtures, name))} do
         use EhOsContract.Next.Contract, domain: #{inspect(@domain)}, context: :settlement

         consumes #{inspect(Module.concat(@fixtures, booking))}, :visit_booked

         aggregate :billing, "Rozliczenie" do
           identity :visit_id
           command :bill_visit, "Rozliczenie wizyty", by: :reception, emits: :visit_billed
           event :visit_billed, "Wizyta rozliczona"
         end

         process :billing, "Rozliczenie" do
           correlate :visit_id
         end

         policy :bill_on_booking, "Rozlicz po rezerwacji",
           handles: :visit_booked, issues: :bill_visit

         scenario "rezerwacja rozliczona" do
           on :visit_booked, #{data}
           issues :bill_visit
         end
       end
       """}
    end

    test "control: data that fits the sibling's event passes, without its identity" do
      assert links([
               booking("ScnSiblingRightBooking"),
               billing(
                 "ScnSiblingRightBilling",
                 "ScnSiblingRightBooking",
                 ~s|%{visit_id: "v-1", room: "12"}|
               )
             ]) == []
    end

    test "an unknown key, a missing field and a value of the wrong type" do
      violations =
        links([
          booking("ScnSiblingWrongBooking"),
          billing(
            "ScnSiblingWrongBilling",
            "ScnSiblingWrongBooking",
            ~s|%{visit_id: 1, rooom: "12"}|
          )
        ])

      file = "scn_sibling_wrong_billing.ex"

      assert assert_linked(violations, "no field :rooom", file, 20) =~
               ~s|X9: scenario "rezerwacja rozliczona": event :visit_booked of | <>
                 "#{inspect(@fixtures)}.ScnSiblingWrongBooking (scn_sibling_wrong_booking.ex:9): " <>
                 "no field :rooom"

      assert_linked(violations, "needs :room", file, 20)
      assert_linked(violations, "field :visit_id: 1 is not an :id, a string", file, 20)
      assert length(violations) == 3
    end
  end
end

defmodule EhOsContract.ContractBoundariesTest do
  @moduledoc """
  v2 plan, E4: **the L2 rules of D10 and D11** (v2 §16) — a query's scope, and what
  crosses to another application. Each refusal names the declaration's file and
  line, and has a control beside it that compiles.
  """

  use EhOsContract.DslCase, async: false

  @unit """
    aggregate :visit, "Wizyta" do
      identity :visit_id
      command :close_visit, "Zamknięcie wizyty", by: :reception, emits: :visit_closed

      event :visit_closed, "Wizyta zamknięta", terminal: true do
        field :clinic_id, :id
        field :closed_at, :timestamp
        field :patient_id, :id, subject: :patient
        field :patient_name, :string, personal: :patient_id
      end
    end

    process :visit, "Wizyta" do
      correlate :visit_id
    end

    read_model :open_visits, "Wizyty do rozliczenia", projects: :visit_closed do
      field :clinic_id, :id
      field :total, :money
    end
  """

  describe "D10: a command narrowed by its scope (plan E9c)" do
    test "no by:, a scope that is not one of its fields, and an optional one" do
      message =
        refuse_contract("CommandScopeWrong", """
          aggregate :visit, "Wizyta" do
            identity :visit_id

            command :close_visit, "Zamknięcie", emits: :visit_closed, scope: :visit_id

            command :bill_visit, "Rozliczenie", by: :reception, emits: :visit_closed,
              scope: :clinic_id

            command :move_visit, "Przeniesienie", by: :reception, emits: :visit_closed,
              scope: :clinic_id do
              field :clinic_id, :id, optional: true
            end

            event :visit_closed, "Wizyta zamknięta", terminal: true
          end

          process :visit, "Wizyta" do
            correlate :visit_id
          end
        """)

      assert message =~
               "D10: command :close_visit is scoped by :visit_id, and names no by:, so no grant " <>
                 "could carry its scope (command_scope_wrong.ex:7)"

      assert message =~
               "D10: command :bill_visit is scoped by :clinic_id, which is not one of its fields " <>
                 "(command_scope_wrong.ex:9)"

      assert message =~
               "D10: command :move_visit is scoped by :clinic_id, which it declares optional; a " <>
                 "grant cannot narrow a missing value (command_scope_wrong.ex:12)"
    end

    test "a scope is one value, and not an identity the library generates" do
      message =
        refuse_contract("CommandScopeShape", """
          aggregate :visit, "Wizyta" do
            identity :visit_id, generated: :uuid

            command :book_visit, "Rezerwacja", by: :reception, emits: :visit_booked,
              creates: true, scope: :visit_id

            command :move_visit, "Przeniesienie", by: :reception, emits: :visit_booked,
              scope: :clinic_ids do
              field :clinic_ids, {:list, :id}
            end

            event :visit_booked, "Wizyta zarezerwowana"
          end

          process :visit, "Wizyta" do
            correlate :visit_id
          end

          read_model :visits, "Wizyty", projects: :visit_booked do
            field :clinic_ids, {:list, :id}
          end

          query :by_clinics, "Według przychodni", reads: :visits, by: :reception do
            param :clinic_ids, {:list, :id}
            scope :clinic_ids
          end
        """)

      assert message =~
               "D10: command :book_visit is scoped by :visit_id, the identity the library " <>
                 "generates, which the command that creates the aggregate arrives without"

      assert message =~
               "D10: command :move_visit is scoped by :clinic_ids, a {:list, :id}; a scope is one value"

      assert message =~
               "D10: query :by_clinics is scoped by :clinic_ids, a {:list, :id}; a scope is one value"
    end

    test "F7: a command's scope field is not personal" do
      message =
        refuse_contract("CommandScopePersonal", """
          aggregate :visit, "Wizyta" do
            identity :visit_id

            command :close_visit, "Zamknięcie", by: :reception, emits: :visit_closed,
              scope: :patient_name do
              field :patient_id, :id, subject: :patient
              field :patient_name, :string, personal: :patient_id
            end

            event :visit_closed, "Wizyta zamknięta", terminal: true
          end

          process :visit, "Wizyta" do
            correlate :visit_id
          end
        """)

      assert message =~
               "F7: command :close_visit, field :patient_name is personal, and it is the " <>
                 "command's scope, whose value is written with every authorization decision"
    end

    test "control: scoped by its identity, and by a declared field" do
      model =
        compile_contract("CommandScopeRight", """
          aggregate :visit, "Wizyta" do
            identity :visit_id

            command :close_visit, "Zamknięcie", by: :reception, emits: :visit_closed,
              scope: :visit_id

            command :move_visit, "Przeniesienie", by: :reception, emits: :visit_closed,
              scope: :clinic_id do
              field :clinic_id, :id
            end

            event :visit_closed, "Wizyta zamknięta", terminal: true
          end

          process :visit, "Wizyta" do
            correlate :visit_id
          end
        """)

      scopes = Map.new(model.commands, &{&1.name, Map.get(&1, :scope)})
      assert scopes == %{close_visit: :visit_id, move_visit: :clinic_id}
    end
  end

  describe "D10: a query is a capability, narrowed by its scope" do
    test "no by:, and a scope missing from the row, from the params, or of another type" do
      message =
        refuse_contract("QueryWrong", """
        #{@unit}
          query :nobody_asks, "Nikt", reads: :open_visits

          query :by_room, "Według gabinetu", reads: :open_visits, by: :reception do
            param :room_id, :id
            scope :room_id
          end

          query :unparametrised, "Bez parametru", reads: :open_visits, by: :reception do
            scope :clinic_id
          end

          query :mistyped, "Zły typ", reads: :open_visits, by: :reception do
            param :clinic_id, :string
            scope :clinic_id
          end
        """)

      assert message =~
               "D10: query :nobody_asks names no by:, so nobody could be granted it (query_wrong.ex:25)"

      assert message =~
               "D10: query :by_room is scoped by :room_id, which is not a field of read model " <>
                 ":open_visits (query_wrong.ex:27)"

      assert message =~
               "D10: query :unparametrised is scoped by :clinic_id, which is not one of its params " <>
                 "(query_wrong.ex:32)"

      assert message =~
               "D10: query :mistyped is scoped by :clinic_id, a :id in the read model and a :string " <>
                 "param (query_wrong.ex:36)"
    end

    test "control: v2 §16's query, with its capability" do
      model =
        compile_contract("QueryRight", """
        #{@unit}
          query :open_visits_for_clinic, "Otwarte wizyty w przychodni",
            reads: :open_visits, by: [:reception], returns: :many do
            param :clinic_id, :id
            scope :clinic_id
          end
        """)

      assert [%{scope: :clinic_id, params: [%{name: :clinic_id, type: :id}]}] = model.queries
      assert model.grants.reception.queries == [:open_visits_for_clinic]
    end
  end

  describe "D11: an event leaves through publish" do
    test "from an unknown event, carrying unknown or personal fields, idempotent on others" do
      message =
        refuse_contract("PublishWrong", """
        #{@unit}
          publish :visit_lost, as: "rehmed.visit.lost.v1", from: :visit_lost, fields: [:visit_id]

          publish :visit_closed,
            as: "rehmed.visit.closed.v1",
            from: :visit_closed,
            fields: [:visit_id, :total, :patient_name],
            idempotent_on: [:clinic_id]

          publish :visit_closed_again, as: "rehmed.visit.closed.v1", from: :visit_closed, fields: []
        """)

      assert message =~
               "D11: publication :visit_lost is built from :visit_lost, which is not an event of " <>
                 "this contract (publish_wrong.ex:25)"

      assert message =~
               "D11: publication :visit_closed carries :total, which event :visit_closed does not " <>
                 "have (publish_wrong.ex:27)"

      assert message =~
               "D11: publication :visit_closed carries :patient_name, which is personal; a copy on " <>
                 "a broker cannot be erased"

      assert message =~
               "D11: publication :visit_closed is idempotent on :clinic_id, which it does not carry"

      assert message =~
               "D11: publication :visit_closed_again carries no fields (publish_wrong.ex:33)"

      assert message =~
               ~s|D11: publication :visit_closed_again is named "rehmed.visit.closed.v1", like an | <>
                 "earlier one"
    end

    test "a name that is not versioned is refused" do
      message =
        refuse_contract("PublishUnversioned", """
        #{@unit}
          publish :visit_closed, as: "Rehmed/VisitClosed", from: :visit_closed, fields: [:visit_id]
        """)

      assert message =~
               ~s|D11: publication :visit_closed: "Rehmed/VisitClosed" is not a versioned name: | <>
                 "the application's namespace, which may hold a dash but not at either end, then " <>
                 "dotted snake_case segments, ending in .v<n>"
    end

    test "a name ending in a newline is refused" do
      message =
        refuse_contract("PublishNewline", """
        #{@unit}
          publish :visit_closed, as: "rehmed.visit.closed.v1\\n", from: :visit_closed, fields: [:visit_id]
        """)

      assert message =~
               ~s|D11: publication :visit_closed: "rehmed.visit.closed.v1\\n" is not a versioned name|
    end

    test "a dash only inside the namespace, the first segment" do
      message =
        refuse_contract("PublishDashed", """
        #{@unit}
          publish :leading, as: "-shop.visit.closed.v1", from: :visit_closed, fields: [:visit_id]
          publish :trailing, as: "shop-.visit.closed.v1", from: :visit_closed, fields: [:visit_id]
          publish :inner, as: "my-shop.visit-closed.v1", from: :visit_closed, fields: [:visit_id]
        """)

      for {name, as} <- [
            leading: "-shop.visit.closed.v1",
            trailing: "shop-.visit.closed.v1",
            inner: "my-shop.visit-closed.v1"
          ] do
        assert message =~ ~s|D11: publication #{inspect(name)}: "#{as}" is not a versioned name|
      end
    end

    test "control: an application's namespace with a dash, as EHOS names one (#50)" do
      assert %{publishes: [%{as: "my-shop.visit.closed.v1"}]} =
               compile_contract("PublishDashedRight", """
               #{@unit}
                 publish :visit_closed, as: "my-shop.visit.closed.v1",
                   from: :visit_closed,
                   fields: [:visit_id]
               """)
    end

    test "control: v2 §16's publication compiles, identity among its fields" do
      assert %{publishes: [publish], digests: %{"publish:visit_closed" => _}} =
               compile_contract("PublishRight", """
               #{@unit}
                 publish :visit_closed, as: "rehmed.visit.closed.v1",
                   from: :visit_closed,
                   fields: [:visit_id, :closed_at],
                   idempotent_on: [:visit_id]
               """)

      assert publish == %{
               name: :visit_closed,
               as: "rehmed.visit.closed.v1",
               from: :visit_closed,
               fields: [:visit_id, :closed_at],
               idempotent_on: [:visit_id]
             }
    end
  end

  describe "D11: another application's event is consumed by name" do
    test "without a local name, with events, without fields, or with a bare name" do
      message =
        refuse_contract("ConsumesByNameWrong", """
          consumes "rehmed.visit.closed.v1" do
            field :visit_id, :id
          end

          consumes "rehmed.visit.opened.v1", [:visit_opened], as: :visit_opened
          consumes "visit_moved", as: :visit_moved

        #{@unit}
        """)

      assert message =~
               ~s|D11: consumes "rehmed.visit.closed.v1" needs as: the name the event has in this | <>
                 "contract (consumes_by_name_wrong.ex:4)"

      assert message =~
               ~s|D11: consumes "rehmed.visit.opened.v1" lists events; a published name is one event, | <>
                 "read by its fields (consumes_by_name_wrong.ex:8)"

      assert message =~ ~s|D11: consumes "rehmed.visit.opened.v1" lists no fields|
      assert message =~ ~s|D11: consumes "visit_moved": "visit_moved" is not a versioned name|
    end

    test "a dash only inside the namespace, as in a publication" do
      message =
        refuse_contract("ConsumesDashedWrong", """
          consumes "shop-.visit.closed.v1", as: :visit_closed_elsewhere do
            field :visit_id, :id
          end

        #{@unit}
        """)

      assert message =~
               ~s|D11: consumes "shop-.visit.closed.v1": "shop-.visit.closed.v1" is not a|
    end

    test "control: another application's event, named under a namespace with a dash" do
      model =
        compile_contract("ConsumesDashedRight", """
          consumes "my-shop.visit.closed.v1", as: :visit_closed_elsewhere do
            field :visit_id, :id
          end

        #{@unit}
        """)

      assert [%{kind: :published, from: "my-shop.visit.closed.v1"}] = model.consumes
    end

    test "control: v2 §16's subscriber, with a policy on the consumed event" do
      model =
        compile_contract("ConsumesByNameRight", """
          consumes "rehmed.visit.closed.v1", as: :visit_closed_elsewhere do
            field :visit_id, :id
            field :closed_at, :timestamp
          end

        #{@unit}
          policy :close_on_remote_close, "Zamknij po zamknięciu gdzie indziej",
            handles: :visit_closed_elsewhere,
            issues: :close_visit
        """)

      assert [
               %{kind: :published, from: "rehmed.visit.closed.v1", as: :visit_closed_elsewhere} =
                 c
             ] =
               model.consumes

      assert Enum.map(c.fields, & &1.name) == [:visit_id, :closed_at]
      assert Map.has_key?(model.digests, "consumes:visit_closed_elsewhere")
    end
  end

  describe "D10 in the domain" do
    test "an actor carries the scope dimensions a grant narrows by" do
      compile("""
      defmodule EhOsContract.ContractBoundariesTest.Domain do
        use EhOsContract.Domain, name: :clinic, language: :pl
        actor :reception, :human, "Recepcja", scope: [:clinic_id]
        actor :manager, :human, "Menedżer"
      end
      """)

      assert [%{name: :reception, scope: [:clinic_id]}, %{name: :manager, scope: []}] =
               EhOsContract.Model.fetch(EhOsContract.ContractBoundariesTest.Domain).actors
    end
  end
end

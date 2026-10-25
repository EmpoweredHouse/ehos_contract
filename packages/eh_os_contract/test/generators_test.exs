defmodule EhOsContract.GeneratorsTest do
  @moduledoc """
  Plan DD, PC1 (#264): **valid examples of a contract's data**. Every generated command,
  event and entity row fits what the engine stores, a domain value with invariants is
  one of its examples, and a history is one the unit's lifecycle allows. On the
  engine's invented rigs: `LifecycleRig` for the lifecycle, `ValueRig` for values,
  `ReadRig` for an entity.
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias EhOsContract.{Codec, Generators, Lifecycle, Model}

  defp fits!(model, declaration, struct) do
    values = Codec.values(model.domain)
    data = Map.from_struct(struct)

    assert Codec.problems(declaration.fields, data, values, model.domain) == [],
           "#{inspect(struct)} does not fit #{inspect(declaration.name)}"
  end

  describe "commands and events" do
    property "every command and event of a contract fits its declaration" do
      for contract <- [LifecycleRig.Visits, ValueRig.Till] do
        model = Model.fetch(contract)

        for declaration <- model.commands do
          check all(command <- Generators.command(contract, declaration.name), max_runs: 25) do
            fits!(model, declaration, command)
          end
        end

        for declaration <- model.events do
          check all(event <- Generators.event(contract, declaration.name), max_runs: 25) do
            fits!(model, declaration, event)
          end
        end
      end
    end

    property "a value with invariants is only ever one of its examples" do
      check all(command <- Generators.command(ValueRig.Till, :pay_in)) do
        assert command.amount in [1, 250]
        assert command.fees == nil or Enum.all?(command.fees, &(&1 == 1000))
      end
    end

    property "fields: fixes a field by a constant, or narrows it by a generator" do
      check all(
              command <-
                Generators.command(LifecycleRig.Visits, :book_visit,
                  fields: [visit_id: "visit-1"]
                ),
              paid <-
                Generators.command(ValueRig.Till, :pay_in,
                  fields: [till_id: member_of(["t-1", "t-2"]), fees: nil]
                )
            ) do
        assert command.visit_id == "visit-1"
        assert paid.till_id in ["t-1", "t-2"]
        assert paid.fees == nil
      end
    end

    property "a command that creates its aggregate has no identity" do
      check all(command <- Generators.command(BoundaryRig.Waitlist, :join_waitlist)) do
        assert command.entry_id == nil
      end
    end

    test "an event's personal field is sometimes erased, naming its subject" do
      model = Model.fetch(ShreddingRig.Members)
      joined = Enum.find(model.events, &(&1.name == :joined))
      sample = ShreddingRig.Members |> Generators.event(:joined) |> Enum.take(200)

      erased = Enum.filter(sample, &match?(%EhOsContract.Erased{}, &1.name))
      assert erased != [] and length(erased) < 200

      assert Enum.all?(
               erased,
               &(&1.name == %EhOsContract.Erased{subject: :member, id: &1.member_id})
             )

      for event <- sample, do: fits!(model, joined, event)

      # A command is what a caller sends, never erased.
      refute ShreddingRig.Members
             |> Generators.command(:join)
             |> Enum.take(100)
             |> Enum.any?(&match?(%EhOsContract.Erased{}, &1.name))
    end

    test "an unknown option, or a bad max_length:, is refused by name" do
      assert_raise ArgumentError, ~r/no option :size/, fn ->
        Generators.command(LifecycleRig.Visits, :book_visit, size: 3)
      end

      assert_raise ArgumentError, ~r/max_length: is a non-negative integer, not -1/, fn ->
        Generators.history(LifecycleRig.Visits, :visit, max_length: -1)
      end
    end

    test "an unknown name, or a field the declaration lacks, is refused by name" do
      assert_raise ArgumentError, ~r/declares no command :book/, fn ->
        Generators.command(LifecycleRig.Visits, :book)
      end

      assert_raise ArgumentError, ~r/declares no event :visit_booked/, fn ->
        Generators.event(LifecycleRig.Visits, :visit_booked)
      end

      assert_raise ArgumentError, ~r/fields: names :room/, fn ->
        Generators.command(LifecycleRig.Visits, :book_visit, fields: [room: "12"])
      end
    end
  end

  describe "an entity's row" do
    property "fits the entity, its identity among its fields" do
      domain = Model.fetch(ReadRig.Domain)
      product = Enum.find(domain.entities, &(&1.name == :product))

      check all(row <- Generators.entity_row(ReadRig.Domain, :product)) do
        assert is_binary(row.product_id)

        assert Codec.problems(product.fields, row, Codec.values(ReadRig.Domain), ReadRig.Domain) ==
                 []
      end
    end
  end

  describe "a history" do
    property "is one the visit's lifecycle allows, of one visit" do
      model = Model.fetch(LifecycleRig.Visits)
      unit = Enum.find(model.units, &(&1.name == :visit))
      lifecycle = Lifecycle.of(unit)

      check all(events <- Generators.history(LifecycleRig.Visits, :visit, max_length: 8)) do
        names = for e <- events, do: Model.fetch(LifecycleRig.Visits) |> name_of(e)

        assert length(events) <= 8
        assert events |> Enum.map(& &1.visit_id) |> Enum.uniq() |> length() <= 1

        # Walking it never raises: every step is one the lifecycle allows.
        Enum.reduce(names, nil, fn name, status ->
          assert {kind, next} = Lifecycle.allowed(lifecycle, status, name)
          assert kind in [:moved, :stayed]
          next
        end)

        for event <- events do
          fits!(model, Enum.find(model.events, &(&1.name == name_of(model, event))), event)
        end
      end
    end

    test "reaches a final status in some histories, and stops there" do
      model = Model.fetch(LifecycleRig.Visits)

      finals =
        LifecycleRig.Visits
        |> Generators.history(:visit)
        |> Enum.take(300)
        |> Enum.map(fn events ->
          names = Enum.map(events, &name_of(model, &1))
          {Enum.find_index(names, &(&1 in [:closed, :cancelled])), length(names)}
        end)

      assert Enum.all?(finals, fn {final, length} -> final == nil or final == length - 1 end)
      assert Enum.any?(finals, fn {final, _} -> final != nil end)
    end

    property "fields: fixes the identity of every event, or narrows it once for the history" do
      check all(
              events <-
                Generators.history(LifecycleRig.Visits, :visit, fields: [visit_id: "visit-1"]),
              narrowed <-
                Generators.history(LifecycleRig.Visits, :visit,
                  fields: [visit_id: member_of(Enum.map(1..50, &"visit-#{&1}"))]
                )
            ) do
        assert Enum.all?(events, &(&1.visit_id == "visit-1"))
        assert narrowed |> Enum.map(& &1.visit_id) |> Enum.uniq() |> length() <= 1
      end
    end

    # #435: a key typed by a domain value keeps the value's invariants in a history too.
    property "an identity typed by a domain value is one of the value's examples" do
      check all(events <- Generators.history(ValueRig.Till, :drawer, max_length: 3)) do
        assert Enum.all?(events, &(&1.shift_id == "2026-01-31"))
      end
    end

    test "fields: naming what no event of the unit has is refused" do
      assert_raise ArgumentError, ~r/which no event of unit :visit has/, fn ->
        Generators.history(LifecycleRig.Visits, :visit, fields: [room: "12"])
      end
    end

    test "a history of a unit the contract lacks is refused by name" do
      assert_raise ArgumentError, ~r/declares no unit :appointment/, fn ->
        Generators.history(LifecycleRig.Visits, :appointment)
      end
    end
  end

  defp name_of(model, %module{}) do
    Enum.find(model.events, &(Model.module_for(model, :event, &1.name) == module)).name
  end
end

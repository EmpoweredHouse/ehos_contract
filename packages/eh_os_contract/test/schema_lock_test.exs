defmodule EhOsContract.SchemaLockTest do
  @moduledoc """
  Plan DD, V3 (#340): the fields of every event, by its type and version, recorded as a
  row holds them, and a change to a recorded version refused. On maps in memory and on
  the library's rigs, and the task on a file of its own: the library keeps no lock.
  """

  use ExUnit.Case, async: true

  alias EhOsContract.SchemaLock
  alias Mix.Tasks.EhOsContract.Schema

  @type_name "shop.orders.order_placed"

  defp field(name, type, opts \\ []),
    do:
      Map.merge(
        %{name: name, type: type, optional: false, personal: nil, subject: nil, label: nil},
        Map.new(opts)
      )

  defp fields,
    do: [
      field(:order_id, :id),
      field(:customer_id, :id, subject: :customer),
      field(:note, :string, optional: true, personal: :customer_id),
      field(:channel, {:enum, [web: "Online", shop: "In a shop"]}),
      field(:total, :money)
    ]

  defp values,
    do: %{
      money: %{
        name: :money,
        type: nil,
        fields: [field(:amount, :decimal), field(:currency, {:enum, [:pln, :eur]})]
      },
      count: %{name: :count, type: :integer, fields: []}
    }

  defp lock(fields, version \\ 1, values \\ values()),
    do: %{@type_name => %{version => SchemaLock.fields(fields, values)}}

  defp replace(fields, name, by),
    do: Enum.map(fields, &if(&1.name == name, do: by, else: &1))

  # A lock at version 1 of `was`, and the contract at version 2 of `is`, its step `step`.
  defp raised(was, is, step),
    do: SchemaLock.merge(lock(was), lock(is, 2), %{@type_name => %{1 => step}})

  describe "a field as a row holds it" do
    test "sorted by name, with only what is set beside its type" do
      assert SchemaLock.fields(fields(), values()) == [
               channel: [type: {:enum, [:shop, :web]}],
               customer_id: [type: :id, subject: :customer],
               note: [type: :string, optional: true, personal: :customer_id],
               order_id: [type: :id],
               total: [
                 type:
                   {:fields, [amount: [type: :decimal], currency: [type: {:enum, [:eur, :pln]}]]}
               ]
             ]
    end

    test "a reference is an :id, a list what it holds, a value its inner type or fields" do
      fields = [
        field(:visit, {:id, :visit}),
        field(:counts, {:list, :count}),
        field(:totals, {:list, :money})
      ]

      assert SchemaLock.fields(fields, values()) == [
               counts: [type: {:list, :integer}],
               totals: [
                 type:
                   {:list,
                    {:fields, [amount: [type: :decimal], currency: [type: {:enum, [:eur, :pln]}]]}}
               ],
               visit: [type: :id]
             ]
    end

    test "the order of fields, a label and a domain value's name change nothing" do
      renamed =
        values() |> Map.delete(:money) |> Map.put(:amount, %{values().money | name: :amount})

      reordered =
        fields()
        |> Enum.reverse()
        |> replace(:total, field(:total, :amount, label: "Amount"))

      assert SchemaLock.fields(reordered, renamed) == SchemaLock.fields(fields(), values())
    end

    test "a real contract's events, by their type in the log and their version" do
      declared = SchemaLock.declared([UpcastRig.Demands])

      assert %{3 => fields} = declared["upcast_rig.demands.demand_opened"]
      assert fields[:note] == [type: :string, optional: true, personal: :requester_id]
      assert Map.keys(declared["upcast_rig.demands.fee_charged"]) == [2]
    end
  end

  describe "merge/2" do
    test "records what the lock lacks, and keeps the rest" do
      other = %{"shop.orders.order_cancelled" => %{1 => [order_id: [type: :id]]}}

      both = Map.merge(other, lock(fields()))

      assert SchemaLock.merge(other, both) == {:ok, both}
      assert SchemaLock.merge(lock(fields()), lock(fields())) == {:ok, lock(fields())}
    end

    test "records in place a change old rows still read" do
      counted =
        fields() ++
          [
            field(:quantity, :integer),
            field(:lines, {:list, :money}),
            field(:ref, :id, optional: true)
          ]

      values = values()
      wider = update_in(values.money.fields, &(&1 ++ [field(:rate, :decimal, optional: true)]))

      changes = [
        {fields() ++ [field(:courier, :string, optional: true)], values()},
        {fields() ++ [field(:hint, :string, optional: true, personal: :customer_id)], values()},
        {replace(fields(), :channel, field(:channel, {:enum, [:web, :shop, :phone]})), values()},
        {fields(), wider}
      ]

      for {changed, values} <- changes do
        assert {:ok, merged} = SchemaLock.merge(lock(fields()), lock(changed, 1, values))
        assert merged == lock(changed, 1, values)
      end

      for changed <- [
            replace(counted, :quantity, field(:quantity, :decimal)),
            replace(counted, :ref, field(:ref, :string, optional: true)),
            replace(counted, :quantity, field(:quantity, :integer, optional: true)),
            replace(counted, :lines, field(:lines, {:list, :money}, optional: true))
          ] do
        assert {:ok, _merged} = SchemaLock.merge(lock(counted), lock(changed))
      end

      assert {:ok, _merged} = SchemaLock.merge(lock(counted), lock(counted, 1, wider))
    end

    test "keeps a field removed in place, marked, and holds a field declared again to it" do
      without = Enum.reject(fields(), &(&1.name == :note))

      assert {:ok, %{@type_name => %{1 => kept}}} =
               SchemaLock.merge(lock(fields()), lock(without))

      assert kept[:note] == [
               type: :string,
               optional: true,
               personal: :customer_id,
               removed: true
             ]

      marked = %{@type_name => %{1 => kept}}
      assert SchemaLock.merge(marked, lock(without)) == {:ok, marked}
      assert SchemaLock.decode(SchemaLock.encode(marked)) == {:ok, marked}

      again = fn note -> replace(fields(), :note, note) end

      assert {:ok, %{@type_name => %{1 => back}}} =
               SchemaLock.merge(
                 marked,
                 lock(again.(field(:note, :string, optional: true, personal: :customer_id)))
               )

      refute Keyword.has_key?(back[:note], :removed)

      for {note, said} <- [
            {field(:note, :integer, optional: true, personal: :customer_id),
             "no step converts a sealed value"},
            {field(:note, :string, optional: true), "whether a field is personal"},
            {field(:note, :string, personal: :customer_id), "no step fills it"}
          ] do
        assert {:error, [problem]} = SchemaLock.merge(marked, lock(again.(note)))
        assert problem =~ said
      end
    end

    test "refuses in place a change old rows would not read, naming the field" do
      changes = [
        {fields() ++ [field(:courier, :string)],
         "courier was added, [type: :string], and is required"},
        {replace(fields(), :channel, field(:channel, {:enum, [:web]})),
         "channel was [type: {:enum, [:shop, :web]}] and is [type: {:enum, [:web]}]"},
        {replace(fields(), :channel, field(:channel, :string)), "channel was"},
        {replace(fields(), :total, field(:total, :money, optional: true))
         |> replace(:channel, field(:channel, :integer)),
         "channel was [type: {:enum, [:shop, :web]}] and is [type: :integer], which a rename"}
      ]

      for {changed, said} <- changes do
        assert {:error, [problem]} = SchemaLock.merge(lock(fields()), lock(changed))
        assert problem =~ "#{@type_name} at schema_version 1: "
        assert problem =~ said
        assert problem =~ "a step `upcast from: 1` that covers the change"
        assert problem =~ "--forget #{@type_name}"
      end

      values = values()
      narrower = update_in(values.money.fields, &(&1 ++ [field(:rate, :decimal)]))
      assert {:error, [problem]} = SchemaLock.merge(lock(fields()), lock(fields(), 1, narrower))
      assert problem =~ "total was [type: {:fields"
      assert problem =~ "a step `upcast from: 1` that covers the change"

      ref = fields() ++ [field(:ref, :string, optional: true)]

      assert {:error, [problem]} =
               SchemaLock.merge(lock(ref), lock(fields() ++ [field(:ref, :string)]))

      assert problem =~ "ref was [type: :string, optional: true] and is [type: :string]"
      assert problem =~ "a step `upcast from: 1` that covers the change"

      optional = replace(fields(), :customer_id, field(:customer_id, :id, optional: true))
      assert {:error, [_problem]} = SchemaLock.merge(lock(optional), lock(fields()))
    end

    test "refuses a field turned personal, or sealed by another identifier, at any version" do
      for changed <- [
            replace(fields(), :note, field(:note, :string, optional: true)),
            replace(fields(), :note, field(:note, :string, optional: true, personal: :order_id)),
            replace(fields(), :customer_id, field(:customer_id, :id, subject: :patient))
          ] do
        assert {:error, [problem]} = SchemaLock.merge(lock(fields()), lock(changed))
        assert problem =~ ~r/whether a field is personal|the subject of an identifier that seals/
        assert problem =~ "declare a new event instead"

        assert {:error, [problem]} = raised(fields(), changed, :function)
        assert problem =~ "#{@type_name} at schema_version 2: "
        assert problem =~ "declare a new event instead"
      end
    end

    test "records a raised version beside the old one when its step covers each change" do
      cents = fields() ++ [field(:amount_minor, :integer)]
      decimal = fields() ++ [field(:amount, :decimal)]

      covered = [
        {fields(), fields() ++ [field(:courier, :string)], %{rename: %{}, default: [:courier]}},
        {fields() ++ [field(:reason, :string)], fields() ++ [field(:why, :string)],
         %{rename: %{reason: :why}, default: []}},
        {cents, decimal, :function},
        {fields(), replace(fields(), :channel, field(:channel, :string)), :function},
        {fields(), fields(), %{rename: %{}, default: []}}
      ]

      for {was, is, step} <- covered do
        assert {:ok, %{@type_name => versions}} = raised(was, is, step)
        assert versions == %{1 => lock(was)[@type_name][1], 2 => lock(is)[@type_name][1]}
      end
    end

    test "refuses a raised version whose step leaves a change uncovered" do
      cents = fields() ++ [field(:amount_minor, :integer)]
      decimal = fields() ++ [field(:amount, :decimal)]

      uncovered = [
        {fields(), fields() ++ [field(:courier, :string)], %{rename: %{}, default: []},
         "courier was added, [type: :string], and is required: give it a `default:`"},
        {cents, decimal, %{rename: %{}, default: []}, "amount was added"},
        {fields() ++ [field(:reason, :string)], fields() ++ [field(:why, :integer)],
         %{rename: %{reason: :why}, default: []},
         "why was [type: :string] and is [type: :integer], which a rename and a default " <>
           "cannot carry: write the step as a function"},
        {fields(), replace(fields(), :channel, field(:channel, {:enum, [:web]})),
         %{rename: %{}, default: []}, "channel was"}
      ]

      for {was, is, step, said} <- uncovered do
        assert {:error, [problem]} = raised(was, is, step)

        assert problem =~
                 "#{@type_name}, from schema_version 1 to 2 (`upcast from: 1`): #{said}"
      end
    end

    test "refuses a field the log tags rows with that the version before did not tag" do
      tagged = fields() ++ [field(:shop_id, :id)]

      for {was, step} <- [
            {fields() ++ [field(:shop_id, :id, optional: true)], :function},
            {fields() ++ [field(:shop_id, :string)], :function},
            {fields(), %{rename: %{}, default: [:shop_id]}},
            {fields() ++ [field(:store_id, :id)], %{rename: %{store_id: :shop_id}, default: []}}
          ] do
        assert {:error, [problem]} = raised(was, tagged, step)
        assert problem =~ "#{@type_name} at schema_version 2: shop_id was"
        assert problem =~ "the log tags rows with it, and the version before did not tag"
      end

      assert {:ok, _merged} = raised(tagged, tagged, %{rename: %{}, default: []})
    end

    test "refuses a personal field made required, since no step fills one an old row lacks" do
      required = replace(fields(), :note, field(:note, :string, personal: :customer_id))

      for lock <- [
            lock(fields()),
            SchemaLock.merge(lock(fields()), lock(Enum.reject(fields(), &(&1.name == :note))))
            |> elem(1)
          ] do
        assert {:error, [problem]} = SchemaLock.merge(lock, lock(required))
        assert problem =~ "it is personal and old rows may lack it, and no step fills it"

        two = %{@type_name => %{2 => lock(required)[@type_name][1]}}

        assert {:error, [problem]} =
                 SchemaLock.merge(lock, two, %{@type_name => %{1 => :function}})

        assert problem =~ "no step fills it"
      end
    end

    test "judges a change inside a value holding personal data field by field" do
      values =
        Map.put(values(), :contact, %{
          name: :contact,
          type: nil,
          fields: [
            field(:kind, {:enum, [:a, :b]}),
            field(:owner, :id, subject: :customer),
            field(:phone, :string, personal: :owner)
          ]
        })

      changed =
        update_in(values.contact.fields, &replace(&1, :kind, field(:kind, {:enum, [:a, :c]})))

      with_contact = fields() ++ [field(:contact, :contact)]
      lock = %{@type_name => %{1 => SchemaLock.fields(with_contact, values)}}
      declared = %{@type_name => %{2 => SchemaLock.fields(with_contact, changed)}}

      assert {:ok, _merged} = SchemaLock.merge(lock, declared, %{@type_name => %{1 => :function}})

      assert {:error, [problem]} =
               SchemaLock.merge(lock, declared, %{
                 @type_name => %{1 => %{rename: %{}, default: []}}
               })

      assert problem =~ "write the step as a function"
    end

    test "lets an identifier gain or lose a subject while nothing is sealed with it" do
      bare =
        replace(fields(), :customer_id, field(:customer_id, :id))
        |> Enum.reject(&(&1.name == :note))

      subject = replace(bare, :customer_id, field(:customer_id, :id, subject: :customer))
      sealed = subject ++ [field(:hint, :string, optional: true, personal: :customer_id)]

      assert {:ok, _merged} = SchemaLock.merge(lock(bare), lock(sealed))
      assert {:ok, _merged} = SchemaLock.merge(lock(subject), lock(bare))
      assert {:ok, _merged} = raised(bare, sealed, %{rename: %{}, default: []})
    end

    test "refuses a change no step carries inside a domain value, even under a function" do
      values = values()

      sealed =
        update_in(values.money.fields, fn fields ->
          [
            field(:payer, :id, subject: :customer)
            | replace(fields, :amount, field(:amount, :decimal, personal: :payer))
          ]
        end)

      plain = update_in(values.money.fields, &[field(:payer, :id, subject: :customer) | &1])
      was = %{@type_name => %{1 => SchemaLock.fields(fields(), plain)}}

      assert {:error, [problem]} = SchemaLock.merge(was, lock(fields(), 1, sealed))
      assert problem =~ "total was"
      assert problem =~ "within it, amount was"
      assert problem =~ "declare a new event instead"

      raised = %{@type_name => %{2 => SchemaLock.fields(fields(), sealed)}}

      assert {:error, [problem]} =
               SchemaLock.merge(was, raised, %{@type_name => %{1 => :function}})

      assert problem =~ "#{@type_name} at schema_version 2: total was"
    end

    test "reads a rename onto a name the version kept as the engine does: the renamed wins" do
      was = fields() ++ [field(:a, :string), field(:b, :integer)]
      is = fields() ++ [field(:b, :integer)]

      assert {:error, [problem]} = raised(was, is, %{rename: %{a: :b}, default: []})
      assert problem =~ "b was [type: :string] and is [type: :integer]"
    end

    test "judges a chain of steps across a version the lock skipped" do
      lock = lock(fields())
      declared = lock(fields() ++ [field(:c, :string)], 3)
      empty = %{rename: %{}, default: []}

      assert {:error, [problem]} =
               SchemaLock.merge(lock, declared, %{@type_name => %{1 => empty, 2 => empty}})

      assert problem =~
               "from schema_version 1 to 3 (`upcast from: 1`, `upcast from: 2`): c was added"

      for steps <- [
            %{1 => empty, 2 => %{rename: %{}, default: [:c]}},
            %{1 => %{rename: %{}, default: [:b]}, 2 => %{rename: %{b: :c}, default: []}},
            %{1 => %{rename: %{}, default: [:c]}, 2 => %{rename: %{b: :c}, default: []}},
            %{1 => :function, 2 => empty}
          ] do
        assert {:ok, %{@type_name => versions}} =
                 SchemaLock.merge(lock, declared, %{@type_name => steps})

        assert Map.keys(versions) == [1, 3]
      end
    end

    test "holds a field a later version declares again to what the earliest rows hold" do
      with_x = fields() ++ [field(:x, :integer, optional: true)]
      versions = %{1 => lock(with_x)[@type_name][1], 2 => lock(fields())[@type_name][1]}
      empty = %{rename: %{}, default: []}
      again = lock(fields() ++ [field(:x, :string, optional: true)], 3)

      assert {:error, [problem]} =
               SchemaLock.merge(%{@type_name => versions}, again, %{
                 @type_name => %{1 => empty, 2 => empty}
               })

      assert problem =~ "from schema_version 1 to 3"

      assert problem =~
               "x was [type: :integer, optional: true] and is [type: :string, optional: true]"
    end

    test "says apart, in place, what a new version would carry and what none would" do
      changed =
        replace(fields(), :note, field(:note, :string, optional: true))
        |> Kernel.++([field(:courier, :string)])

      assert {:error, [never, step]} = SchemaLock.merge(lock(fields()), lock(changed))
      assert never =~ "note was" and never =~ "declare a new event instead"
      refute never =~ "courier"
      assert step =~ "courier was added" and step =~ "a step `upcast from: 1`"
    end

    test "holds a nested change no step carries, whatever else changes around it" do
      values =
        Map.put(values(), :contact, %{
          name: :contact,
          type: nil,
          fields: [
            field(:owner, :id, subject: :customer),
            field(:phone, :string, personal: :owner)
          ]
        })

      plain =
        put_in(values.contact.fields, [
          field(:owner, :id, subject: :customer),
          field(:phone, :string)
        ])

      at = fn fields, values -> SchemaLock.fields(fields, values) end
      optional = fields() ++ [field(:contact, :contact, optional: true)]
      required = fields() ++ [field(:contact, :contact)]
      listed = fields() ++ [field(:contact, {:list, :contact}, optional: true)]

      for {is, is_values} <- [{required, plain}, {listed, values}] do
        lock = %{@type_name => %{1 => at.(optional, values)}}
        declared = %{@type_name => %{2 => at.(is, is_values)}}

        assert {:error, [problem]} =
                 SchemaLock.merge(lock, declared, %{@type_name => %{1 => :function}})

        assert problem =~ "declare a new event instead"
      end
    end

    test "reads a removed field as possibly absent, and one the declaration dropped as unread" do
      with_b = fields() ++ [field(:b, :string)]
      empty = %{rename: %{}, default: []}

      assert {:ok, %{@type_name => %{1 => marked}}} =
               SchemaLock.merge(lock(with_b), lock(fields()))

      assert marked[:b] == [type: :string, removed: true]
      lock = %{@type_name => %{1 => marked}}

      assert {:ok, _merged} =
               SchemaLock.merge(lock, lock(with_b, 2), %{
                 @type_name => %{1 => %{rename: %{}, default: [:b]}}
               })

      assert {:error, [problem]} =
               SchemaLock.merge(lock, lock(with_b, 2), %{@type_name => %{1 => empty}})

      assert problem =~ "rows written since it was removed lack it: give it a `default:`"

      dropped = %{
        1 => lock(fields() ++ [field(:a, :string)])[@type_name][1],
        2 => lock(fields() ++ [field(:a, :integer, optional: true)])[@type_name][1]
      }

      assert {:ok, %{@type_name => %{2 => two}}} =
               SchemaLock.merge(%{@type_name => dropped}, lock(fields(), 2), %{
                 @type_name => %{1 => empty}
               })

      assert two[:a] == [type: :integer, optional: true, removed: true]
    end

    test "reads every earlier version as the declared one, not as the versions between" do
      empty = %{rename: %{}, default: []}

      versions = %{
        1 => lock(fields() ++ [field(:b, :string, optional: true)])[@type_name][1],
        2 => lock(fields())[@type_name][1],
        3 => lock(fields() ++ [field(:b, :string)])[@type_name][1]
      }

      declared = lock(fields() ++ [field(:b, :string, optional: true)], 4)
      steps = %{1 => empty, 2 => %{rename: %{}, default: [:b]}, 3 => empty}

      assert {:ok, _merged} =
               SchemaLock.merge(%{@type_name => versions}, declared, %{@type_name => steps})

      wrong = lock(fields() ++ [field(:b, :integer, optional: true)], 4)

      assert {:error, [problem]} =
               SchemaLock.merge(%{@type_name => versions}, wrong, %{@type_name => steps})

      assert problem =~ "from schema_version 3 to 4"
    end

    test "leaves a step it cannot judge: one between versions the lock never recorded" do
      lock = %{@type_name => %{1 => SchemaLock.fields(fields(), values())}}
      declared = lock(fields() ++ [field(:courier, :string)], 3)
      steps = %{@type_name => %{1 => %{rename: %{}, default: []}, 2 => :function}}

      assert {:ok, %{@type_name => versions}} = SchemaLock.merge(lock, declared, steps)
      assert Map.keys(versions) == [1, 3]
    end

    test "the steps of a real contract, by event type and the version each reads" do
      steps = SchemaLock.steps([UpcastRig.Demands])

      assert steps["upcast_rig.demands.demand_opened"] == %{
               1 => %{rename: %{reason: :why, remark: :note}, default: [:priority]},
               2 => %{rename: %{why: :demand_reason}, default: []}
             }

      assert steps["upcast_rig.demands.fee_charged"] == %{1 => :function}
    end

    test "refuses a version newer than the declaration" do
      assert {:error, [problem]} = SchemaLock.merge(lock(fields(), 2), lock(fields(), 1))
      assert problem =~ "the lock records schema_version 2, and its contract declares 1"
    end

    test "refuses an event no contract declares any more, until it is forgotten" do
      gone = %{"shop.orders.order_lost" => %{1 => [order_id: [type: :id]], 2 => []}}
      kept = Map.merge(gone, lock(fields()))

      assert {:error, [problem]} = SchemaLock.merge(kept, lock(fields()))

      assert problem =~
               "shop.orders.order_lost: the lock records it at schema_version 1, 2, and no " <>
                 "contract of the applications read (`applications:`, less `exclude:`) declares it"

      forgotten = SchemaLock.forget(kept, "shop.orders.order_lost")
      assert SchemaLock.merge(forgotten, lock(fields())) == {:ok, lock(fields())}
    end

    test "forgets an event's versions from the one given up, and keeps those below" do
      kept = %{@type_name => %{1 => [a: [type: :id]], 2 => [b: [type: :id]], 3 => []}}

      assert SchemaLock.forget(kept, @type_name, 2) == %{@type_name => %{1 => [a: [type: :id]]}}
      assert SchemaLock.forget(kept, @type_name, 1) == %{}
    end
  end

  describe "the file" do
    test "reads back what it writes, one field a line" do
      text = SchemaLock.encode(lock(fields()))

      assert text =~ ~r/^      customer_id: \[type: :id, subject: :customer\],$/m
      assert SchemaLock.decode(text) == {:ok, lock(fields())}
      assert SchemaLock.decode(SchemaLock.encode(%{})) == {:ok, %{}}
    end

    test "refuses a key or a field given twice, and text that is not UTF-8" do
      for twice <- [
            ~s|%{"a" => %{1 => []}, "a" => %{2 => []}}|,
            ~s|%{"a" => %{1 => [], 1 => []}}|
          ] do
        assert SchemaLock.decode(twice) == {:error, "a map in it gives a key twice"}
      end

      assert {:error, "it is not a map of event types to versions"} =
               SchemaLock.decode(~s|%{"a" => %{1 => [x: [type: :id], x: [type: :string]]}}|)

      assert SchemaLock.decode("# caf" <> <<0xE9>> <> "\n%{}") == {:error, "it is not UTF-8 text"}
    end

    test "refuses a lock whose fields are not as it writes them, at any depth" do
      for type <- [
            "{:fields, :x}",
            "{:fields, [a: :nope]}",
            "{:fields, [a: [foo: 1]]}",
            "{:enum, :x}",
            "{:list, {:fields, [a: [type: :id, optional: nil]]}}",
            "nil"
          ] do
        assert SchemaLock.decode(~s|%{"a" => %{1 => [x: [type: #{type}]]}}|) ==
                 {:error, "it is not a map of event types to versions"}
      end

      for key <- ["optional: nil", ~s|optional: "yes"|, "personal: nil", "label: :x"] do
        assert SchemaLock.decode(~s|%{"a" => %{1 => [x: [type: :id, #{key}]]}}|) ==
                 {:error, "it is not a map of event types to versions"}
      end
    end

    test "reads fields and their keys in any order as written in order" do
      shuffled = ~s"""
      %{"#{@type_name}" => %{1 => [
        total: [type: {:fields, [currency: [type: {:enum, [:pln, :eur]}], amount: [type: :decimal]]}],
        order_id: [type: :id],
        note: [personal: :customer_id, optional: true, type: :string],
        customer_id: [subject: :customer, type: :id],
        channel: [type: {:enum, [:shop, :web]}]
      ]}}
      """

      assert SchemaLock.decode(shuffled) == {:ok, lock(fields())}
    end

    test "refuses what is not a literal, and never runs it" do
      code = ~s|%{"a" => %{1 => [x: [type: send(self(), :ran)]]}}|

      assert {:error, "it is not an Elixir literal"} = SchemaLock.decode(code)
      refute_received :ran

      # A struct is a literal to `Macro.quoted_literal?/1`, and evaluating one calls its
      # module, one that does not exist included.
      for struct <- ["%URI{}", "%NoSuchModule{}", ~s|%{"a" => %{1 => [x: [type: %URI{}]]}}|] do
        assert {:error, "it is not an Elixir literal"} = SchemaLock.decode(struct)
      end

      assert {:error, "it is not a map of event types to versions"} =
               SchemaLock.decode(~s|%{__struct__: :"Elixir.URI"}|)

      assert {:error, "it is not a map of event types to versions"} =
               SchemaLock.decode(~s|%{"a" => %{__struct__: :"Elixir.URI"}}|)

      assert {:error, "line 1: " <> _} = SchemaLock.decode("%{")
      assert {:error, "it is not a map of event types to versions"} = SchemaLock.decode("[1]")

      assert {:error, "it is not a map of event types to versions"} =
               SchemaLock.decode(~s|%{"a" => %{0 => []}}|)
    end
  end

  describe "the task" do
    setup do
      dir = Path.join(System.tmp_dir!(), "schema_lock_#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)
      %{path: Path.join(dir, "eh_os_contract.lock")}
    end

    test "--check fails on a missing file, and on a missing version", %{path: path} do
      assert_raise Mix.Error, ~r/does not exist/, fn ->
        Schema.lock(path, lock(fields()), check: true)
      end

      assert Schema.lock(path, lock(fields()), []) =~ "recorded #{@type_name} at 1"
      assert Schema.lock(path, lock(fields()), check: true) =~ "holds every event's fields"

      raised = lock(fields() ++ [field(:courier, :string)], 2)

      assert_raise Mix.Error, ~r/does not record #{@type_name} at 2/, fn ->
        Schema.lock(path, raised, check: true)
      end
    end

    test "refuses a changed version and writes nothing", %{path: path} do
      Schema.lock(path, lock(fields()), [])
      before = File.read!(path)
      changed = lock(fields() ++ [field(:courier, :string)])

      for opts <- [[], [check: true]] do
        assert_raise Mix.Error, ~r/courier was added/, fn -> Schema.lock(path, changed, opts) end
      end

      assert File.read!(path) == before
    end

    test "--forget records the event again, and drops one no contract declares", %{path: path} do
      gone = %{"shop.orders.order_lost" => %{1 => [order_id: [type: :id]]}}
      File.write!(path, SchemaLock.encode(Map.merge(gone, lock(fields()))))
      changed = lock(fields() ++ [field(:courier, :string)])

      assert_raise Mix.Error, ~r/no contract of the applications read/, fn ->
        Schema.lock(path, lock(fields()), [])
      end

      said =
        Schema.lock(path, changed,
          forget: @type_name,
          forget: "shop.orders.order_lost",
          forget: "shop.orders.order_lost"
        )

      assert said =~ "recorded #{@type_name} at 1; forgot shop.orders.order_lost at 1"
      assert SchemaLock.decode(File.read!(path)) == {:ok, changed}

      assert_raise Mix.Error, ~r/--forget shop.orders.nothing/, fn ->
        Schema.lock(path, changed, forget: "shop.orders.nothing")
      end
    end

    test "--forget keeps the versions below the declared one", %{path: path} do
      Schema.lock(path, lock(fields()), [])
      Schema.lock(path, lock(fields() ++ [field(:courier, :string)], 2), [])
      edited = lock(fields() ++ [field(:courier, :string, optional: true)], 2)

      assert Schema.lock(path, edited, forget: @type_name) =~ "recorded #{@type_name} at 2"

      assert {:ok, %{@type_name => %{1 => one, 2 => two}}} = SchemaLock.decode(File.read!(path))
      assert one == lock(fields())[@type_name][1]
      assert two == edited[@type_name][2]
    end

    test "says it wrote a lock with no event in it", %{path: path} do
      assert Schema.lock(path, %{}, []) =~ "no contract declares an event"
      assert SchemaLock.decode(File.read!(path)) == {:ok, %{}}
    end

    test "leaves the old file, and no temporary one, when it cannot write", %{path: path} do
      Schema.lock(path, lock(fields()), [])
      before = File.read!(path)
      dir = Path.dirname(path)
      File.chmod!(dir, 0o500)
      on_exit(fn -> File.chmod(dir, 0o700) end)

      assert_raise Mix.Error, ~r/cannot be written/, fn ->
        Schema.lock(path, lock(fields(), 2), [])
      end

      assert File.read!(path) == before
      refute File.exists?(path <> ".tmp")
    end

    test "refuses a file it cannot read", %{path: path} do
      File.write!(path, "<<<<<<< HEAD\n%{}\n")

      assert_raise Mix.Error, ~r/cannot be read: line 1/, fn ->
        Schema.lock(path, lock(fields()), [])
      end
    end
  end
end

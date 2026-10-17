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

    test "a reference is an :id, a list what it holds, a value its inner type" do
      fields = [field(:visit, {:id, :visit}), field(:counts, {:list, :count})]

      assert SchemaLock.fields(fields, values()) == [
               counts: [type: {:list, :integer}],
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

      assert SchemaLock.merge(other, lock(fields())) == {:ok, Map.merge(other, lock(fields()))}
      assert SchemaLock.merge(lock(fields()), lock(fields())) == {:ok, lock(fields())}
    end

    test "refuses each change to a recorded version, naming the field" do
      changes = [
        {fields() ++ [field(:courier, :string)], "courier was added, [type: :string]"},
        {replace(fields(), :order_id, nil) |> Enum.reject(&is_nil/1), "order_id was removed"},
        {replace(fields(), :channel, field(:channel, {:enum, [:web]})),
         "channel was [type: {:enum, [:shop, :web]}] and is [type: {:enum, [:web]}]"},
        {replace(fields(), :note, field(:note, :string, optional: true)),
         "note was [type: :string, optional: true, personal: :customer_id] and is"},
        {replace(fields(), :order_id, field(:order_id, :id, optional: true)), "order_id was"}
      ]

      for {fields, said} <- changes do
        assert {:error, [problem]} = SchemaLock.merge(lock(fields()), lock(fields))
        assert problem =~ "#{@type_name} at schema_version 1: #{said}"
        assert problem =~ "upcast from: 1"
        assert problem =~ "--forget #{@type_name}"
      end
    end

    test "refuses a domain value given another field, in every event that holds it" do
      values = values()
      values = update_in(values.money.fields, &(&1 ++ [field(:rate, :decimal, optional: true)]))

      assert {:error, [problem]} = SchemaLock.merge(lock(fields()), lock(fields(), 1, values))
      assert problem =~ "total was [type: {:fields"
    end

    test "records a changed version beside the old one once it is raised" do
      raised = lock(fields() ++ [field(:courier, :string)], 2)

      assert {:ok, %{@type_name => versions}} = SchemaLock.merge(lock(fields()), raised)
      assert Map.keys(versions) == [1, 2]
      assert versions[1] == lock(fields())[@type_name][1]
    end

    test "refuses a version newer than the declaration" do
      assert {:error, [problem]} = SchemaLock.merge(lock(fields(), 2), lock(fields(), 1))
      assert problem =~ "the lock records schema_version 2, and its contract declares 1"
    end

    test "keeps an event no contract declares any more until it is forgotten" do
      gone = %{"shop.orders.order_lost" => %{1 => [order_id: [type: :id]]}}

      assert {:ok, merged} = SchemaLock.merge(Map.merge(gone, lock(fields())), lock(fields()))
      assert Map.has_key?(merged, "shop.orders.order_lost")

      refute merged
             |> SchemaLock.forget("shop.orders.order_lost")
             |> Map.has_key?("shop.orders.order_lost")
    end
  end

  describe "the file" do
    test "reads back what it writes, one field a line" do
      text = SchemaLock.encode(lock(fields()))

      assert text =~ ~r/^      customer_id: \[type: :id, subject: :customer\],$/m
      assert SchemaLock.decode(text) == {:ok, lock(fields())}
      assert SchemaLock.decode(SchemaLock.encode(%{})) == {:ok, %{}}
    end

    test "refuses what is not a literal, and never runs it" do
      code = ~s|%{"a" => %{1 => [x: [type: send(self(), :ran)]]}}|

      assert {:error, "it is not an Elixir literal"} = SchemaLock.decode(code)
      refute_received :ran
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

      assert_raise Mix.Error, ~r/lacks #{@type_name} at 2/, fn ->
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

      said = Schema.lock(path, changed, forget: @type_name, forget: "shop.orders.order_lost")

      assert said =~ "recorded #{@type_name} at 1; forgot shop.orders.order_lost at 1"
      assert SchemaLock.decode(File.read!(path)) == {:ok, changed}

      assert_raise Mix.Error, ~r/--forget shop.orders.nothing/, fn ->
        Schema.lock(path, changed, forget: "shop.orders.nothing")
      end
    end

    test "refuses a file it cannot read", %{path: path} do
      File.write!(path, "<<<<<<< HEAD\n%{}\n")

      assert_raise Mix.Error, ~r/cannot be read: line 1/, fn ->
        Schema.lock(path, lock(fields()), [])
      end
    end
  end
end

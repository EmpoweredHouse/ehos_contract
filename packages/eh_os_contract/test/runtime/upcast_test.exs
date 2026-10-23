defmodule EhOsContract.UpcastTest do
  @moduledoc """
  Plan DD, V1 (#333): a row written with an older version of its event's fields is read
  in the current one, through the event's steps, and the log keeps the row as it was.
  `UpcastRig.Demands` declares `:demand_opened` at version 3; its rows here are appended
  as the code of versions 1 and 2 wrote them, a personal note sealed under the name it
  had then.
  """

  use EhOsContract.DataCase, async: false

  alias EhOsContract.{
    Actor,
    Bus,
    Codec,
    Consumer,
    Erased,
    Event,
    Implementations,
    Model,
    Personal,
    Store,
    Subscription,
    Upcast
  }

  alias UpcastRig.Demands
  alias UpcastRig.Demands.Events.DemandOpened

  @officer Actor.credential("u-officer", [])

  defp type(event),
    do: Enum.find(Model.fetch(Demands).events, &(&1.name == event)).type

  # A row of `event`, of the unit `unit`, as the code of `version` appended it: `fields`
  # its fields then, `data` its values, a personal field sealed under the name it had.
  defp written!(version, fields, data, {event, unit} \\ {:demand_opened, :demand}) do
    demand = "#{unit}-#{System.unique_integer([:positive])}"

    Repo.transaction(fn ->
      prepared = Personal.prepare(Repo, [{:requester, data.requester_id}])
      {:ok, keys} = Personal.for_writing(Repo, prepared)

      payload =
        Codec.encode(
          fields,
          Map.put(data, :"#{unit}_id", demand),
          %{},
          Personal.sealer(keys, type(event))
        )

      entry = %{
        type: type(event),
        schema_version: version,
        contract: Model.fetch(Demands).id,
        contract_version: Model.fetch(Demands).version,
        correlation_id: Ecto.UUID.generate(),
        actor: "older-code",
        occurred_at: DateTime.utc_now(),
        payload: payload
      }

      {:ok, [row]} = Store.append(Repo, [entry], {:stream, "#{unit}:#{demand}", 0})
      row
    end)
    |> elem(1)
  end

  defp field(name, opts \\ []),
    do:
      Map.merge(
        %{name: name, type: :string, optional: false, personal: nil, subject: nil},
        Map.new(opts)
      )

  # The fields as version 1 declared them.
  defp version_1 do
    [
      field(:demand_id, type: :id),
      field(:requester_id, type: :id, subject: :requester),
      field(:remark, personal: :requester_id, optional: true),
      field(:reason)
    ]
  end

  describe "reading an older row" do
    test "a row of version 1 goes through both steps: renamed twice, the priority given, the note opened" do
      row =
        written!(1, version_1(), %{
          requester_id: "r-anna",
          remark: "urgent",
          reason: "a new laptop"
        })

      # The log keeps the row as it was written.
      stored = Repo.get!(Event, row.id)
      assert stored.schema_version == 1
      assert Map.has_key?(stored.payload, "reason")
      assert %{"$eh" => "enc1"} = stored.payload["remark"]

      assert %DemandOpened{
               requester_id: "r-anna",
               note: "urgent",
               demand_reason: "a new laptop",
               priority: "normal"
             } = Consumer.decode!(stored)
    end

    test "a row of version 2 goes through the last step alone, and keeps the priority it holds" do
      fields = [
        field(:demand_id, type: :id),
        field(:requester_id, type: :id, subject: :requester),
        field(:note, personal: :requester_id, optional: true),
        field(:why),
        field(:priority)
      ]

      row =
        written!(2, fields, %{
          requester_id: "r-anna",
          note: "n",
          why: "a monitor",
          priority: "high"
        })

      assert %DemandOpened{note: "n", demand_reason: "a monitor", priority: "high"} =
               Consumer.decode!(row)
    end

    test "a renamed personal field of an erased requester reads as erased" do
      row =
        written!(1, version_1(), %{requester_id: "r-bartek", remark: "private", reason: "a mouse"})

      assert {:ok, :erased} = EhOsContract.erase(:requester, "r-bartek", actor: @officer)

      assert %DemandOpened{
               note: %Erased{subject: :requester, id: "r-bartek"},
               demand_reason: "a mouse"
             } =
               Consumer.decode!(Repo.get!(Event, row.id))
    end

    test "control: without the step's paths, the renamed seal does not open" do
      row = written!(1, version_1(), %{requester_id: "r-anna", remark: "urgent", reason: "x"})
      declaration = Enum.find(Model.fetch(Demands).events, &(&1.name == :demand_opened))
      {payload, paths} = Upcast.read(declaration, row)

      # Two renames compose: version 1's `reason` became `why`, and then `demand_reason`.
      assert paths == %{"note" => "remark", "demand_reason" => "reason"}
      keys = Personal.for_reading(Repo, [{:requester, "r-anna"}])

      fields =
        Enum.map(
          declaration.fields,
          &Map.take(&1, [:name, :type, :optional, :personal, :subject])
        )

      assert {:error, [note: :type]} =
               Codec.decode(fields, payload, %{}, open: Personal.opener(keys, row.type))

      assert {:ok, %{note: "urgent"}} =
               Codec.decode(fields, payload, %{},
                 open: Upcast.opener(Personal.opener(keys, row.type), paths)
               )
    end
  end

  # Plan DD, V2 (#338): a step by a function of the unit's code.
  describe "a step by a function" do
    defp fee!(data) do
      fields = [
        field(:fee_id, type: :id),
        field(:requester_id, type: :id, subject: :requester),
        field(:note, personal: :requester_id, optional: true),
        field(:amount_minor, type: :integer),
        field(:do, optional: true)
      ]

      written!(1, fields, Map.put(data, :requester_id, "r-anna"), {:fee_charged, :fee})
    end

    test "a row of version 1 reads through the implementation's function, its seal kept" do
      row = fee!(%{amount_minor: 12_050, note: "by card"})

      assert %UpcastRig.Demands.Events.FeeCharged{amount: amount, note: "by card"} =
               Consumer.decode!(row)

      assert Decimal.equal?(amount, Decimal.new("120.50"))
      assert Repo.get!(Event, row.id).payload["amount_minor"] == 12_050
    end

    test "a function moving a seal to another field is refused, naming no value" do
      row = fee!(%{amount_minor: 100, note: "secret", do: "move_seal"})
      error = assert_raise ArgumentError, fn -> Consumer.decode!(row) end

      assert Exception.message(error) =~ "the function puts a sealed value at remark"
      refute Exception.message(error) =~ "secret"
    end

    test "a function changing a field the log tags rows with is refused" do
      row = fee!(%{amount_minor: 100, do: "change_tag"})
      error = assert_raise ArgumentError, fn -> Consumer.decode!(row) end

      assert Exception.message(error) =~
               "the function leaves requester_id other than the row was written with"
    end

    test "what the function gives is read as the log stores it: a decimal, a date, an atom key" do
      row = fee!(%{amount_minor: 990, do: "stored_form"})

      assert %UpcastRig.Demands.Events.FeeCharged{amount: amount} = Consumer.decode!(row)
      assert Decimal.equal?(amount, Decimal.new("9.90"))
    end

    test "a field given under an atom and under its name, a clear personal value, a bare struct" do
      for {mode, refusal} <- [
            {"collide", "gave a field under an atom and under its name"},
            {"clear", "the function writes note, a personal field, in the clear"},
            {"struct", "amount_from_minor/1 gave no map"}
          ] do
        row = fee!(%{amount_minor: 100, do: mode})
        error = assert_raise ArgumentError, fn -> Consumer.decode!(row) end
        assert Exception.message(error) =~ refusal
        refute Exception.message(error) =~ "written in the clear"
      end
    end

    test "a function that throws or exits is refused, naming the step and no value" do
      for mode <- ["throw", "exit"] do
        row = fee!(%{amount_minor: 100, note: "secret", do: mode})
        error = assert_raise ArgumentError, fn -> Consumer.decode!(row) end

        assert Exception.message(error) =~
                 "amount_from_minor/1 #{if mode == "throw", do: "threw", else: "exited"}"

        refute Exception.message(error) =~ "secret"
      end
    end

    test "a function that raises, or gives no map, is refused, naming the step and no value" do
      raised = fee!(%{amount_minor: 100, do: "raise"})
      error = assert_raise ArgumentError, fn -> Consumer.decode!(raised) end

      assert Exception.message(error) =~
               "(upcast_rig.demands.fee_charged), `upcast from: 1`: UpcastRig.Fees.amount_from_minor/1 raised KeyError"

      no_map = fee!(%{amount_minor: 100, do: "no_map"})
      error = assert_raise ArgumentError, fn -> Consumer.decode!(no_map) end
      assert Exception.message(error) =~ "amount_from_minor/1 gave no map"
    end
  end

  describe "Upcast.read/2" do
    defp read(steps, version, payload),
      do:
        Upcast.read(%{schema_version: 3, upcasts: steps}, %{
          schema_version: version,
          payload: payload
        })

    test "the renames of one step happen at once, so two fields may swap names" do
      step = %{from: 2, rename: %{a: :b, b: :a}, default: %{}}

      assert read([step], 2, %{"a" => 1, "b" => 2}) ==
               {%{"a" => 2, "b" => 1}, %{"a" => "b", "b" => "a"}}
    end

    test "a default fills only what the row lacks" do
      step = %{from: 2, rename: %{}, default: %{priority: "normal"}}

      assert read([step], 2, %{"priority" => "high"}) == {%{"priority" => "high"}, %{}}
      assert read([step], 2, %{}) == {%{"priority" => "normal"}, %{}}
    end

    test "a row at the current version goes through no step" do
      step = %{from: 2, rename: %{a: :b}, default: %{c: 1}}

      assert read([step], 3, %{"a" => 1}) == {%{"a" => 1}, %{}}
    end

    test "a field nested in a renamed one opens below its old name" do
      open = fn path, _subject, _sealed -> {:ok, path} end
      opener = Upcast.opener(open, %{"contacts" => "phones"})

      assert opener.("contacts.0.phone", :s, :x) == {:ok, "phones.0.phone"}
      assert opener.("note", :s, :x) == {:ok, "note"}
    end
  end

  describe "a relay" do
    defmodule TakingBus do
      @moduledoc false
      @behaviour EhOsContract.Bus

      @impl true
      def publish(opts, messages) do
        send(Keyword.fetch!(opts, :to), {:published, messages})
        :ok
      end

      @impl true
      def consumer(_opts, _consumer), do: raise("not consumed from")
    end

    setup do
      previous = Application.get_env(:eh_os_contract, :bus)
      Application.put_env(:eh_os_contract, :bus, {TakingBus, to: self()})

      on_exit(fn ->
        if previous,
          do: Application.put_env(:eh_os_contract, :bus, previous),
          else: Application.delete_env(:eh_os_contract, :bus)
      end)
    end

    test "publishes an older row with the current fields" do
      relay = "upcast_rig.demands:relay:demand_opened"
      Subscription.register!(Repo, [Implementations.consumer(relay)])

      row =
        written!(1, version_1(), %{requester_id: "r-anna", remark: "urgent", reason: "a laptop"})

      assert {:applied, 1} = Subscription.step(Repo, Implementations.consumer(relay))
      assert_received {:published, [%Bus.Message{payload: payload}]}

      assert payload == %{
               "demand_id" => row.payload["demand_id"],
               "demand_reason" => "a laptop",
               "priority" => "normal"
             }
    end
  end
end

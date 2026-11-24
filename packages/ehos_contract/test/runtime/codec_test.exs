defmodule EhosContract.CodecTest do
  @moduledoc """
  Field values against declared types, and their round trip through the log's form
  (v2 §5: what stays at run time).
  """

  use ExUnit.Case, async: true

  alias EhosContract.{Codec, Key}

  @values %{
    money: %{name: :money, type: :integer, fields: []},
    method: %{name: :method, type: {:enum, [card: "Card", cash: "Cash"]}, fields: []},
    address: %{
      name: :address,
      type: nil,
      fields: [
        %{name: :city, type: :string, optional: false},
        %{name: :zip, type: :string, optional: true}
      ]
    }
  }

  @fields [
    %{name: :visit_id, type: :id, optional: false},
    %{name: :amount, type: :money, optional: false},
    %{name: :method, type: :method, optional: false},
    %{name: :rate, type: :decimal, optional: true},
    %{name: :on, type: :date, optional: true},
    %{name: :at, type: :timestamp, optional: true},
    %{name: :codes, type: {:list, {:enum, [:a, :b]}}, optional: true},
    %{name: :address, type: :address, optional: true},
    %{name: :note, type: :string, optional: true}
  ]

  @full %{
    visit_id: "w-1",
    amount: 20_000,
    method: :card,
    rate: Decimal.new("0.23"),
    on: ~D[2026-09-01],
    at: ~U[2026-09-01 09:00:00.000000Z],
    codes: [:a, :b],
    address: %{city: "Zürich", zip: nil},
    note: nil
  }

  test "values of their types have no problems, and a missing optional field is fine" do
    assert Codec.problems(@fields, @full, @values) == []
    assert Codec.problems(@fields, %{visit_id: "w-1", amount: 1, method: :cash}, @values) == []
  end

  test "a missing required field and a value of another type are named, never their values" do
    problems =
      Codec.problems(
        @fields,
        %{
          @full
          | visit_id: nil,
            amount: 1.5,
            method: :voucher,
            codes: [:c],
            address: %{zip: "1"}
        },
        @values
      )

    assert problems == [
             visit_id: :required,
             amount: :type,
             method: :type,
             codes: :type,
             address: :type
           ]
  end

  test "a timestamp outside UTC and a float for a decimal do not fit" do
    at =
      DateTime.from_naive!(~N[2026-09-01 09:00:00], "Etc/UTC")
      |> Map.put(:time_zone, "Europe/Warsaw")

    assert {:at, :type} in Codec.problems(@fields, %{@full | at: at}, @values)
    assert {:rate, :type} in Codec.problems(@fields, %{@full | rate: 0.23}, @values)
  end

  test "the log's form is JSON's, and it decodes back to the same values" do
    encoded = Codec.encode(@fields, @full, @values)

    assert encoded == %{
             "visit_id" => "w-1",
             "amount" => 20_000,
             "method" => "card",
             "rate" => "0.23",
             "on" => "2026-09-01",
             "at" => "2026-09-01T09:00:00.000000Z",
             "codes" => ["a", "b"],
             "address" => %{"city" => "Zürich", "zip" => nil},
             "note" => nil
           }

    # Through JSON, as the payload column stores it.
    assert Codec.decode(@fields, encoded |> Jason.encode!() |> Jason.decode!(), @values) ==
             {:ok, @full}
  end

  test "decoding refuses what does not fit, and never creates an atom" do
    name = "not_a_member_#{System.unique_integer([:positive])}"

    assert Codec.decode(
             @fields,
             %{"visit_id" => "w-1", "amount" => "1", "method" => name},
             @values
           ) ==
             {:error, [amount: :type, method: :type]}

    assert_raise ArgumentError, fn -> String.to_existing_atom(name) end

    assert Codec.decode(@fields, %{"amount" => 1, "method" => "cash"}, @values) ==
             {:error, [visit_id: :required]}
  end

  test "query strings convert values recursively inside lists and structured values" do
    values =
      Map.put(@values, :window, %{
        name: :window,
        type: nil,
        fields: [%{name: :count, type: :integer, optional: false}]
      })

    fields = [
      %{name: :counts, type: {:list, :integer}, optional: false},
      %{name: :window, type: :window, optional: false}
    ]

    assert Codec.decode(
             fields,
             %{"counts" => ["1", "2"], "window" => %{"count" => "3"}},
             values,
             strings: true
           ) == {:ok, %{counts: [1, 2], window: %{count: 3}}}
  end

  describe "what a form sends (form: true)" do
    @task %{
      name: :task,
      type: nil,
      fields: [
        %{name: :title, type: :string, optional: false},
        %{name: :days, type: :integer, optional: true}
      ]
    }

    @form_fields [
      %{name: :visit_id, type: :id, optional: false},
      %{name: :amount, type: :money, optional: false},
      %{name: :method, type: :method, optional: false},
      %{name: :paid, type: :boolean, optional: true},
      %{name: :note, type: :string, optional: true},
      %{name: :tasks, type: {:list, :task}, optional: true}
    ]

    defp form(params),
      do: Codec.decode(@form_fields, params, Map.put(@values, :task, @task), form: true)

    @sent %{
      "visit_id" => "w-1",
      "amount" => "20000",
      "method" => "cash",
      "paid" => "false",
      "note" => ""
    }

    test "reads every value as the text a form sends, and a blank field as absent" do
      assert form(@sent) ==
               {:ok,
                %{
                  visit_id: "w-1",
                  amount: 20_000,
                  method: :cash,
                  paid: false,
                  note: nil,
                  tasks: nil
                }}

      assert form(%{@sent | "visit_id" => "  ", "amount" => ""}) ==
               {:error, [visit_id: :required, amount: :required]}

      assert form(%{@sent | "amount" => "twenty"}) == {:error, [amount: :type]}
      assert form(%{@sent | "method" => "cheque"}) == {:error, [method: :type]}
    end

    test "reads inputs_for's rows in the order of their indices, blanks inside them absent" do
      tasks = %{
        "10" => %{"title" => "Payroll", "days" => "", "_persistent_id" => "10"},
        "2" => %{"title" => "VAT", "days" => "5", "_persistent_id" => "2"}
      }

      assert {:ok, %{tasks: [%{title: "VAT", days: 5}, %{title: "Payroll", days: nil}]}} =
               form(Map.put(@sent, "tasks", tasks))

      assert form(Map.put(@sent, "tasks", %{"0" => %{"title" => " ", "days" => "1"}})) ==
               {:error, [tasks: :type]}

      assert form(Map.put(@sent, "tasks", %{"first" => %{"title" => "VAT"}})) ==
               {:error, [tasks: :type]}

      assert {:ok, %{tasks: []}} = form(Map.put(@sent, "tasks", %{}))
    end

    test "leaves text too long for an integer unparsed, and a row index past nine digits" do
      digits = String.duplicate("9", 2_000_000)

      assert form(%{@sent | "amount" => digits}) == {:error, [amount: :type]}

      assert Codec.decode([%{name: :n, type: :integer}], %{"n" => digits}, @values, strings: true) ==
               {:error, [n: :type]}

      assert form(Map.put(@sent, "tasks", %{digits => %{"title" => "VAT"}})) ==
               {:error, [tasks: :type]}

      assert form(Map.put(@sent, "tasks", %{"1" => %{"title" => "A"}, "01" => %{"title" => "B"}})) ==
               {:error, [tasks: :type]}
    end

    test "drops a list's blank items, as a checkbox group sends to say nothing was chosen" do
      fields = [%{name: :codes, type: {:list, {:enum, [:a, :b]}}, optional: true}]

      assert Codec.decode(fields, %{"codes" => [""]}, @values, form: true) == {:ok, %{codes: []}}

      assert Codec.decode(fields, %{"codes" => ["", "a", " "]}, @values, form: true) ==
               {:ok, %{codes: [:a]}}
    end

    test "trims the spaces around a value that is not text, and keeps text as typed" do
      assert {:ok, %{visit_id: "w-1", amount: 42, method: :cash, note: " a note "}} =
               form(%{
                 @sent
                 | "visit_id" => " w-1 ",
                   "amount" => " 42 ",
                   "method" => "cash ",
                   "note" => " a note "
               })
    end

    test "ignores the keys a form adds that the declaration does not name" do
      assert {:ok, %{note: nil}} =
               form(Map.merge(@sent, %{"_unused_note" => "", "_target" => "x"}))
    end

    test "leaves JSON's reading as it was: an empty string is a value there" do
      fields = [%{name: :note, type: :string, optional: false}]

      assert Codec.decode(fields, %{"note" => ""}, @values) == {:ok, %{note: ""}}

      assert Codec.decode(fields, %{"note" => ""}, @values, form: true) ==
               {:error, [note: :required]}
    end
  end

  test "a field typed with a value the domain does not declare fits nothing" do
    assert Codec.problems([%{name: :x, type: :unknown}], %{x: 1}, @values) == [x: :type]
  end

  describe "the edges of the round trip" do
    # What the payload types accept at their corners, and what the log's form does to
    # it — the edges v1's `payload_edges_test.exs` pinned, on the codec v2 reads and
    # writes through. Each failure here would be silent: a value that is merely
    # different when it comes back, in a field the engine never looks at.

    @edges [
      %{name: :amount, type: :integer, optional: true},
      %{name: :at, type: :timestamp, optional: true},
      %{name: :note, type: :string, optional: true}
    ]

    defp round_trip(data) do
      encoded = Codec.encode(@edges, data, %{}) |> Jason.encode!() |> Jason.decode!()
      {:ok, decoded} = Codec.decode(@edges, encoded, %{})
      decoded
    end

    test "negative, zero and the ends of 64 bits come back as they went" do
      # A correction or a reversal is counted negative, and zero is a value, not an
      # absence.
      for amount <- [-1, 0, -9_223_372_036_854_775_808, 9_223_372_036_854_775_807] do
        assert Codec.problems(@edges, %{amount: amount}, %{}) == []
        assert round_trip(%{amount: amount}).amount == amount
      end
    end

    # Until 3 October an integer far beyond 64 bits was let in: the column is JSON and the
    # BEAM has bignums. A host's read model holds a `bigint` at most, so the input is bounded
    # now; one already in the log still reads back.
    test "an integer beyond 64 bits does not fit, and one in the log still reads back" do
      huge = 12_345_678_901_234_567_890_123_456_789

      assert Codec.problems(@edges, %{amount: huge}, %{}) == [amount: :type]

      stored = Codec.encode(@edges, %{amount: huge}, %{})
      open = fn _path, _subject, value -> {:ok, value} end
      assert {:ok, %{amount: ^huge}} = Codec.decode(@edges, stored, %{}, open: open)
    end

    test "before 1970 and far into the future both survive" do
      # A date of birth and a statutory retention horizon, both on a process's first
      # day. Epoch arithmetic anywhere on the way would break the first and overflow
      # the second, and neither would raise.
      for at <- [~U[1969-07-20 20:17:00.000000Z], ~U[9999-12-31 23:59:59.000000Z]] do
        assert round_trip(%{at: at}).at == at
      end
    end

    test "microsecond precision is kept exactly as given, and so is its absence" do
      # `DateTime.compare/2` calls the last two the same instant and `==` does not; the
      # evaluator compares with `compare`, and this is what notices if a round trip
      # started turning one into the other.
      with_micro = ~U[2026-08-05 09:00:00.123456Z]
      without = ~U[2026-08-05 09:00:00Z]

      assert round_trip(%{at: with_micro}).at == with_micro
      assert round_trip(%{at: without}).at == without
      refute without == ~U[2026-08-05 09:00:00.000000Z]
    end

    test "whitespace, newlines and unicode in a string come back unchanged" do
      # The log is what a report quotes from. Text mangled on the way in cannot be
      # repaired later, and the damage shows only to somebody who reads the language.
      text = "  zażółć\ngęślą jaźń\t— ✓  "

      assert round_trip(%{note: text}).note == text
    end

    test "an empty :string is a value, and an empty :id is refused" do
      # Not an inconsistency, and the reason v1 gave: `:string` is text somebody typed,
      # and typing nothing is a fact worth keeping; `:id` names something, and an
      # identifier that identifies nothing is a missing value wearing a type. An empty
      # one would also key a stream, a tag and a run with nothing after the colon, one
      # for every command that forgot to fill it in.
      required = fn type -> [%{name: :f, type: type, optional: false}] end

      assert Codec.problems(required.(:string), %{f: ""}, %{}) == []
      assert Codec.problems(required.(:id), %{f: ""}, %{}) == [f: :type]

      # An entity's identifier is an `:id` too, wherever the model keeps its entity.
      assert Codec.problems(required.({:id, :invoice}), %{f: ""}, %{}) == [f: :type]

      # The control: a one-character id is an id.
      assert Codec.problems(required.(:id), %{f: "x"}, %{}) == []
      assert Codec.problems(required.({:id, :invoice}), %{f: "x"}, %{}) == []
    end
  end

  describe "Key" do
    test "streams, tags and joined keys escape the separator, so two keys never merge" do
      assert Key.stream(:visit_settlement, ["w-1"]) == "visit_settlement:w-1"
      assert Key.stream(:month, ["c-1", "2026-09"]) == "month:c-1|2026-09"
      assert Key.tag(:visit_id, "w|1") == "visit_id:w%7C1"
      refute Key.join(["a|b", "c"]) == Key.join(["a", "b|c"])
      assert Key.join(["100%", "|"]) == "100%25|%7C"
      assert_raise ArgumentError, fn -> Key.join(["a", nil]) end
    end

    test "unicode passes through untouched; only the separator and the escape are escaped" do
      assert Key.join(["episode", "żółw-✓"]) == "episode|żółw-✓"
    end
  end

  describe "personal fields (v2 §14)" do
    alias EhosContract.{Erased, Personal}

    @personal [
      %{name: :member_id, type: :id, optional: false, subject: :member},
      %{name: :name, type: :string, optional: false, personal: :member_id},
      %{name: :note, type: :string, optional: true}
    ]

    @key {"member", "member-anna"}
    @keys %{@key => {1, :binary.copy(<<7>>, 32)}}
    @read %{{"member", "member-anna", 1} => :binary.copy(<<7>>, 32)}

    defp sealed(type \\ "shredding_rig.joined") do
      Codec.encode(
        @personal,
        %{member_id: "member-anna", name: "Anna Nowak", note: "n"},
        %{},
        Personal.sealer(@keys, type)
      )
    end

    test "sealed with a key, opened with it" do
      stored = sealed()
      assert %{"$eh" => "enc1", "k" => 1} = stored["name"]
      assert stored["note"] == "n"

      assert Codec.subjects(@personal, stored, %{}, :stored) == [{:member, "member-anna"}]

      assert Codec.decode(@personal, stored, %{},
               open: Personal.opener(@read, "shredding_rig.joined")
             ) ==
               {:ok, %{member_id: "member-anna", name: "Anna Nowak", note: "n"}}
    end

    # Inside a ciphertext the log holds any bytes JSON writes, and a NUL was let in before text
    # had to be text: what is read back was written, so reading it back does not refuse it.
    test "a sealed value with a NUL, written before the rule, is read back" do
      stored =
        Codec.encode(
          @personal,
          %{member_id: "member-anna", name: "Anna" <> <<0>>},
          %{},
          Personal.sealer(@keys, "shredding_rig.joined")
        )

      assert {:ok, %{name: "Anna" <> <<0>>}} =
               Codec.decode(@personal, stored, %{},
                 open: Personal.opener(@read, "shredding_rig.joined")
               )

      # What comes from outside is held to it.
      assert Codec.decode(
               @personal,
               %{"member_id" => "member-anna", "name" => "Anna" <> <<0>>},
               %{}
             ) ==
               {:error, [name: :type]}

      # So is a field no seal held, read with `open:` all the same: only an opened value is let in.
      assert Codec.decode(
               @personal,
               %{"member_id" => "member-anna" <> <<0>>, "name" => nil},
               %{},
               open: Personal.opener(@read, "shredding_rig.joined")
             ) == {:error, [member_id: :type, name: :required]}
    end

    test "a ciphertext moved to another event type, field or subject does not open" do
      stored = sealed("shredding_rig.joined")
      open = Personal.opener(@read, "shredding_rig.renamed")
      assert Codec.decode(@personal, stored, %{}, open: open) == {:error, [name: :type]}

      moved = %{stored | "note" => stored["name"]}

      notes =
        Enum.map(
          @personal,
          &if(&1.name == :note, do: Map.put(&1, :personal, :member_id), else: &1)
        )

      open = Personal.opener(@read, "shredding_rig.joined")
      assert {:error, [note: :type]} = Codec.decode(notes, moved, %{}, open: open)

      bartek = Map.put(@read, {"member", "member-bartek", 1}, :binary.copy(<<7>>, 32))
      other = %{stored | "member_id" => "member-bartek"}

      assert Codec.decode(@personal, other, %{},
               open: Personal.opener(bartek, "shredding_rig.joined")
             ) ==
               {:error, [name: :type]}
    end

    test "without its key, an erased subject's field is Erased; without open:, it does not fit" do
      stored = sealed()
      erased = MapSet.new([{"member", "member-anna"}])

      assert Codec.decode(@personal, stored, %{},
               open: Personal.opener(%{}, "shredding_rig.joined", erased)
             ) ==
               {:ok,
                %{
                  member_id: "member-anna",
                  name: %Erased{subject: :member, id: "member-anna"},
                  note: "n"
                }}

      assert Codec.decode(@personal, stored, %{}) == {:error, [name: :type]}

      # Without its key and never erased: raised, never read as erased.
      assert_raise ArgumentError, ~r/is missing, and the subject was never erased/, fn ->
        Codec.decode(@personal, stored, %{}, open: Personal.opener(%{}, "shredding_rig.joined"))
      end
    end

    test "Erased fits a personal field and nothing else, and cannot be sealed" do
      erased = %Erased{subject: :member, id: "member-anna"}

      assert Codec.problems(@personal, %{member_id: "member-anna", name: erased}, %{}) == []

      assert Codec.problems(@personal, %{member_id: "member-anna", name: "A", note: erased}, %{}) ==
               [note: :type]

      assert_raise ArgumentError, ~r/field name holds EhosContract.Erased/, fn ->
        Codec.encode(
          @personal,
          %{member_id: "member-anna", name: erased},
          %{},
          Personal.sealer(@keys, "t")
        )
      end
    end

    test "clear text where a seal belongs, and a seal with nothing to open it, do not fit" do
      open = Personal.opener(@read, "shredding_rig.joined")
      clear = %{"member_id" => "member-anna", "name" => "Anna Nowak", "note" => nil}
      assert Codec.decode(@personal, clear, %{}, open: open) == {:error, [name: :type]}

      # Control: an optional personal field left empty is empty, not clear text.
      optional = Enum.map(@personal, &if(&1.name == :name, do: %{&1 | optional: true}, else: &1))

      assert {:ok, %{name: nil}} =
               Codec.decode(optional, %{clear | "name" => nil}, %{}, open: open)

      # A domain value whose fields are all optional would take the envelope's keys
      # for none of its own and decode empty.
      values = %{
        info: %{name: :info, type: nil, fields: [%{name: :phone, type: :string, optional: true}]}
      }

      fields = [
        %{name: :member_id, type: :id, optional: false, subject: :member},
        %{name: :info, type: :info, optional: false, personal: :member_id}
      ]

      stored =
        Codec.encode(
          fields,
          %{member_id: "member-anna", info: %{phone: "+48 600 100 200"}},
          values,
          Personal.sealer(@keys, "t")
        )

      assert Codec.decode(fields, stored, values) == {:error, [info: :type]}

      assert Codec.decode(fields, stored, values, open: Personal.opener(@read, "t")) ==
               {:ok, %{member_id: "member-anna", info: %{phone: "+48 600 100 200"}}}
    end

    test "a seal that fails names the field, never a key or the value" do
      [{_, {_, key}}] = Map.to_list(@keys)

      missing =
        assert_raise ArgumentError, fn ->
          Codec.encode(
            @personal,
            %{member_id: "member-bartek", name: "Bartek Nowak"},
            %{},
            Personal.sealer(@keys, "t")
          )
        end

      assert missing.message =~ "field name is personal to subject member \"member-bartek\""
      refute missing.message =~ inspect(key)
      refute missing.message =~ "Bartek Nowak"

      not_utf8 =
        assert_raise ArgumentError, fn ->
          Codec.encode(
            @personal,
            %{member_id: "member-anna", name: "Anna " <> <<0xFF>>},
            %{},
            Personal.sealer(@keys, "t")
          )
        end

      assert not_utf8.message =~ "field name holds a value that cannot be written as JSON"
      refute not_utf8.message =~ "Anna"
    end

    test "out of the log, Erased is written as nil" do
      erased = %Erased{subject: :member, id: "member-anna"}

      assert Codec.encode(@personal, %{member_id: "member-anna", name: erased}, %{}) ==
               %{"member_id" => "member-anna", "name" => nil, "note" => nil}
    end

    test "personal?/2 and subjects/4 look inside domain values, lists and aliases" do
      values = %{
        contact: %{
          name: :contact,
          type: nil,
          fields: [
            %{name: :member_id, type: :id, optional: false, subject: :member},
            %{name: :phone, type: :string, optional: false, personal: :member_id}
          ]
        },
        contact_ref: %{name: :contact_ref, type: :contact, fields: []}
      }

      fields = [
        %{name: :contacts, type: {:list, :contact_ref}, optional: false},
        %{name: :count, type: :integer, optional: false}
      ]

      assert Codec.personal?(fields, values)
      refute Codec.personal?([%{name: :count, type: :integer, optional: false}], values)

      data = %{
        contacts: [
          %{member_id: "member-anna", phone: "1"},
          %{member_id: "member-bartek", phone: "2"},
          %{member_id: "member-anna", phone: "3"}
        ],
        count: 3
      }

      assert Codec.subjects(fields, data, values, :value) ==
               [{:member, "member-anna"}, {:member, "member-bartek"}]

      # In the log's form only a sealed field needs a key.
      assert Codec.subjects(fields, Codec.encode(fields, data, values), values, :stored) == []
    end
  end
end

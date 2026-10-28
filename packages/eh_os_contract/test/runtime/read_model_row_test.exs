defmodule EhOsContract.ReadModelRowTest do
  @moduledoc """
  #472: **a read model's `Row` is an Ecto schema**, of its `table:` with its `key:` as
  the primary key, or embedded when it names no table. Its fields have the contract's
  types: an enum is an `Ecto.Enum`, a `:timestamp` keeps microseconds, a domain value
  is what the domain says it is, read when it is first used. A projection writes
  through it and a query reads it, with no field listed a second time.
  """

  use EhOsContract.DataCase, async: false

  import EhOsContract.DslCase, only: [compile: 2]

  @table "read_model_row_test_visits"

  setup_all do
    unless Code.ensure_loaded?(EhOsContract.Fixtures.RowClinic.Contract) do
      compile(
        """
        defmodule EhOsContract.Fixtures.RowClinic.Domain do
          use EhOsContract.Domain, name: :row_clinic, language: :en

          subdomain :core, "Core", type: :core
          context :visits, "Visits", subdomain: :core
          actor :reception, :human, "Reception"
          subject :member, "Member"

          value :money, :integer, unit: :cents
          value :method, {:enum, [card: "Card", cash: "Cash"]}
          value :room_id, :id

          value :contact do
            field :member_id, :id, subject: :member
            field :email, :string, personal: :member_id
          end

          value :remark do
            field :text, :string, optional: true
          end

          value :address do
            field :street, :string
            field :since, :date, optional: true
            field :method, :method, optional: true
          end
        end

        defmodule EhOsContract.Fixtures.RowClinic.Contract do
          use EhOsContract.Contract,
            domain: EhOsContract.Fixtures.RowClinic.Domain,
            context: :visits,
            id: "row_clinic.visits"

          aggregate :visit, "Visit" do
            identity :visit_id
            command :close_visit, "Closing a visit", by: :reception, emits: :visit_closed
            event :visit_closed, "Visit closed"
          end

          read_model :visits, "Visits", projects: :visit_closed,
            table: "#{@table}", key: [:visit_id, :room_id] do
            field :visit_id, :id
            field :room_id, :room_id
            field :status, {:enum, [:open, :closed]}
            field :paid, :money, optional: true
            field :method, :method, optional: true
            field :closed_at, :timestamp, optional: true
            field :tags, {:list, :string}, optional: true
            field :address, :address, optional: true
            field :stops, {:list, :address}, optional: true
            field :contact, :contact, optional: true
            field :remark, :remark, optional: true
            field :amounts, {:list, :money}, optional: true
          end

          read_model :visits_seen, "Visits seen", projects: :visit_closed do
            field :visit_id, :id
            field :address, :address, optional: true
            field :member_id, :id, subject: :member
            field :member_name, :string, personal: :member_id, optional: true
          end
        end
        """,
        "row_clinic.ex"
      )
    end

    :ok
  end

  # Compiled while the test runs, so named at run time: no struct literal, no remote
  # call the compiler would look for before the module exists.
  defp visits, do: Module.concat(EhOsContract.Fixtures.RowClinic.Contract.ReadModels.Visits, Row)

  # A value of the domain compiled while the test runs, as its struct.
  defp value(name, fields),
    do: struct!(Module.concat(EhOsContract.Fixtures.RowClinic.Domain.Values, name), fields)

  defp seen,
    do: Module.concat(EhOsContract.Fixtures.RowClinic.Contract.ReadModels.VisitsSeen, Row)

  setup do
    Repo.query!("""
    CREATE TABLE #{@table} (
      visit_id text, room_id text, status text, paid integer, method text,
      closed_at timestamp(6), tags text[], address jsonb, stops jsonb, contact jsonb, remark jsonb, amounts integer[],
      PRIMARY KEY (visit_id, room_id)
    )
    """)

    :ok
  end

  describe "a read model with a table" do
    test "is a schema of its table, keyed by its key, with the contract's types" do
      assert visits().__schema__(:source) == @table
      assert visits().__schema__(:primary_key) == [:visit_id, :room_id]

      assert visits().__schema__(:fields) ==
               [
                 :visit_id,
                 :room_id,
                 :status,
                 :paid,
                 :method,
                 :closed_at,
                 :tags,
                 :address,
                 :stops,
                 :contact,
                 :remark,
                 :amounts
               ]

      assert visits().__schema__(:type, :closed_at) == EhOsContract.EctoTypes.Timestamp
      assert visits().__schema__(:type, :tags) == {:array, :string}
      assert Ecto.Enum.values(visits(), :status) == [:open, :closed]

      # Read from the domain: a list of values made of fields is one jsonb column, a
      # list of values resting on a type an array of that type.
      assert Ecto.Type.type(visits().__schema__(:type, :stops)) == :map
      assert Ecto.Type.type(visits().__schema__(:type, :amounts)) == {:array, :integer}
    end

    test "writes and reads through its schema, a domain value read from the domain" do
      closed_at = ~U[2026-10-28 09:15:00.123456Z]

      Repo.insert_all(visits(), [
        %{
          visit_id: "v-1",
          room_id: "r-1",
          status: :closed,
          paid: 1500,
          method: :card,
          closed_at: closed_at,
          tags: ["late"]
        }
      ])

      # What the table stores: an enum's member and a domain enum's as their names.
      assert %{rows: [["closed", "card", 1500]]} =
               Repo.query!("SELECT status, method, paid FROM #{@table}")

      assert [row] = Repo.all(from(r in visits(), where: r.method == :card))

      assert row.__struct__ == visits()

      assert %{
               visit_id: "v-1",
               room_id: "r-1",
               status: :closed,
               paid: 1500,
               method: :card,
               closed_at: ^closed_at,
               tags: ["late"]
             } = row
    end

    # A scenario's given happens at a time to the second, as does an ISO 8601 string a
    # caller sends; Ecto's `:utc_datetime_usec` alone refuses to write one.
    test "writes a time to the second, as a scenario's given carries it, and reads it back" do
      Repo.insert_all(visits(), [
        %{visit_id: "v-1", room_id: "r-1", status: :open, closed_at: ~U[2026-01-01 09:00:00Z]}
      ])

      assert [%{closed_at: ~U[2026-01-01 09:00:00.000000Z]}] =
               Repo.all(from(r in visits(), where: r.closed_at >= ^~U[2026-01-01 09:00:00Z]))
    end

    # The map an event carries is written as it is, and read back the same: never a
    # struct, so a projection and a query see what an event's consumer sees.
    test "writes a value made of fields, and a list of them, in the log's form, and reads back the event's map" do
      address = value(Address, street: "Main", since: ~D[2026-01-31], method: :cash)
      stop = value(Address, street: "Side", since: nil, method: nil)

      Repo.insert_all(visits(), [
        %{visit_id: "v-1", room_id: "r-1", status: :open, address: address, stops: [stop]}
      ])

      assert %{rows: [[%{"street" => "Main", "since" => "2026-01-31", "method" => "cash"}]]} =
               Repo.query!("SELECT address FROM #{@table}")

      # A list of them is one column holding the list, as `embeds_many` keeps it.
      assert %{rows: [[[%{"street" => "Side", "since" => nil, "method" => nil}]]]} =
               Repo.query!("SELECT stops FROM #{@table}")

      assert [%{address: ^address, stops: [^stop]}] = Repo.all(visits())
    end

    # A rebuild replays an event after its subject was erased: the personal field reads
    # back as EhOsContract.Erased, is written as nil, and the row still loads.
    test "writes an erased personal field of a value as nil, and reads the row back" do
      erased = %EhOsContract.Erased{subject: :member, id: "m-1"}

      Repo.insert_all(visits(), [
        %{
          visit_id: "v-1",
          room_id: "r-1",
          status: :open,
          contact: value(Contact, member_id: "m-1", email: erased)
        }
      ])

      assert [%{contact: %{member_id: "m-1", email: nil}}] = Repo.all(visits())
    end

    test "redacts a personal field when a row is inspected" do
      # Inspect itself is not asked: a module compiled while the tests run comes after
      # protocols were consolidated, so its redacting Inspect has no effect here.
      assert seen().__schema__(:redact_fields) == [:member_name]
    end

    # A value whose fields are all optional is still decoded from the log's form: its
    # keys are the field names, never the strings the column holds.
    test "reads a value whose fields are all optional with its keys as atoms" do
      Repo.insert_all(visits(), [
        %{visit_id: "v-1", room_id: "r-1", status: :open, remark: value(Remark, text: "late")}
      ])

      assert [%{remark: %{text: "late"}}] = Repo.all(visits())
    end

    test "refuses to write a value made of fields that does not fit it" do
      assert_raise Ecto.ChangeError, fn ->
        Repo.insert_all(visits(), [
          %{visit_id: "v-1", room_id: "r-1", status: :open, address: %{street: 7}}
        ])
      end
    end

    test "dumps a domain value through the type the domain gives it, and refuses what does not fit" do
      assert {:ok, 1500} = Ecto.Type.dump(visits().__schema__(:type, :paid), 1500)
      assert :error = Ecto.Type.cast(visits().__schema__(:type, :paid), "a lot")
      assert {:ok, :cash} = Ecto.Type.cast(visits().__schema__(:type, :method), "cash")
      assert {:error, _} = Ecto.Type.cast(visits().__schema__(:type, :method), "cheque")
    end
  end

  test "a read model without a table is an embedded schema" do
    assert seen().__schema__(:source) == nil
    assert seen().__schema__(:primary_key) == []
    assert seen().__schema__(:fields) == [:visit_id, :address, :member_id, :member_name]
    refute Map.has_key?(struct(seen()), :__meta__)

    assert {:ok, %{street: "Main", since: ~D[2026-01-31], method: :card}} =
             Ecto.Type.cast(seen().__schema__(:type, :address), %{
               "street" => "Main",
               "since" => "2026-01-31",
               "method" => "card"
             })
  end
end

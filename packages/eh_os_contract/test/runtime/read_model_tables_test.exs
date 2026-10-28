defmodule EhOsContract.ReadModelTablesTest do
  @moduledoc """
  #493: **a read model's table, checked against its contract.**
  `EhOsContract.Testing.assert_read_model_tables/1` reads the table from the database
  and fails on what no row written through `Row` would fit: a missing table or
  column, a column of another type, a required field's column that takes `NULL`, a
  primary key that is not the key, a column of the projection's own that refuses a
  row. Each table here is created inside the test's transaction.
  """

  use EhOsContract.DataCase, async: false

  import EhOsContract.DslCase, only: [compile: 2]

  alias EhOsContract.Testing

  @table "table_check_visits"
  @contract EhOsContract.Fixtures.TableCheck.Contract

  setup_all do
    unless Code.ensure_loaded?(@contract) do
      compile(
        """
        defmodule EhOsContract.Fixtures.TableCheck.Domain do
          use EhOsContract.Domain, name: :table_check, language: :en

          subdomain :core, "Core", type: :core
          context :visits, "Visits", subdomain: :core
          actor :reception, :human, "Reception"
          subject :member, "Member"

          value :money, :integer, unit: :cents

          value :address do
            field :street, :string
          end
        end

        defmodule #{inspect(@contract)} do
          use EhOsContract.Contract,
            domain: EhOsContract.Fixtures.TableCheck.Domain,
            context: :visits,
            id: "table_check.visits"

          aggregate :visit, "Visit" do
            identity :visit_id
            command :close_visit, "Closing a visit", by: :reception, emits: :visit_closed
            event :visit_closed, "Visit closed"
          end

          read_model :visits, "Visits", projects: :visit_closed,
            table: "#{@table}", key: :visit_id do
            field :visit_id, :id
            field :status, {:enum, [:open, :closed]}
            field :paid, :money
            field :closed_at, :timestamp, optional: true
            field :tags, {:list, :string}, optional: true
            field :address, :address, optional: true
            field :member_id, :id, subject: :member
            field :name, :string, personal: :member_id
          end
        end
        """,
        "table_check.ex"
      )
    end

    :ok
  end

  # The table the contract needs, with one column replaced, dropped or added.
  defp create!(change \\ fn columns -> columns end) do
    columns =
      change.([
        "visit_id text PRIMARY KEY",
        "status text NOT NULL",
        "paid bigint NOT NULL",
        "closed_at timestamp(6)",
        "tags text[]",
        "address jsonb",
        "member_id text NOT NULL",
        "name text"
      ])

    Repo.query!("CREATE TABLE #{@table} (#{Enum.join(columns, ", ")})")
  end

  defp replace(columns, name, by),
    do: Enum.map(columns, &if(String.starts_with?(&1, name <> " "), do: by, else: &1))

  defp failure, do: assert_raise(ExUnit.AssertionError, fn -> check() end).message
  defp check, do: Testing.assert_read_model_tables([@contract])

  test "a table that fits its contract passes" do
    create!()
    assert check() == :ok
  end

  test "a personal field's column takes NULL though the field is required" do
    create!(&replace(&1, "name", "name text"))
    assert check() == :ok
  end

  test "a column of the projection's own passes when it takes NULL or has a default" do
    create!(&(&1 ++ ["note text", "position bigint NOT NULL DEFAULT 0"]))
    assert check() == :ok
  end

  test "a missing table" do
    assert failure() =~
             "read model :visits of #{inspect(@contract)}: table \"#{@table}\" does not exist"
  end

  test "a missing column, a column of another type, and a required field's column that takes NULL" do
    create!(fn columns ->
      columns
      |> Enum.reject(&String.starts_with?(&1, "tags "))
      |> replace("paid", "paid text NOT NULL")
      |> replace("status", "status text")
    end)

    message = failure()
    assert message =~ "column tags is missing"

    assert message =~
             "column paid is text, and the field is :integer, stored as int8 or int4 or int2"

    assert message =~ "column status takes NULL, and the field is required"
    refute message =~ "column name"
  end

  test "a list and a value made of fields need their own column types" do
    create!(fn columns ->
      columns |> replace("tags", "tags text") |> replace("address", "address text")
    end)

    message = failure()
    assert message =~ "column tags is text, and the field is {:array, :string}"
    assert message =~ "column address is text, and the field is :map, stored as jsonb or json"
  end

  test "a primary key that is not the key" do
    create!(fn columns ->
      columns
      |> replace("visit_id", "visit_id text NOT NULL")
      |> replace("member_id", "member_id text PRIMARY KEY")
    end)

    assert failure() =~
             ~s|its primary key is ["member_id"], and the read model's key is ["visit_id"]|
  end

  test "a column of the projection's own that refuses a row written through Row" do
    create!(&(&1 ++ ["position bigint NOT NULL"]))

    assert failure() =~
             "column position is not a field of the read model, and is NOT NULL with no default"
  end

  describe "mix eh_os_contract.gen.migration" do
    @tag :tmp_dir
    test "writes a migration that creates a table its contract fits", %{tmp_dir: dir} do
      Mix.Tasks.EhOsContract.Gen.Migration.run([
        inspect(@contract),
        "visits",
        "--migrations-path",
        dir
      ])

      assert [path] = Path.wildcard(Path.join(dir, "*_create_#{@table}.exs"))
      source = File.read!(path)

      assert source =~ "create table(:#{@table}, primary_key: false) do"
      assert source =~ "add :visit_id, :text, primary_key: true"
      assert source =~ "add :paid, :bigint, null: false"
      assert source =~ "add :tags, {:array, :text}"
      assert source =~ "add :address, :map"
      # Personal, so an erasure may blank it, though the field is required.
      assert source =~ ~r/add :name, :text\n/
      assert source =~ "create index(:#{@table}, [:member_id])"

      [{module, _}] = Code.compile_file(path)
      :ok = Ecto.Migrator.up(Repo, 20_261_028_000_000, module, log: false, migration_lock: false)

      assert Testing.assert_read_model_tables([@contract]) == :ok
    end

    @tag :tmp_dir
    test "never writes a second migration for a table, nor one for a read model without one",
         %{tmp_dir: dir} do
      args = [inspect(@contract), "visits", "--migrations-path", dir]
      Mix.Tasks.EhOsContract.Gen.Migration.run(args)

      assert_raise Mix.Error, ~r/already holds a migration named create_#{@table}/, fn ->
        Mix.Tasks.EhOsContract.Gen.Migration.run(args)
      end

      assert_raise Mix.Error, ~r/has no read model nowhere with a table/, fn ->
        Mix.Tasks.EhOsContract.Gen.Migration.run([
          inspect(@contract),
          "nowhere",
          "--migrations-path",
          dir
        ])
      end
    end
  end
end

defmodule EhOsContract.ReadModelTable do
  # #493: the table a read model with `table:` needs, read from its `Row`, for the
  # migration `mix eh_os_contract.gen.migration` writes and for the comparison
  # `EhOsContract.Testing.assert_read_model_tables/1` makes with the database. One
  # place says what each field's column is, so the two cannot disagree.
  @moduledoc false

  alias EhOsContract.Model

  @typedoc "A column a field needs: its name, the type it stores, and its constraints."
  @type column :: %{
          name: atom(),
          type: term(),
          null: boolean(),
          primary_key: boolean()
        }

  @typedoc "The table a read model with `table:` needs."
  @type t :: %{
          contract: module(),
          read_model: atom(),
          table: String.t(),
          row: module(),
          columns: [column()],
          indexes: [[atom()]]
        }

  @doc """
  Every read model of `contracts` that names a table, as the table it needs, in the
  order the contracts and their read models are declared.
  """
  @spec of([module()]) :: [t()]
  def of(contracts) do
    for contract <- contracts,
        model = Model.fetch(contract),
        read_model <- model.read_models,
        table = Map.get(read_model, :table),
        table != nil,
        do: table(contract, model, read_model, table)
  end

  defp table(contract, model, read_model, table) do
    row = Module.concat(Model.module_for(model, :read_model, read_model.name), Row)
    key = Map.get(read_model, :key, [])

    columns =
      for field <- read_model.fields do
        %{
          name: field.name,
          type: row |> apply(:__schema__, [:type, field.name]) |> Ecto.Type.type(),
          # A personal field is blanked when its subject is erased, so its column takes
          # `NULL` whether the field is optional or not.
          null: field.optional or Map.get(field, :personal) != nil,
          primary_key: field.name in key
        }
      end

    %{
      contract: contract,
      read_model: read_model.name,
      table: table,
      row: row,
      columns: columns,
      indexes: indexes(model, read_model, key)
    }
  end

  # What a row is looked up by besides its key: a subject's field, which `forget/2`
  # deletes or blanks by, and a query's scope, which every scoped answer filters by.
  defp indexes(model, read_model, key) do
    subjects = for f <- read_model.fields, Map.get(f, :subject), do: f.name

    scopes =
      for q <- model.queries,
          q.reads == read_model.name,
          q.scope != nil,
          Enum.any?(read_model.fields, &(&1.name == q.scope)),
          do: q.scope

    (subjects ++ scopes)
    |> Enum.uniq()
    |> Enum.reject(&(key == [&1] or List.first(key) == &1))
    |> Enum.map(&[&1])
  end

  @doc """
  The source of an Ecto migration that creates `table`, as a module named `module`:
  one `add` per field, of the column type its field is stored as, `primary_key: true`
  on the key's fields, `null: false` where the column takes no `NULL`, then an index
  on each field a row is looked up by besides its key.
  """
  @spec migration(t(), module()) :: String.t()
  def migration(table, module) do
    adds =
      for c <- table.columns do
        options =
          Enum.concat([
            if(c.primary_key, do: ["primary_key: true"], else: []),
            if(c.null or c.primary_key, do: [], else: ["null: false"])
          ])

        Enum.join(["      add #{inspect(c.name)}", inspect(column_type(c.type)) | options], ", ")
      end

    indexes =
      for fields <- table.indexes,
          do: "    create index(#{inspect(String.to_atom(table.table))}, #{inspect(fields)})"

    """
    defmodule #{inspect(module)} do
      @moduledoc \"\"\"
      The table of read model `#{inspect(table.read_model)}` of `#{inspect(table.contract)}`,
      generated from its declaration by `mix eh_os_contract.gen.migration`. Edit it as any
      migration; `EhOsContract.Testing.assert_read_model_tables/1` holds the table to the
      contract from here on.
      \"\"\"

      use Ecto.Migration

      def change do
        create table(#{inspect(String.to_atom(table.table))}, primary_key: false) do
    #{Enum.join(adds, "\n")}
        end
    #{if indexes == [], do: "", else: "\n" <> Enum.join(indexes, "\n") <> "\n"}  end
    end
    """
  end

  @doc """
  Whether one of the migration `sources` creates the table `name`: `create table(:t, …)`
  or `(:t)`, the name an atom or a string, `create_if_not_exists` too. An `alter` or a
  `drop` does not count, nor does another table whose name starts with this one.
  """
  @spec created_by?(String.t(), [String.t()]) :: boolean()
  def created_by?(name, sources) do
    name = Regex.escape(name)

    creates =
      ~r/create(?:_if_not_exists)?\(?\s*table\(\s*(?::#{name}|:"#{name}"|"#{name}")\s*[,)]/

    Enum.any?(sources, &Regex.match?(creates, &1))
  end

  # The column type a migration adds for an Ecto type: text for a string, which an
  # identifier and an enum's member are too, and 64 bits for an integer, as the
  # engine bounds one.
  defp column_type(:string), do: :text
  defp column_type(:integer), do: :bigint
  defp column_type({:array, inner}), do: {:array, column_type(inner)}
  defp column_type(type), do: type

  @doc """
  What is wrong with the table in the database `repo` reads, against what `table`
  needs, in words: `[]` when nothing is. The table is found by its exact name in the
  current schema, as Ecto quotes it. A column the read model does not declare is the
  projection's own and is let be, unless it refuses a row written through `Row`:
  `NOT NULL` with no default, identity or generation. A narrower column of the same
  kind passes, an `int4` for an integer or a `varchar(n)` for a string, as Ecto's own
  `:integer` and `:string` write them; the generator writes the wide ones.
  """
  @spec problems(t(), module()) :: [String.t()]
  def problems(%{table: name} = table, repo) do
    case columns_in(repo, name) do
      [] ->
        ["table #{inspect(name)} does not exist"]

      found ->
        by_name = Map.new(found, &{&1.name, &1})
        declared = MapSet.new(table.columns, &Atom.to_string(&1.name))

        missing_or_unfit =
          Enum.flat_map(table.columns, fn column ->
            case Map.fetch(by_name, Atom.to_string(column.name)) do
              :error -> ["column #{column.name} is missing"]
              {:ok, found} -> unfit(column, found)
            end
          end)

        blocking =
          for column <- found,
              not MapSet.member?(declared, column.name),
              not column.nullable and not column.fills_itself do
            "column #{column.name} is not a field of the read model, and is NOT NULL with no " <>
              "default, so no row written through its Row fits it"
          end

        key = for c <- table.columns, c.primary_key, do: Atom.to_string(c.name)
        primary = primary_key_in(repo, name)

        key_problem =
          if Enum.sort(key) == Enum.sort(primary),
            do: [],
            else: [
              "its primary key is #{inspect(primary)}, and the read model's key is #{inspect(key)}"
            ]

        missing_or_unfit ++ blocking ++ key_problem
    end
  end

  defp unfit(column, found) do
    type =
      if fits?(column.type, found),
        do: [],
        else: [
          "column #{column.name} is #{found.shown}, and the field is #{inspect(column.type)}, " <>
            "stored as #{Enum.join(accepted(column.type), " or ")}"
        ]

    null =
      if not column.null and found.nullable,
        do: ["column #{column.name} takes NULL, and the field is required"],
        else: []

    type ++ null
  end

  # The Postgres types each Ecto type is stored in, by `udt_name`.
  defp accepted(:string), do: ["text", "varchar"]
  defp accepted(:integer), do: ["int8", "int4", "int2"]
  defp accepted(:boolean), do: ["bool"]
  defp accepted(:decimal), do: ["numeric"]
  defp accepted(:date), do: ["date"]

  defp accepted(type) when type in [:utc_datetime_usec, :utc_datetime],
    do: ["timestamp", "timestamptz"]

  defp accepted(:map), do: ["jsonb", "json"]
  # Postgres names an array of any depth by its element alone: `text[][]` is `_text`.
  defp accepted({:array, {:array, _} = inner}), do: accepted(inner)
  defp accepted({:array, inner}), do: Enum.map(accepted(inner), &("_" <> &1))
  defp accepted(_other), do: []

  defp fits?(type, %{udt: udt}), do: udt in accepted(type)

  defp columns_in(repo, table) do
    %{rows: rows} =
      repo.query!(
        """
        SELECT column_name, udt_name, is_nullable,
               column_default IS NOT NULL OR is_identity = 'YES' OR is_generated <> 'NEVER',
               data_type
        FROM information_schema.columns
        WHERE table_schema = current_schema() AND table_name = $1
        ORDER BY ordinal_position
        """,
        [table]
      )

    for [name, udt, nullable, fills_itself, data_type] <- rows do
      %{
        name: name,
        udt: udt,
        nullable: nullable == "YES",
        # A default, an identity or a generated column fills a row that leaves it out.
        fills_itself: fills_itself,
        shown: if(data_type == "ARRAY", do: "#{String.trim_leading(udt, "_")}[]", else: udt)
      }
    end
  end

  defp primary_key_in(repo, table) do
    %{rows: rows} =
      repo.query!(
        """
        SELECT a.attname
        FROM pg_index i
        JOIN pg_class c ON c.oid = i.indrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace
        JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey)
        WHERE c.relname = $1 AND n.nspname = current_schema() AND i.indisprimary
        """,
        [table]
      )

    List.flatten(rows)
  end
end

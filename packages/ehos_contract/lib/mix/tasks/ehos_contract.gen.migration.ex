defmodule Mix.Tasks.EhosContract.Gen.Migration do
  @shortdoc "Writes the migration that creates the table of a read model"

  @moduledoc """
  Writes the Ecto migration that creates the table of a read model. The task reads
  the fields from the declaration of the read model, so you do not write them a
  second time. The read model must declare `table:` and `key:`.

      mix ehos_contract.gen.migration Lending.Contracts.Membership member_directory
      mix ehos_contract.gen.migration --all

  - The first form writes the migration of one read model. It takes any compiled
    contract. If the read model has no table, the task stops with an error.
  - `--all` writes a migration for each read model whose table no migration of the
    repo creates yet. A migration creates the table if its source holds
    `table(:<table>`. It reads only the contracts of `config :ehos_contract,
    applications:`.
  - `--migrations-path DIR` writes into another directory.

  ## What the migration creates

  - A column for each field, of the type that stores the field:
    - `text` for an identifier, a string and a member of an enum;
    - `bigint` for an integer;
    - `numeric`, `boolean` and `date` for a decimal, a boolean and a date;
    - `timestamp` with microseconds for a timestamp;
    - `jsonb` for a domain value with fields, and for a list of them;
    - the column of the inner type for a domain value with an inner type;
    - an array for a list of anything else.
  - The `key:` of the read model as the primary key.
  - `null: false` on each required field, except a personal field. An erasure blanks
    a personal field.
  - An index on each field that finds a row, other than the key. These fields are the
    identifier of a subject, which `forget/2` deletes by, and the scope of a query.

  ## Where the task writes it

  The task writes the migration into the migrations of the repo:
  `priv/<repo>/migrations`, unless the `:priv` of the repo says otherwise. The file
  name is `<timestamp>_create_<table>.exs`.

  After that, the migration belongs to the application. Add to it, or change the
  table in a later migration. `EhosContract.Testing.assert_read_model_tables/1` holds
  the table to the contract.

  The task never writes over a migration:

  - If a migration `create_<table>` exists, the task stops with an error.
  - With `--all`, if two read models name one table, the task stops before it
    writes anything. The form for one read model does not check this; the compiler
    refuses it.
  - With `--all`, the task writes nothing for a read model without a table.
  """

  use Boundary, classify_to: EhosContract
  use Mix.Task

  alias EhosContract.ReadModelTable

  @impl true
  def run(args) do
    {opts, rest} =
      OptionParser.parse!(args, strict: [all: :boolean, migrations_path: :string])

    Mix.Task.run("compile")
    Application.load(:ehos_contract)

    repo = EhosContract.Config.fetch!(:repo)
    dir = opts[:migrations_path] || Path.join(priv(repo), "migrations")
    existing = migrations(dir)

    tables =
      case {opts[:all], rest} do
        {true, []} ->
          EhosContract.Registry.load!()
          sources = Enum.map(existing, &File.read!(Path.join(dir, &1)))

          Enum.reject(
            ReadModelTable.of(EhosContract.Registry.contracts()),
            &ReadModelTable.created_by?(&1.table, sources)
          )

        {nil, [contract, read_model]} ->
          [one!(contract, read_model)]

        _other ->
          Mix.raise("usage: mix ehos_contract.gen.migration CONTRACT READ_MODEL | --all")
      end

    if tables == [], do: Mix.shell().info("every read model with a table has its migration")

    # Before anything is written, so a refusal leaves no part of a set behind. The links
    # refuse a table two read models share, but only in a project that compiles them.
    for {table, owners} <- ReadModelTable.shared(tables) do
      Mix.raise(
        "table #{inspect(table)} is named by #{Enum.join(owners, " and ")}; each read model " <>
          "has a table of its own (P6), and nothing was written"
      )
    end

    File.mkdir_p!(dir)

    Enum.reduce(tables, latest(existing), fn table, latest -> write!(table, repo, dir, latest) end)
  end

  defp one!(contract, read_model) do
    module = Module.concat([contract])

    unless Code.ensure_loaded?(module) and
             function_exported?(module, :__ehos_contract_model__, 0),
           do: Mix.raise("#{contract} is not a compiled contract")

    tables = ReadModelTable.of([module])

    Enum.find(tables, &(Atom.to_string(&1.read_model) == read_model)) ||
      Mix.raise(
        "#{contract} has no read model #{read_model} with a table; its read models with one " <>
          "are #{inspect(Enum.map(tables, & &1.read_model))}"
      )
  end

  # The migration files of `dir`, by name: listed, never matched as a pattern, so a
  # path with `[` or `*` in it is a path.
  defp migrations(dir) do
    case File.ls(dir) do
      {:ok, names} ->
        names |> Enum.filter(&Regex.match?(~r/\A[0-9]{14}_.+\.exs\z/, &1)) |> Enum.sort()

      {:error, _} ->
        []
    end
  end

  # The highest version a migration of `dir` holds, so a new one never repeats it.
  defp latest(names) do
    names
    |> Enum.map(&(&1 |> String.slice(0, 14) |> String.to_integer()))
    |> Enum.max(fn -> 0 end)
  end

  defp write!(table, repo, dir, latest) do
    now = DateTime.utc_now() |> Calendar.strftime("%Y%m%d%H%M%S") |> String.to_integer()
    version = max(now, latest + 1)

    name = "create_#{table.table}"
    path = Path.join(dir, "#{version}_#{name}.exs")

    # `<version>_create_<table>.exs` exactly: `create_x_create_<table>` is another's.
    named = ~r/\A[0-9]{14}_#{Regex.escape(name)}\.exs\z/

    if Enum.any?(migrations(dir), &Regex.match?(named, &1)),
      do: Mix.raise("#{dir} already holds a migration named #{name}; it is never overwritten")

    module = Module.concat([repo, Migrations, Macro.camelize(name)])

    source =
      table
      |> ReadModelTable.migration(module)
      |> Code.format_string!(locals_without_parens: [add: :*, create: :*])
      |> IO.iodata_to_binary()

    File.write!(path, source <> "\n", [:exclusive])
    Mix.shell().info("wrote #{path}")
    version
  end

  # Where Ecto keeps a repo's migrations: its `:priv`, or `priv/<repo's last name>`.
  defp priv(repo) do
    repo.config()[:priv] ||
      Path.join("priv", repo |> Module.split() |> List.last() |> Macro.underscore())
  end
end

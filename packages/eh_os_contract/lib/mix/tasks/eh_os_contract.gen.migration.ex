defmodule Mix.Tasks.EhOsContract.Gen.Migration do
  @shortdoc "Writes the migration that creates a read model's table"

  @moduledoc """
  Writes the Ecto migration that creates the table of a read model that names one
  (`table:` and `key:`), from its declaration, so the migration does not list the
  read model's fields a second time by hand.

      mix eh_os_contract.gen.migration Lending.Contracts.Membership member_directory
      mix eh_os_contract.gen.migration --all

  The first form writes the migration of one read model. `--all` writes one for every
  read model with a table that no migration of the repo creates yet, a migration whose
  source holds `table(:<table>`.

  Each migration creates the table with:

    * one column per field, of the type its field is stored as: text for an identifier,
      a string and an enum's member, `bigint` for an integer, `numeric`, `boolean`,
      `date`, `timestamp` with microseconds, `jsonb` for a value made of fields and for
      a list of them, an array for a list of anything else;
    * the read model's `key:` as the primary key;
    * `null: false` on every required field, except a personal one, which an erasure
      blanks;
    * an index on each field a row is looked up by besides its key: a subject's
      identifier, which `forget/2` deletes by, and a query's scope.

  It is written into the repo's migrations, `priv/<repo>/migrations` unless the repo's
  `:priv` says otherwise, named `<timestamp>_create_<table>.exs`, and it is the
  application's from then on: add to it, alter the table in a later migration, and let
  `EhOsContract.Testing.assert_read_model_tables/1` hold the table to the contract. The
  task never overwrites a migration, and writes nothing for a read model without a
  table.

  `--migrations-path DIR` writes into another directory.
  """

  use Boundary, classify_to: EhOsContract
  use Mix.Task

  alias EhOsContract.ReadModelTable

  @impl true
  def run(args) do
    {opts, rest} =
      OptionParser.parse!(args, strict: [all: :boolean, migrations_path: :string])

    Mix.Task.run("compile")
    Application.load(:eh_os_contract)
    EhOsContract.Registry.load!()

    repo = EhOsContract.Config.fetch!(:repo)
    dir = opts[:migrations_path] || Path.join(priv(repo), "migrations")

    tables =
      case {opts[:all], rest} do
        {true, []} ->
          Enum.reject(ReadModelTable.of(EhOsContract.Registry.contracts()), &created?(&1, dir))

        {nil, [contract, read_model]} ->
          [one!(contract, read_model)]

        _other ->
          Mix.raise("usage: mix eh_os_contract.gen.migration CONTRACT READ_MODEL | --all")
      end

    if tables == [], do: Mix.shell().info("every read model with a table has its migration")

    File.mkdir_p!(dir)

    tables
    |> Enum.with_index()
    |> Enum.each(fn {table, i} -> write!(table, repo, dir, i) end)
  end

  defp one!(contract, read_model) do
    module = Module.concat([contract])

    unless Code.ensure_loaded?(module) and
             function_exported?(module, :__eh_os_contract_model__, 0),
           do: Mix.raise("#{contract} is not a compiled contract")

    tables = ReadModelTable.of([module])

    Enum.find(tables, &(Atom.to_string(&1.read_model) == read_model)) ||
      Mix.raise(
        "#{contract} has no read model #{read_model} with a table; its read models with one " <>
          "are #{inspect(Enum.map(tables, & &1.read_model))}"
      )
  end

  # A migration of `dir` already creates the table.
  defp created?(table, dir) do
    needle = "table(#{inspect(String.to_atom(table.table))}"

    dir
    |> Path.join("*.exs")
    |> Path.wildcard()
    |> Enum.any?(&String.contains?(File.read!(&1), needle))
  end

  defp write!(table, repo, dir, i) do
    # One second apart, so migrations written together keep their order and names.
    stamp =
      DateTime.utc_now()
      |> DateTime.add(i, :second)
      |> Calendar.strftime("%Y%m%d%H%M%S")

    name = "create_#{table.table}"
    path = Path.join(dir, "#{stamp}_#{name}.exs")

    if Path.wildcard(Path.join(dir, "*_#{name}.exs")) != [],
      do: Mix.raise("#{dir} already holds a migration named #{name}; it is never overwritten")

    module = Module.concat([repo, Migrations, Macro.camelize(name)])

    source =
      table
      |> ReadModelTable.migration(module)
      |> Code.format_string!(locals_without_parens: [add: :*, create: :*])
      |> IO.iodata_to_binary()

    File.write!(path, source <> "\n")
    Mix.shell().info("wrote #{path}")
  end

  # Where Ecto keeps a repo's migrations: its `:priv`, or `priv/<repo's last name>`.
  defp priv(repo) do
    repo.config()[:priv] ||
      Path.join("priv", repo |> Module.split() |> List.last() |> Macro.underscore())
  end
end

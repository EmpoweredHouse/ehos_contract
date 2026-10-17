defmodule Mix.Tasks.EhOsContract.Schema do
  @shortdoc "Records the fields of every event, and refuses a change old rows would not read"

  @moduledoc """
  Keeps `eh_os_contract.lock`, the record of every event's fields by its
  `schema_version`, and refuses a change to a recorded version that old rows would not
  read, or a new version whose step does not cover what changed.

  The log keeps every event it ever recorded and reads each one again whenever it
  rebuilds a unit or a list, with today's declaration. A row that lacks a field the
  declaration now requires, or holds one in another shape or under another seal, does
  not read, so a change to an event's fields raises its `schema_version` and says, in an
  `upcast` step, how an old row reads. Nothing in a
  compile notices a change made without that: the code compiles, the tests pass on an
  empty log, and the deployed application fails on its first old row. This task
  notices it where the code is written.

      mix eh_os_contract.schema                  # record what is new
      mix eh_os_contract.schema --check          # fail when anything is new or changed
      mix eh_os_contract.schema --forget TYPE    # drop what no log holds rows of, record again

  It reads every contract of the applications `config :eh_os_contract, applications:`
  names, as `mix eh_os_contract.check` does, and keeps the file beside the project's
  `mix.lock` (in an umbrella, at its root). Commit the file: a change to it shows in a
  pull request as the fields that changed.

  ## What it records

  An entry per event type, as the log names it, and version, with the fields as a row
  holds them:

      %{
        "shop.orders.order_placed" => %{
          1 => [
            customer_id: [type: :id, subject: :customer],
            note: [type: :string, optional: true, personal: :customer_id],
            order_id: [type: :id],
            total: [
              type: {:fields, [amount: [type: :decimal], currency: [type: {:enum, [:eur, :pln]}]]}
            ]
          ]
        }
      }

  A field's type is what the log stores: a built-in type, an enum as its members' names,
  a list as what it holds, and a domain value as its own shape, its inner type or its
  fields. Then whether it may be absent, whether it is personal and whose identifier
  seals it, and the subject an identifier names. Labels, the names of domain values,
  invariants and the order of fields change no stored row, and are left out: a domain
  value renamed changes nothing, and one given a field changes every event that holds
  it.

  ## What it refuses

  Recording the current version of every event adds what the file lacks, and records in
  place a change old rows still read: a field added as optional, a field removed, a
  required field made optional, an enum given members, an `:integer` made a `:decimal`,
  an `:id` made a `:string`, and the same inside a list or a domain value. A field removed
  stays in the file, marked `removed: true`, since old rows still hold it and rows written
  since do not: a field declared again under its name is held to what both hold. It
  refuses, writing nothing, when:

    * the file holds the event's current version with fields an old row would not read
      as: a field added as required, a type changed otherwise. The message names each
      such field. Raise the event's `schema_version` and add its `upcast` step: the new
      version is recorded beside the old one.
    * the steps from a recorded version to the declared one do not cover what changed: a
      field renamed without `rename:`, a required field added without `default:`, an
      optional field made required (old rows hold an explicit `nil`), a type changed
      otherwise than above, with no step a function. A function covers every change a
      step could carry, since the engine cannot see what it does.
    * a field becomes personal or stops being, or another identifier seals it; a personal
      field changes its type, or a value holding personal data its shape; a personal field
      is made required where old rows may lack it; an identifier that seals a field
      changes its `subject:`; or a field the log tags rows with (a required,
      non-personal `:id`, `:date` or `:timestamp`) was not tagged so under that name in
      the version before. Inside a domain value too. No step carries those: rows already
      sealed or tagged keep what they were written with. Declare a new event.
    * the file holds a version newer than the one declared, whose rows would not read.
    * the file holds an event no contract declares any more, renamed or removed, whose
      rows would not read either.

  `--forget TYPE` drops the event's versions from the one its contract declares up, or
  every version of an event no contract declares, and records what is declared: it says
  that no log holds rows of what it drops, as of a version added on a branch that was
  never deployed. It may be given more than once.

  `--check` writes nothing and fails when recording would change the file, or refuse.
  Run it beside `mix eh_os_contract.check`.
  """

  use Boundary, classify_to: EhOsContract
  use Mix.Task

  alias EhOsContract.SchemaLock

  @file_name "eh_os_contract.lock"

  @impl Mix.Task
  def run(args) do
    {opts, _rest} = OptionParser.parse!(args, strict: [check: :boolean, forget: :keep])

    if opts[:check] && opts[:forget],
      do: Mix.raise("--check writes nothing, so it does not take --forget")

    Mix.Task.run("compile")
    Application.load(:eh_os_contract)
    EhOsContract.Registry.load!()

    if EhOsContract.Check.no_contracts?() do
      Mix.raise(
        "no contracts found in #{inspect(EhOsContract.Config.get(:applications) || [])}, so " <>
          "there is nothing to record: set `config :eh_os_contract, applications: [...]` to " <>
          "the applications that hold your contracts"
      )
    end

    contracts = EhOsContract.Registry.contracts()
    declared = SchemaLock.declared(contracts)

    Mix.shell().info(
      lock(path(), declared, Keyword.put(opts, :steps, SchemaLock.steps(contracts)))
    )
  end

  # Beside `mix.lock`, wherever the project keeps it.
  defp path do
    lockfile = Mix.Project.config()[:lockfile] || "mix.lock"
    Path.join(Path.dirname(Path.expand(lockfile)), @file_name)
  end

  # What the task does with the file at `path` and the entries `declared`, with each
  # event's `:steps` in `opts`: the line it prints, or `Mix.raise/1` with why. Called by
  # this task and its tests.
  @doc false
  @spec lock(Path.t(), SchemaLock.t(), keyword()) :: String.t()
  def lock(path, declared, opts) do
    {found, kept} = read!(path)
    name = Path.relative_to_cwd(path)

    forgotten =
      for type <- opts |> Keyword.get_values(:forget) |> Enum.uniq(), reduce: kept do
        lock ->
          unless Map.has_key?(lock, type) or Map.has_key?(declared, type),
            do: Mix.raise("--forget #{type}: no event of that type is in #{name} or declared")

          from = declared |> Map.get(type, %{1 => []}) |> Map.keys() |> Enum.min()
          SchemaLock.forget(lock, type, from)
      end

    merged =
      case SchemaLock.merge(forgotten, declared, Keyword.get(opts, :steps, %{})) do
        {:ok, merged} -> merged
        {:error, problems} -> Mix.raise(refusal(name, problems))
      end

    cond do
      found and merged == kept ->
        "#{name} holds every event's fields"

      opts[:check] && not found ->
        Mix.raise("#{name} does not exist: run `mix eh_os_contract.schema` and commit it")

      opts[:check] ->
        Mix.raise(
          "#{name} does not record #{recorded(kept, merged)} as the contracts declare it: run " <>
            "`mix eh_os_contract.schema` and commit it"
        )

      true ->
        write!(path, SchemaLock.encode(merged))

        case summary(kept, merged) do
          [] -> "#{name}: written, and no contract declares an event"
          said -> "#{name}: " <> Enum.join(said, "; ")
        end
    end
  end

  # Beside it and renamed over it, so that a write cut short leaves the old file.
  defp write!(path, text) do
    temporary = path <> ".tmp"

    with :ok <- File.write(temporary, text),
         :ok <- File.rename(temporary, path) do
      :ok
    else
      {:error, reason} ->
        File.rm(temporary)

        Mix.raise(
          "#{Path.relative_to_cwd(path)} cannot be written: #{:file.format_error(reason)}"
        )
    end
  end

  defp read!(path) do
    case File.read(path) do
      {:ok, text} ->
        case SchemaLock.decode(text) do
          {:ok, lock} -> {true, lock}
          {:error, why} -> Mix.raise("#{Path.relative_to_cwd(path)} cannot be read: #{why}")
        end

      {:error, :enoent} ->
        {false, %{}}

      {:error, reason} ->
        Mix.raise("#{Path.relative_to_cwd(path)} cannot be read: #{:file.format_error(reason)}")
    end
  end

  defp refusal(name, problems),
    do:
      "#{name} and the contracts disagree:\n\n" <>
        Enum.map_join(problems, "\n\n", &("  * " <> &1))

  defp summary(kept, merged) do
    recorded = recorded(kept, merged)

    dropped =
      for {type, version, _fields} <- entries(kept),
          not has?(merged, type, version),
          do: {type, version}

    Enum.reject(
      [recorded && "recorded #{recorded}", listed(dropped) && "forgot #{listed(dropped)}"],
      &is_nil/1
    )
  end

  # The versions `merged` holds and `kept` does not hold alike, as the person reads them.
  defp recorded(kept, merged) do
    listed(
      for {type, version, fields} <- entries(merged),
          get_in(kept, [type, version]) != fields,
          do: {type, version}
    )
  end

  defp entries(lock),
    do:
      for(
        {type, versions} <- Enum.sort(lock),
        {version, fields} <- Enum.sort(versions),
        do: {type, version, fields}
      )

  defp has?(lock, type, version), do: Map.has_key?(Map.get(lock, type, %{}), version)

  defp listed([]), do: nil
  defp listed(versions) when length(versions) > 5, do: "#{length(versions)} event versions"
  defp listed(versions), do: Enum.map_join(versions, ", ", fn {type, v} -> "#{type} at #{v}" end)
end

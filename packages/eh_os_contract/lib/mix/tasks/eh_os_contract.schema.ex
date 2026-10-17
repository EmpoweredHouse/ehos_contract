defmodule Mix.Tasks.EhOsContract.Schema do
  @shortdoc "Records the fields of every event, and checks that none changed"

  @moduledoc """
  Keeps `eh_os_contract.lock`, the record of every event's fields by its
  `schema_version`, and refuses a change to the fields of a version it holds.

  The log keeps every event it ever recorded and reads each one again whenever it
  rebuilds a unit or a list, with today's declaration. A row written with fields the
  declaration no longer has does not read, so a change to an event's fields raises its
  `schema_version` and says, in an `upcast` step, how an old row reads. Nothing in a
  compile notices a change made without that: the code compiles, the tests pass on an
  empty log, and the deployed application fails on its first old row. This task
  notices it where the code is written.

      mix eh_os_contract.schema                  # record what is new
      mix eh_os_contract.schema --check          # fail when anything is new or changed
      mix eh_os_contract.schema --forget TYPE    # drop an event's versions, record it again

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

  Recording the current version of every event adds what the file lacks, and refuses,
  writing nothing, when:

    * the file holds the event's current version with other fields. The message names
      each field that changed. Raise the event's `schema_version` and add its `upcast`
      step: the new version is recorded beside the old one.
    * the file holds a version newer than the one declared, whose rows would not read.

  An event no contract declares any more stays in the file, since a log may still hold
  its rows. `--forget TYPE` drops every version of one event and records its current
  one: it says that no log holds rows of it, as of an event added in a branch that was
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

    declared = SchemaLock.declared(EhOsContract.Registry.contracts())
    Mix.shell().info(lock(path(), declared, opts))
  end

  # Beside `mix.lock`, wherever the project keeps it.
  defp path do
    lockfile = Mix.Project.config()[:lockfile] || "mix.lock"
    Path.join(Path.dirname(Path.expand(lockfile)), @file_name)
  end

  # What the task does with the file at `path` and the entries `declared`: the line it
  # prints, or `Mix.raise/1` with why. Called by this task and its tests.
  @doc false
  @spec lock(Path.t(), SchemaLock.t(), keyword()) :: String.t()
  def lock(path, declared, opts) do
    {found, kept} = read!(path)
    name = Path.relative_to_cwd(path)

    forgotten =
      for type <- Keyword.get_values(opts, :forget), reduce: kept do
        lock ->
          unless Map.has_key?(lock, type) or Map.has_key?(declared, type),
            do: Mix.raise("--forget #{type}: no event of that type is in #{name} or declared")

          SchemaLock.forget(lock, type)
      end

    merged =
      case SchemaLock.merge(forgotten, declared) do
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
          "#{name} lacks #{recorded(kept, merged)}: run `mix eh_os_contract.schema` and commit it"
        )

      true ->
        File.write!(path, SchemaLock.encode(merged))
        "#{name}: " <> Enum.join(summary(kept, merged), "; ")
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
      "#{if length(problems) == 1, do: "an event version differs", else: "#{length(problems)} event versions differ"} from #{name}:\n\n" <>
        Enum.map_join(problems, "\n\n", &("  * " <> &1))

  defp summary(kept, merged) do
    recorded = versions(merged, kept)
    dropped = versions(kept, merged, fn _fields, _other -> true end)

    Enum.reject(
      [listed("recorded", recorded), listed("forgot", dropped)],
      &is_nil/1
    )
  end

  # The versions `merged` holds and `kept` does not, as the person reads them.
  defp recorded(kept, merged), do: listed(nil, versions(merged, kept))

  # Each version of `lock` that `other` lacks, or, unless `same?` says otherwise, holds
  # with other fields.
  defp versions(lock, other, same? \\ &==/2) do
    for {type, versions} <- Enum.sort(lock),
        {version, fields} <- Enum.sort(versions),
        kept = Map.get(other, type, %{}),
        not Map.has_key?(kept, version) or not same?.(fields, Map.fetch!(kept, version)),
        do: "#{type} at #{version}"
  end

  defp listed(_verb, []), do: nil
  defp listed(nil, [one]), do: one
  defp listed(nil, many), do: "#{length(many)} event versions: #{Enum.join(many, ", ")}"
  defp listed(verb, versions) when length(versions) > 5,
    do: "#{verb} #{length(versions)} event versions"

  defp listed(verb, versions), do: "#{verb} #{Enum.join(versions, ", ")}"
end

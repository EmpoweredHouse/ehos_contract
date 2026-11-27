defmodule Mix.Tasks.EhosContract.Schema do
  @shortdoc "Records the fields of each event and publication, and refuses a change that breaks them"

  @moduledoc """
  Keeps `ehos_contract.lock`, the record of the fields of each event for each
  `schema_version`, and of each publication at its `version:`. It refuses a change that
  old rows do not read, a new version whose step does not cover what changed, and a
  change to a publication that its subscribers do not read.

  The log keeps each event that it recorded. It reads each event again, with the
  declaration of today, when it rebuilds a unit or a list. A row does not read if it
  lacks a field that the declaration now requires. It also does not read if it holds a
  field in another shape or under another seal. So a change to the fields of an event
  raises its `schema_version`, and an `upcast` step tells how an old row reads.

  The compile does not see a change without a new version. The code compiles, and the
  tests pass on an empty log. Then the deployed application fails on its first old row.
  This task finds the change where you write the code.

      mix ehos_contract.schema                  # record what is new
      mix ehos_contract.schema --check          # fail if anything is new or changed
      mix ehos_contract.schema --forget TYPE    # drop what no log holds rows of, and record again
      mix ehos_contract.schema --forget NAME    # drop a publication no application subscribes to

  The task reads each contract of the applications that `config :ehos_contract,
  applications:` names, as `mix ehos_contract.check` does. If they hold no contract,
  the task stops with an error. It keeps the file beside
  the `mix.lock` of the project; in an umbrella, at its root. Commit the file. In a
  pull request, a change to it shows the fields that changed.

  ## What it records

  The file has an entry for each event type, by its name in the log, and for each
  version. The entry gives the fields as a row holds them. It also has an entry for
  each publication, by its published name without the version, with the fields that the
  publication carries at its version:

      %{
        events: %{
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
        },
        publications: %{
          "shop.order_placed" => %{1 => [customer_id: [type: :id], order_id: [type: :id]]}
        }
      }

  A file written before it recorded publications holds the events alone. The task reads
  it, and writes it again with both.

  For each field, the entry gives:

  - the type that the log stores. A built-in type is its name, an enum is the names
    of its members, and a list is what it holds. A domain value is its own shape,
    its inner type or its fields;
  - if the field can be absent;
  - if the field is personal, and which identifier seals it;
  - the subject that an identifier names.

  The entry leaves out what changes no stored row: labels, the names of domain values,
  invariants and the order of fields. So a domain value that you rename changes
  nothing. A domain value that gets a new field changes each event that holds it.

  ## What it records in place

  When the task records the current version of each event, it adds what the file
  lacks. It also records in place a change that old rows still read:

  - a field added as optional;
  - a field removed;
  - a required field made optional;
  - an enum with new members;
  - an `:integer` made a `:decimal`, or an `:id` made a `:string`;
  - the same changes inside a list or a domain value.

  A removed field stays in the file, marked `removed: true`. Old rows still hold it,
  and newer rows do not. So if you declare a field of that name again, the task holds
  it to what both kinds of row hold.

  ## What it refuses

  The task refuses, and writes nothing, in these cases:

  - The file holds the current version of the event, with fields that an old row does
    not read as declared. Examples: a field added as required, or another change of
    type. The
    message names each such field. Raise the `schema_version` of the event, and add
    its `upcast` step. The task then records the new version beside the old one.
  - The steps from a recorded version to the declared one do not cover what changed:
    - a field renamed without `rename:`;
    - a required field added without `default:`;
    - an optional field made required (old rows hold an explicit `nil`);
    - another change of type, with no step that is a function.

    A function covers each change that a step can carry, because the engine cannot see
    what the function does.
  - A change of personal data, which no step carries:
    - a field becomes personal or stops being personal, or another identifier seals
      it;
    - a personal field changes its type other than in place (an `:integer` made a
      `:decimal` still reads, and the task records it in place);
    - a value that holds personal data changes its shape;
    - a required personal field, at any depth, is one that old rows can lack;
    - an identifier that seals a field changes its `subject:`.
  - A field that the log tags rows with was not tagged under that name in the version
    before. Such a field is a required, non-personal `:id`, `:date` or `:timestamp`,
    or a domain value that rests on one. This also applies inside a domain value.
  - The file holds a version newer than the declared one, whose rows do not read.
  - The file holds an event that no contract declares now, because it was renamed or
    removed. Its rows do not read either.
  - A publication removes a field, or changes the type of a field or whether it can be
    absent, at the version that the file holds. Raise its `version:`. An added field
    needs no new version.
  - A publication declares a lower version than the file holds.
  - The file holds a publication that no contract declares now, because the
    publication or its domain was renamed, or it was removed. Its subscribers receive
    nothing.

  No step carries a change of personal data or of tags. The rows already sealed or
  tagged keep what they were written with. Declare a new event instead.

  ## Forget a version, or check the file

  `--forget TYPE` drops versions of the event: the declared version and the versions
  after it. For an event that no contract declares, it drops each version. Then it
  records what is declared. Use it only when no log holds rows of what it drops.
  Example: a version that you added on a branch that was never deployed. You can give
  `--forget` more than one time.

  `--forget NAME`, with the published name without its version, such as
  `shop.order_placed`, drops the publication, and records what is declared. Use it only
  when no application subscribes to what it drops.

  `--check` writes nothing. It fails if the task would change the file, or would refuse.
  It also fails if the file does not exist. It does not take `--forget`. Run it beside
  `mix ehos_contract.check`.
  """

  use Boundary, classify_to: EhosContract
  use Mix.Task

  alias EhosContract.SchemaLock
  alias EhosContract.SchemaLock.Publications

  @file_name "ehos_contract.lock"

  @impl Mix.Task
  def run(args) do
    {opts, _rest} = OptionParser.parse!(args, strict: [check: :boolean, forget: :keep])

    if opts[:check] && opts[:forget],
      do: Mix.raise("--check writes nothing, so it does not take --forget")

    Mix.Task.run("compile")
    Application.load(:ehos_contract)
    EhosContract.Registry.load!()

    if EhosContract.Check.no_contracts?() do
      Mix.raise(
        "no contracts found in #{inspect(EhosContract.Config.get(:applications) || [])}, so " <>
          "there is nothing to record: set `config :ehos_contract, applications: [...]` to " <>
          "the applications that hold your contracts"
      )
    end

    contracts = EhosContract.Registry.contracts()
    declared = SchemaLock.declared(contracts)

    opts =
      opts
      |> Keyword.put(:steps, SchemaLock.steps(contracts))
      |> Keyword.put(:publications, Publications.declared(contracts))

    Mix.shell().info(lock(path(), declared, opts))
  end

  # Beside `mix.lock`, wherever the project keeps it.
  defp path do
    lockfile = Mix.Project.config()[:lockfile] || "mix.lock"
    Path.join(Path.dirname(Path.expand(lockfile)), @file_name)
  end

  # What the task does with the file at `path`, the events `declared`, each event's
  # `:steps` and the `:publications` declared in `opts`: the line it prints, or
  # `Mix.raise/1` with why. Called by this task and its tests.
  @doc false
  @spec lock(Path.t(), SchemaLock.t(), keyword()) :: String.t()
  def lock(path, declared, opts) do
    {found, kept} = read!(path)
    name = Path.relative_to_cwd(path)
    published = Keyword.get(opts, :publications, %{})

    forgotten =
      for type <- opts |> Keyword.get_values(:forget) |> Enum.uniq(), reduce: kept do
        lock -> forget(lock, type, declared, published, name)
      end

    events = SchemaLock.merge(forgotten.events, declared, Keyword.get(opts, :steps, %{}))
    publications = Publications.merge(forgotten.publications, published)

    merged =
      case {events, publications} do
        {{:ok, events}, {:ok, publications}} -> %{events: events, publications: publications}
        _refused -> Mix.raise(refusal(name, problems(events) ++ problems(publications)))
      end

    cond do
      found and merged == kept ->
        "#{name} holds the fields of every event and publication"

      opts[:check] && not found ->
        Mix.raise("#{name} does not exist: run `mix ehos_contract.schema` and commit it")

      opts[:check] ->
        Mix.raise(
          "#{name} does not record #{recorded(kept, merged)} as the contracts declare it: run " <>
            "`mix ehos_contract.schema` and commit it"
        )

      true ->
        write!(path, SchemaLock.encode(merged))

        case summary(kept, merged) do
          [] -> "#{name}: written, and no contract declares an event"
          said -> "#{name}: " <> Enum.join(said, "; ")
        end
    end
  end

  # A publication's entry is its name without the version (#697), which no event type is:
  # an event's type has the contract's id, of two segments at least, before its name.
  defp forget(lock, type, declared, published, name) do
    cond do
      Map.has_key?(lock.publications, type) or Map.has_key?(published, type) ->
        %{lock | publications: Publications.forget(lock.publications, type)}

      Map.has_key?(lock.events, type) or Map.has_key?(declared, type) ->
        from = declared |> Map.get(type, %{1 => []}) |> Map.keys() |> Enum.min()
        %{lock | events: SchemaLock.forget(lock.events, type, from)}

      true ->
        Mix.raise(
          "--forget #{type}: no event or publication of that name is in #{name} or declared"
        )
    end
  end

  defp problems({:ok, _merged}), do: []
  defp problems({:error, problems}), do: problems

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
        {false, %{events: %{}, publications: %{}}}

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
          entry(kept, type, version) != fields,
          do: {type, version}
    )
  end

  # Every entry of a file, an event's by its type and a publication's by its name, as
  # it is published.
  defp entries(file),
    do:
      for(
        {type, versions} <- Enum.sort(file.events),
        {version, fields} <- Enum.sort(versions),
        do: {type, version, fields}
      ) ++
        for(
          {name, versions} <- Enum.sort(file.publications),
          {version, fields} <- versions,
          do: {Publications.published(name, version), :published, fields}
        )

  defp entry(file, type, version) do
    Enum.find_value(entries(file), fn
      {^type, ^version, fields} -> fields
      _other -> nil
    end)
  end

  defp has?(file, type, version), do: entry(file, type, version) != nil

  defp listed([]), do: nil
  defp listed(versions) when length(versions) > 5, do: "#{length(versions)} event versions"
  defp listed(versions), do: Enum.map_join(versions, ", ", &version/1)

  defp version({published, :published}), do: published
  defp version({type, version}), do: "#{type} at #{version}"
end

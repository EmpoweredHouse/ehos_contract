defmodule EhosContract.SchemaLock.Publications do
  # #697: the fields each publication carries, at its version, kept in the publications
  # of `ehos_contract.lock`, so that a subscriber in another application keeps reading
  # what it was promised. The library builds a publication's name from the namespace,
  # the publication's name and its version (`EhosContract.Contract.Published`); the lock
  # keys an entry by that name without the version, and holds the one version declared.
  #
  # A subscriber reads the fields it declares and ignores the rest. So a field added
  # changes no subscriber and is recorded in place, while a field removed, or changed
  # in type or in whether it may be absent, is refused at the same version: raising
  # `version:` publishes another name, and its subscribers move to it. A lower version
  # than the lock's, and a publication the lock records that no contract declares, are
  # refused too, since their subscribers would receive nothing; forgetting the
  # publication is the person's statement that none is left.
  #
  # A field is recorded as `EhosContract.SchemaLock.fields/2` records an event's, so a
  # domain value given another field changes each publication that carries it.
  @moduledoc false

  alias EhosContract.Codec
  alias EhosContract.Model
  alias EhosContract.SchemaLock

  @doc false
  # The entry of each publication of `contracts` at the version it declares.
  @spec declared([module() | Model.t()]) :: SchemaLock.t()
  def declared(contracts) do
    for contract <- contracts,
        model = Model.fetch(contract),
        values = Codec.values(Map.get(model, :domain)),
        publication <- model.publishes,
        event = Enum.find(model.events, &(&1.name == publication.from)),
        into: %{} do
      {name, version} = split(publication.as)
      carried = Enum.filter(event.fields, &(&1.name in publication.fields))
      {name, %{version => SchemaLock.fields(carried, values)}}
    end
  end

  @doc false
  # `lock` with what `declared` adds or raises; refused, with a sentence a problem, when a
  # publication drops or changes a field at the version the lock records, declares a
  # lower version, or is no longer declared.
  @spec merge(SchemaLock.t(), SchemaLock.t()) :: {:ok, SchemaLock.t()} | {:error, [String.t()]}
  def merge(lock, declared) do
    problems =
      for {name, versions} <- Enum.sort(declared),
          {version, fields} <- versions,
          problem <- problems(name, version, fields, Map.get(lock, name)),
          do: problem

    undeclared =
      for {name, versions} <- Enum.sort(lock), not Map.has_key?(declared, name) do
        [version] = Map.keys(versions)

        "#{name}.v#{version}: the lock records it as published, and no contract of the " <>
          "applications read (`applications:`, less `exclude:`) publishes it, so its " <>
          "subscribers would receive nothing. Publish it again, or, once no application " <>
          "subscribes to it, run `mix ehos_contract.schema --forget #{name}`"
      end

    case problems ++ undeclared do
      [] -> {:ok, Map.merge(lock, declared)}
      problems -> {:error, problems}
    end
  end

  @doc false
  # `lock` without the publication `name`.
  @spec forget(SchemaLock.t(), String.t()) :: SchemaLock.t()
  def forget(lock, name), do: Map.delete(lock, name)

  @doc false
  # The published name of the entry `name` at `version`.
  @spec published(String.t(), pos_integer()) :: String.t()
  def published(name, version), do: "#{name}.v#{version}"

  defp problems(_name, _version, _fields, nil), do: []

  defp problems(name, version, fields, recorded) do
    [{was, recorded_fields}] = Map.to_list(recorded)

    cond do
      version > was ->
        []

      version < was ->
        [
          "#{published(name, version)}: the lock records version #{was}, and its subscribers " <>
            "would receive nothing under a lower one. Declare version: #{was} or higher"
        ]

      true ->
        for {field, is} <- broken(recorded_fields, fields) do
          "#{published(name, version)}: #{field} #{is}, and a subscriber of " <>
            "#{published(name, version)} may read it. Raise version: to #{version + 1}, which " <>
            "publishes #{published(name, version + 1)}, or keep the field as it was"
        end
    end
  end

  # What a subscriber of the recorded fields would no longer read: a field removed, or
  # changed in its type or in whether it may be absent.
  defp broken(recorded, fields) do
    for {field, was} <- recorded, Keyword.get(fields, field) != was do
      case Keyword.fetch(fields, field) do
        :error -> {field, "was removed"}
        {:ok, is} -> {field, "changed from #{inspect(was)} to #{inspect(is)}"}
      end
    end
  end

  defp split(published) do
    [_, name, version] = Regex.run(~r/\A(.+)\.v([0-9]+)\z/, published)
    {name, String.to_integer(version)}
  end
end

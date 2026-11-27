defmodule EhosContract.Contract.Published do
  # #697: the one place a published event's name is built, so a publisher and a
  # subscriber spell it alike. The name is `<namespace>.<publication>.v<version>`: the
  # namespace is the first segment of the publishing contract's `id:`, which D11 holds
  # to the domain's `name:`; the publication is the `publish`'s name; the version is its
  # `version:`. A subscriber writes the same three parts as a key,
  # `{namespace, publication, version}`, since it cannot compile against the publisher.
  @moduledoc false

  @typedoc "A subscriber's key for a published event."
  @type key :: {atom(), atom(), pos_integer()}

  @doc false
  # The name a contract of `id` publishes `publication` under at `version`; `nil` when the
  # contract has no id, which D11 refuses on its own.
  @spec name(String.t() | nil, atom(), pos_integer()) :: String.t() | nil
  def name(id, publication, version) when is_binary(id),
    do: "#{namespace(id)}.#{publication}.v#{version}"

  def name(_id, _publication, _version), do: nil

  @doc false
  # The name a subscriber's `key` stands for.
  @spec of_key(key()) :: String.t()
  def of_key({namespace, publication, version}),
    do: "#{namespace}.#{publication}.v#{version}"

  @doc false
  # The key a subscriber writes for the published `name`, as Elixir source.
  @spec key_source(String.t()) :: String.t()
  def key_source(name) do
    [namespace, publication, "v" <> version] = String.split(name, ".")

    "{#{inspect(String.to_atom(namespace))}, #{inspect(String.to_atom(publication))}, " <>
      "#{version}}"
  end

  defp namespace(id), do: id |> String.split(".", parts: 2) |> hd()
end

defmodule EhOsContract.EctoTypes.Value do
  # #472: the Ecto type of a field typed by a domain value, in a read model's `Row`.
  #
  # A contract names its domain without a compile dependency, so its `Row` cannot know,
  # when it compiles, what a domain value is. This type keeps the domain's module and
  # the value's name, and reads the value from the domain the first time it casts,
  # loads or dumps, through `EhOsContract.EctoTypes.of/2`: a `:money` resting on
  # `:integer` is an integer column, a domain enum an `Ecto.Enum`.
  @moduledoc false

  use Ecto.ParameterizedType

  alias EhOsContract.{Codec, EctoTypes}

  @impl true
  def init(opts),
    do: %{domain: Keyword.fetch!(opts, :domain), value: Keyword.fetch!(opts, :value)}

  @impl true
  def type(params), do: params |> resolved() |> Ecto.Type.type()

  # `nil` is `nil` whatever the value, and asks nothing of the domain: Ecto dumps a
  # field's default, `nil`, while the schema compiles, before the domain may have.
  @impl true
  def cast(nil, _params), do: {:ok, nil}
  def cast(value, params), do: params |> resolved() |> Ecto.Type.cast(value)

  @impl true
  def load(nil, _loader, _params), do: {:ok, nil}
  def load(value, loader, params), do: params |> resolved() |> Ecto.Type.load(value, loader)

  @impl true
  def dump(nil, _dumper, _params), do: {:ok, nil}
  def dump(value, dumper, params), do: params |> resolved() |> Ecto.Type.dump(value, dumper)

  @impl true
  def equal?(a, b, params), do: params |> resolved() |> Ecto.Type.equal?(a, b)

  @impl true
  def embed_as(format, params), do: params |> resolved() |> Ecto.Type.embed_as(format)

  # The value's Ecto type, read from the domain. A domain that is not compiled, or
  # that does not declare the value, is a defect the links check refuses at compile.
  defp resolved(%{domain: domain, value: value}) do
    values = Codec.values(domain)

    unless is_map_key(values, value) do
      raise ArgumentError, "#{inspect(domain)} declares no value #{inspect(value)}"
    end

    EctoTypes.of(value, values)
  end
end

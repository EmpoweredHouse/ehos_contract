defmodule EhosContract.EctoTypes.Timestamp do
  # #472: a `:timestamp` in a read model's `Row` and in a form: Ecto's
  # `:utc_datetime_usec`, except that it writes a time of any precision.
  #
  # The engine hands a consumer the time it was given: a scenario's `given` and an
  # ISO 8601 string read from a caller are often to the second. `:utc_datetime_usec`
  # refuses such a time when it dumps (`expects microsecond precision`), so a
  # projection writing `event.__meta__.occurred_at` through its row would fail on a
  # scenario's events and pass on dispatched ones. This type pads the precision when it
  # dumps, and changes nothing the engine hands out, which a test may compare with a
  # literal written to the second.
  @moduledoc false

  use Ecto.Type

  @impl true
  def type, do: :utc_datetime_usec

  @impl true
  def cast(value), do: Ecto.Type.cast(:utc_datetime_usec, value)

  @impl true
  def load(value), do: Ecto.Type.load(:utc_datetime_usec, value)

  @impl true
  def dump(%DateTime{microsecond: {microseconds, _precision}} = at),
    do: Ecto.Type.dump(:utc_datetime_usec, %{at | microsecond: {microseconds, 6}})

  def dump(value), do: Ecto.Type.dump(:utc_datetime_usec, value)

  @impl true
  def equal?(a, b), do: Ecto.Type.equal?(:utc_datetime_usec, a, b)
end

defmodule EhOsContract.Value do
  @moduledoc """
  A value of a domain, held to its invariants (plan EL2b).

      value :money, :integer, unit: :grosze do
        invariant :not_negative, "Kwota nie jest ujemna",
          violated_by: [-1],
          satisfied_by: [0, 15_000]
      end

  The domain generates a behaviour for a value that declares invariants,
  `Rehmed.Domain.Values.Money`, and a module bound with `use Rehmed.Domain, value:
  :money` defines one function per invariant, answering whether a value keeps it.
  `EhOsContract.Codec` asks here once a field's value fits its type, so dispatch
  refuses a command, or a recorded event, that carries a value breaking one, and
  raises on an event a decision returns with one: `{field, {:invariant, name}}`.

  What is read back from the log is never held to them: an invariant declared
  today does not make yesterday's events unreadable.
  """

  alias EhOsContract.{Implementations, Model}

  @doc """
  The first invariant of the value `name` of `domain` that `value` breaks, in
  declaration order, or `nil`. Only the value's own invariants: the ones of the values
  it is made of are asked by `EhOsContract.Codec`, which walks them first.

  Raises when no module implements the value, as dispatch does for a declaration
  without code, and when a function answers anything but a boolean, without saying
  what: an answer may hold the value, and a value may be personal data (v2 §17).
  """
  @spec violated(module(), atom(), term()) :: atom() | nil
  def violated(domain, name, value) do
    model = Model.fetch(domain)
    %{invariants: invariants} = Enum.find(model.values, &(&1.name == name))
    implementation = Implementations.fetch!(model, :value, name)

    Enum.find_value(invariants, fn %{name: invariant} ->
      case apply(implementation, invariant, [value]) do
        true ->
          nil

        false ->
          invariant

        # Not shown: what it answered may hold the value, and a value may be personal.
        _other ->
          raise ArgumentError,
                "#{inspect(implementation)}.#{invariant}/1 answered neither true nor false; the " <>
                  "check of invariant #{inspect(invariant)} of value #{inspect(name)} answers one"
      end
    end)
  end
end

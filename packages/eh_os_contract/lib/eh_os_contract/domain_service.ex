defmodule EhOsContract.DomainService do
  @moduledoc """
  A call to a domain service's function, held to its declaration (plan EM2).

  A contract generates `C.DomainServices.<Name>`, and a decision calls the function
  there, never the implementation: `C.DomainServices.Seating.free_seats(3, 1)`. The
  call checks the arguments against the declared types, runs the implementation
  bound with `use C, domain_service: :name`, and checks its result, as dispatch holds
  a decision to the events its command emits. A mismatch is a defect in the code,
  never a business outcome, so it raises.

  The error names the function and which argument, or the result, did not fit, and
  never the value: a domain service may be handed personal data.
  """

  alias EhOsContract.{Codec, Implementations, Model}

  @doc false
  # Called by the functions of a generated `C.DomainServices.<Name>`.
  @spec call(module(), atom(), atom(), [term()]) :: term()
  def call(contract, service, function, args) do
    model = Model.fetch(contract)
    declared = Enum.find(model.domain_services, &(&1.name == service))
    f = Enum.find(declared.functions, &(&1.name == function))
    values = Codec.values(model.domain)

    where =
      "function #{inspect(function)} of domain service #{inspect(service)} of #{inspect(contract)}"

    arguments = Map.new(Enum.zip(Enum.map(f.arguments, & &1.name), args))

    case Codec.problems(f.arguments, arguments, values) do
      [] ->
        :ok

      problems ->
        raise ArgumentError,
              "#{where} was called with arguments that do not fit their declared types: " <>
                inspect(problems)
    end

    result = apply(Implementations.fetch!(model, :domain_service, service), function, args)

    case Codec.problems(
           [%{name: :result, type: f.returns, optional: false}],
           %{result: result},
           values
         ) do
      [] ->
        result

      [{:result, problem}] ->
        raise ArgumentError,
              "#{where} returned a result that does not fit #{inspect(f.returns)} " <>
                "(#{problem}); the declaration says what it returns"
    end
  end
end

defmodule EhOsContract.DomainService do
  # A call to a domain service's function, held to its declaration (plan EM2).
  #
  # A contract generates `C.DomainServices.<Name>`, and a decision calls the function
  # there, never the implementation: `C.DomainServices.Seating.free_seats(3, 1)`. The
  # call checks the arguments against the declared types, runs the implementation
  # bound with `use C, domain_service: :name`, and checks its result, as dispatch holds
  # a decision to the events its command emits. A mismatch is a defect in the code,
  # never a business outcome, so it raises.
  #
  # The arguments and the result are held to the invariants of their domain values
  # too (plan EL2b), as a command's fields are.
  #
  # The error names the function and which argument, or the result, did not fit, and
  # never the value: a domain service may be handed personal data.
  @moduledoc false

  alias EhOsContract.{Codec, Implementations, Model}

  @doc false
  # Called by the functions of a generated `C.DomainServices.<Name>`.
  @spec call(module(), atom(), atom(), [term()]) :: term()
  def call(contract, service, function, args) when is_list(args),
    do: call(contract, service, function, args, implementation(contract, service))

  @doc false
  # The call, with the implementation given: a scenario's run finds its own, for a
  # contract compiled outside an application (`EhOsContract.ScenarioCase`).
  @spec call(module(), atom(), atom(), [term()], module()) :: term()
  def call(contract, service, function, args, implementation) when is_list(args) do
    %{functions: functions, values: values, domain: domain} = resolved(contract, service)

    where =
      "function #{inspect(function)} of domain service #{inspect(service)} of #{inspect(contract)}"

    f =
      Map.get(functions, function) ||
        raise ArgumentError,
              "#{inspect(contract)}'s domain service #{inspect(service)} " <>
                "declares no function #{inspect(function)}"

    if length(args) != length(f.arguments) do
      raise ArgumentError,
            "#{where} takes #{length(f.arguments)} arguments and was called with #{length(args)}"
    end

    arguments = Map.new(Enum.zip(Enum.map(f.arguments, & &1.name), args))

    case Codec.problems(f.arguments, arguments, values, domain) do
      [] ->
        :ok

      problems ->
        raise ArgumentError,
              "#{where} was called with arguments that do not fit their declared types: " <>
                inspect(problems)
    end

    result = apply(implementation, function, args)
    returns = [%{name: :result, type: f.returns.type, optional: f.returns.optional}]

    case Codec.problems(returns, %{result: result}, values, domain) do
      [] ->
        result

      [{:result, problem}] ->
        raise ArgumentError,
              "#{where} returned a result that does not fit #{inspect(f.returns.type)} " <>
                "(#{describe(problem)}); the declaration says what it returns"
    end
  end

  defp describe({:invariant, invariant}), do: "it breaks invariant #{inspect(invariant)}"
  defp describe(problem), do: to_string(problem)

  # The module implementing the service, looked up once and kept, as `resolved/2`
  # is and for its reason: finding it in the index costs a scan of the loaded
  # applications, and a decision may call once per line (the EL2b review). Declared
  # first, so an undeclared service is said to be one, not to lack code.
  defp implementation(contract, service) do
    key = {__MODULE__, :implementation, contract, service}

    case :persistent_term.get(key, nil) do
      nil ->
        resolved(contract, service)
        implementation = Implementations.fetch!(Model.fetch(contract), :domain_service, service)
        :persistent_term.put(key, implementation)
        implementation

      implementation ->
        implementation
    end
  end

  # What a call needs that does not change while the node runs: the declared
  # functions, the domain and its values. Looked up once per service and kept in
  # `:persistent_term`, as `EhOsContract.Implementations` keeps its index, since a
  # decision may call a function once per line of what it decides over.
  defp resolved(contract, service) do
    key = {__MODULE__, contract, service}

    case :persistent_term.get(key, nil) do
      nil ->
        model = Model.fetch(contract)

        declared =
          Enum.find(model.domain_services, &(&1.name == service)) ||
            raise ArgumentError,
                  "#{inspect(contract)} declares no domain service #{inspect(service)}"

        resolved = %{
          functions: Map.new(declared.functions, &{&1.name, &1}),
          values: Codec.values(model.domain),
          domain: model.domain
        }

        :persistent_term.put(key, resolved)
        resolved

      resolved ->
        resolved
    end
  end
end

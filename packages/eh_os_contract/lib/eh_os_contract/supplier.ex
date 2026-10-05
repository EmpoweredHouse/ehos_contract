defmodule EhOsContract.Supplier do
  @moduledoc """
  Where the values of the fields a contract declares `supplied_by: :host` come from
  (plan T1).

      config :eh_os_contract, supplier: MyApp.Supplier

  Some of what a decision depends on is not the caller's to say. Whether a visit's
  report to the state register went out is a fact of the host's systems; a request
  that carried `p1_reported: true` would decide on what the caller claims. A field
  declared `supplied_by: :host` is therefore refused from a request through
  `EhOsContract.call/3` — sent at all, even as `null`, it is `{field, :supplied}`
  — and its value is asked of the configured implementation instead, once the
  credential is authorized and before the fields are checked:

      defmodule MyApp.Supplier do
        @behaviour EhOsContract.Supplier

        @impl true
        def supply(_actor, %{name: :close_visit_clinically, given: %{visit_id: id}}),
          do: {:ok, %{p1_reported: MyApp.Register.reported?(id)}}
      end

  One call per command or recording, for every supplied field of it, with the fields
  already decoded as `given`. The answer holds exactly the fields asked for, each of
  its type; anything else is the host's defect and raises, naming the field and never
  its value. `{:error, reason}` — the register did not answer — refuses the request
  with `{:not_supplied, reason}`, and nothing is written.

  The host is asked after the caller is authorized and after what the caller sent is
  found sound — its own fields and its idempotency key — and not at all for a retry
  of a request already accepted under its key, which gets its receipt. A value that
  breaks a domain value's invariant is the host's defect, as one of the wrong type is,
  and raises. The call has no time limit of the engine's: a register that may hang
  is bounded by the implementation.

  `dispatch/3` and `record/3` from the application's own code are not asked: the
  struct it builds is trusted, as everything else in it is. A node with a contract
  declaring a supplied field does not start without an implementation configured,
  one that is loaded and exports `supply/2` (`check!/1`, at the engine's boot); the
  Mix tasks that only read contracts do not ask.
  """

  alias EhOsContract.{Actor, Codec}

  defmodule Request do
    @moduledoc """
    What the host is asked to supply: for `kind` `:command` or `:record`, the
    capability under the name EHOS grants it by, the contract, the command's or the
    recorded event's name, the `fields` to supply and the fields the request `given`,
    decoded.
    """

    @enforce_keys [:kind, :capability, :contract, :name, :fields, :given]
    defstruct [:kind, :capability, :contract, :name, :fields, :given]

    @typedoc "One request to supply."
    @type t :: %__MODULE__{
            kind: :command | :record,
            capability: String.t(),
            contract: module(),
            name: atom(),
            fields: [atom()],
            given: %{atom() => term()}
          }
  end

  @doc "The values of `request.fields`, or why the host cannot give them."
  @callback supply(Actor.t(), Request.t()) :: {:ok, %{atom() => term()}} | {:error, term()}

  @doc """
  The configured implementation, `config :eh_os_contract, supplier: MySupplier`, or
  `nil` when there is none.
  """
  @spec impl() :: module() | nil
  def impl, do: Application.get_env(:eh_os_contract, :supplier)

  @doc """
  Refuses to go on when a contract of `models` declares a field `supplied_by: :host`
  and the configured implementation is missing, not loaded, or does not export
  `supply/2`: every request carrying the field would fail. Called when the engine
  starts, so the configuration shows at deployment. Raises `ArgumentError` naming the
  contract, the declaration and the fields.
  """
  @spec check!([map()]) :: :ok
  def check!(models) do
    impl = impl()

    unless impl && Code.ensure_loaded?(impl) && function_exported?(impl, :supply, 2) do
      for model <- models,
          {kind, declaration} <-
            Enum.map(model.commands, &{:command, &1}) ++
              for(e <- model.events, e.recorded_by != [], do: {:event, e}),
          [_ | _] = fields <- [fields(declaration.fields)] do
        raise ArgumentError,
              "#{inspect(model.module)} declares #{inspect(Enum.map(fields, & &1.name))} of " <>
                "#{kind} #{inspect(declaration.name)} supplied_by: :host, and " <>
                missing(impl) <>
                ": implement EhOsContract.Supplier and set config :eh_os_contract, supplier: " <>
                "MySupplier"
      end
    end

    :ok
  end

  defp missing(nil), do: "no supplier is configured"

  defp missing(impl),
    do: "the configured supplier #{inspect(impl)} is not a module that exports supply/2"

  @doc "The fields of `fields` declared `supplied_by: :host`, in order."
  @spec fields([map()]) :: [map()]
  def fields(fields), do: Enum.filter(fields, &(Map.get(&1, :supplied_by) == :host))

  @doc """
  Asks `impl` for `request`'s fields and holds the answer to their declarations
  (`declared`, the fields as the model declares them; `values`, the domain's values by
  name).

  Raises `ArgumentError` when there is no implementation, when the answer is neither
  `{:ok, map}` nor `{:error, reason}`, when it names other fields than were asked
  for, and when a value does not fit its field — naming the field, never the value.
  """
  @spec run(Actor.t(), Request.t(), [map()], map(), module() | nil, module() | nil) ::
          {:ok, %{atom() => term()}} | {:error, {:not_supplied, term()}}
  def run(actor, %Request{} = request, declared, values, domain, impl \\ impl()) do
    impl ||
      raise ArgumentError,
            "#{inspect(request.contract)} declares #{inspect(request.fields)} of " <>
              "#{request.kind} #{inspect(request.name)} supplied_by: :host, and no supplier " <>
              "is configured (config :eh_os_contract, supplier: MySupplier)"

    case impl.supply(actor, request) do
      {:ok, supplied} when is_map(supplied) ->
        held!(impl, request, supplied, declared, values, domain)
        {:ok, supplied}

      {:error, reason} ->
        {:error, {:not_supplied, reason}}

      other ->
        raise ArgumentError,
              "#{inspect(impl)}.supply/2 returned #{shape(other)} for #{request.kind} " <>
                "#{inspect(request.name)}; it returns {:ok, %{field => value}} or " <>
                "{:error, reason}"
    end
  end

  defp held!(impl, request, supplied, declared, values, domain) do
    asked = MapSet.new(request.fields)
    given = MapSet.new(Map.keys(supplied))

    unless MapSet.equal?(asked, given) do
      raise ArgumentError,
            "#{inspect(impl)}.supply/2 was asked for #{inspect(request.fields)} of " <>
              "#{request.kind} #{inspect(request.name)} and answered " <>
              "#{inspect(Enum.sort(MapSet.to_list(given)))}; it answers exactly the fields " <>
              "it is asked for"
    end

    fields = Enum.filter(declared, &(&1.name in request.fields))

    case Codec.problems(fields, supplied, values, domain) do
      [] ->
        :ok

      problems ->
        raise ArgumentError,
              "#{inspect(impl)}.supply/2 answered #{request.kind} #{inspect(request.name)} " <>
                "with fields that do not fit: #{inspect(problems)}"
    end
  end

  # The answer's shape, never its values, which may be personal.
  defp shape(%module{}), do: "a %#{inspect(module)}{}"
  defp shape(map) when is_map(map), do: "a bare map"
  defp shape(tuple) when is_tuple(tuple), do: "a tuple of #{tuple_size(tuple)}"
  defp shape(list) when is_list(list), do: "a list"
  defp shape(_other), do: "something else"
end

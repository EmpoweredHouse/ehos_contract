defmodule EhOsContract.Supplier do
  @moduledoc """
  Gives the values of the fields that a contract declares `supplied_by: :host`. A
  caller through `EhOsContract.call/3` cannot send these fields.

      config :eh_os_contract, supplier: MyApp.Supplier

  A decision can depend on data that the caller must not give. Example: the fee for a
  late return comes from the tariff of the desk, which the host keeps. A request with
  `late_fee: 0` would make the decision on what the caller claims. So the contract
  declares the field `supplied_by: :host`, and the engine asks the configured
  implementation for its value:

      defmodule MyApp.Supplier do
        @behaviour EhOsContract.Supplier

        @impl true
        def supply(_actor, %{name: :return_copy, given: %{loan_id: id}}),
          do: {:ok, %{late_fee: MyApp.Tariff.late_fee(id)}}
      end

  ## What the caller gets

  - If a request through `EhOsContract.call/3` holds a supplied field, also as
    `null`, the engine refuses it: `{:error, {:invalid, [{field, :supplied}]}}`. Over
    HTTP, the answer is 422.
  - If the implementation returns `{:error, reason}`, the engine refuses the request:
    `{:error, {:not_supplied, reason}}`. Over HTTP, the answer is 503. The engine
    writes nothing, so the caller can send the request again.

  ## When the engine asks

  The engine asks one time for each attempt of a command or recording, for all of its
  supplied fields. `given` holds the other fields, decoded. The engine asks:

  1. after it authorizes the caller;
  2. after it checks what the caller sent: its own fields and its idempotency key;
  3. inside the transaction that appends the events, before it reads the unit.

  The answer and the events are in one transaction. So `supply/2` can lock the rows
  that it reads, for example with `SELECT ... FOR UPDATE`, and a concurrent save of
  those rows waits until the events are appended. Without a lock, the answer can be
  stale when the engine appends.

  If the stream of the unit changed after the engine read it, and the transaction is
  the engine's own, the engine tries the command again, in a new transaction, and asks
  again. In a transaction of the host, the engine returns `{:error, :conflict}`.

  If a command with a supplied field also reads entities (`reads:`), the engine reads
  them in the same transaction, after the answer, and again on each retry. A command
  with no supplied field reads its entities before the transaction
  (`EhOsContract.Entities`).

  The engine does not ask for a retry of a request that it accepted under its
  idempotency key. That retry gets its receipt.

  ## What the transaction asks of `supply/2`

  - **Make it fast.** The transaction holds a connection of the pool of the repository
    while `supply/2` runs. Each request that waits for a slow system holds one
    connection, and the other work of the application waits for the pool. The engine
    sets no time limit on the call, so limit the time of each call to another system.
    If the code of the host dispatches inside a transaction that appended before, each
    other writer of the log also waits.
  - **Lock in one order.** The engine takes the lock of the log after `supply/2`. So do
    not lock rows that a read model or a reaction delivered `:in_transaction` writes:
    the two locks in the other order can deadlock. The engine does not try a command
    again after a deadlock.
  - **Let a failed query raise.** After a query fails, Postgres refuses each next
    query of the transaction, and the engine cannot finish it. Do not catch the error
    and return `{:error, reason}`.
  - **Know what is kept.** What `supply/2` writes to the database commits with the
    transaction, also when the engine refuses the command. It rolls back if the engine
    raises. If the transaction is the engine's own, it also rolls back when the engine
    tries the command again after a conflict. A call to another system is not rolled
    back, and the engine can make it up to 3 times for one command.

  `dispatch/3` and `record/3` ask only with `supply: true`. `call/3` sets it, and a
  page with `EhOsContract.Form` can pass it. Without it, the code of the application
  fills the supplied fields itself. The engine trusts that struct, and checks those
  fields as it checks each other field. So do not fill a supplied field from what a
  caller sent.

  ## What the answer must hold

  The answer holds exactly the fields that the engine asked for, each of its type. If
  it does not, or if a value breaks an invariant of a domain value, the engine raises.
  The message names the field, never its value. Such an answer is an error in the
  code of the host. If the transaction is the engine's own, the engine also records
  the command as failed, with `failed_in` `"supplier"`.

  If a contract declares a supplied field, the node does not start without an
  implementation. The implementation must be loaded and export `supply/2`. The engine
  checks this at boot. The Mix tasks that only read contracts do not check it.
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

  @doc """
  Returns the values of `request.fields`, or `{:error, reason}` if the host cannot
  give them now.
  """
  @callback supply(Actor.t(), Request.t()) :: {:ok, %{atom() => term()}} | {:error, term()}

  # The configured implementation, `config :eh_os_contract, supplier: MySupplier`, or
  # `nil` when there is none.
  @doc false
  @spec impl() :: module() | nil
  def impl, do: EhOsContract.Config.get(:supplier)

  # Refuses to go on when a contract of `models` declares a field `supplied_by: :host`
  # and the configured implementation is missing, not loaded, or does not export
  # `supply/2`: every request carrying the field would fail. Called when the engine
  # starts, so the configuration shows at deployment. Raises `ArgumentError` naming the
  # contract, the declaration and the fields.
  @doc false
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

  # The fields of `fields` declared `supplied_by: :host`, in order.
  # Called by dispatcher.ex.
  @doc false
  @spec fields([map()]) :: [map()]
  def fields(fields), do: Enum.filter(fields, &(Map.get(&1, :supplied_by) == :host))

  # Asks `impl` for `request`'s fields and holds the answer to their declarations
  # (`declared`, the fields as the model declares them; `values`, the domain's values by
  # name).
  #
  # Raises `ArgumentError` when there is no implementation, when the answer is neither
  # `{:ok, map}` nor `{:error, reason}`, when it names other fields than were asked
  # for, and when a value does not fit its field — naming the field, never the value.
  # Called by dispatcher.ex.
  @doc false
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

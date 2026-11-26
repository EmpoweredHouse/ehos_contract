defmodule EhosContract.Entities do
  @moduledoc """
  Gives the rows of the entities that a command reads. An entity is data that the
  application keeps outside the log.

      config :ehos_contract, entities: MyApp.Entities

  A decision can depend on such data. Example: a clinic reports a booked visit to the
  state register only for some services, and the application of the clinic keeps its
  services. A command that declares `reads: [service: :service_id]` gets the service
  as the third argument of its decision. The engine asks the configured
  implementation for the row:

      defmodule MyApp.Entities do
        @behaviour EhosContract.Entities

        @impl true
        def fetch(actor, Clinic.Domain, :service, id) do
          case MyApp.Repo.get_by(MyApp.Service, id: id, clinic_id: MyApp.clinic_of(actor)) do
            nil -> :not_found
            service -> {:ok, service}
          end
        end
      end

  ## Which actor it gets

  The actor is the actor that dispatch authorized. It is the credential of a person,
  a `:system` actor that the command names in `by:`, or the domain's `:seed` actor
  (`EhosContract.Actor.seed/1`), which loads sample data and which no `by:` names. It
  is never a reaction, because a policy or a process manager cannot issue a command
  that reads. The contract does not compile otherwise.

  If the host keeps the rows of more than one tenant, answer a credential only with
  the rows of its tenant. Answer `:not_found` for the rows of another tenant. If you
  do not, a caller can make a decision read the row of another tenant, and the record
  of the command keeps it. The host decides what a `:system` actor can read.

  The host also decides what the seed can read. The seed acts in every scope, so match
  it in its own clause. A clause that answers it as a `:system` actor reads the rows of
  every tenant for it. If no clause matches it, `fetch/4` raises, and the seed fails.

  ## What the engine does with the answer

  - **`{:ok, row}`**: the row is a map or a struct with atom keys, such as an Ecto
    schema. The engine keeps the fields that the domain declares for the entity,
    with its identity, and drops the rest. Example: the decision gets
    `%{card: %{card_id: "card-1", suspended: false}}`.
  - **`:not_found`**: the engine refuses the command, as a field that names nothing:
    `{:error, {:invalid, [{:service_id, :unknown}]}}`. Through
    `EhosContract.call/3`, the answer is 422. The engine writes nothing.
  - Any other answer raises `ArgumentError`.

  The engine raises `EhosContract.Entities.UnfitRowError` if the row does not fit the
  domain. Then the code of the host and the domain do not agree:

  - a required field that the domain declares is not in the row;
  - a field has the wrong type, or its value breaks an invariant of a domain value;
  - the identity of the row is not the id that the engine asked for.

  The message names the fields, never their values. An optional field that is not in
  the row is not an error.

  ## When the engine asks

  The engine asks one time for each entry of `reads:` of the command. It stops at the
  first `:not_found`. It asks after it authorizes the caller and checks the fields of
  the command. When it asks depends on the fields of the command:

  - If the engine asks `EhosContract.Supplier` for a field of the command, the engine
    asks inside the transaction of the decision, after the supplier answers. If the
    decision meets a conflict and runs again, the engine asks again. Then `fetch/4`
    holds the transaction as `supply/2` does: read "What the transaction asks of
    `supply/2`" in `EhosContract.Supplier`.
  - Otherwise, the engine asks before the transaction of the decision. If the decision
    meets a conflict and runs again, it decides on the same rows.
  - A retry of a command that the engine accepted under its idempotency key gets its
    receipt, and the engine does not ask.
  - The engine sets no time limit on the call.

  The code of the host can dispatch a command inside a transaction: its own, or the
  transaction of a read model or an effect. Then the engine asks inside that
  transaction. If that transaction appended before, each other writer of the log
  waits for the answer. So make `fetch/4` a local read.

  The record of the command keeps what the engine read, accepted or rejected, with
  the declared fields of the row whole. So an entity with a long text or a long list
  makes each command that reads it larger.

  If a contract has a command that reads, the node does not start without an
  implementation. The implementation must be loaded and export `fetch/4`.
  """

  alias EhosContract.{Actor, Codec, Model}

  defmodule UnfitRowError do
    @moduledoc """
    Raised when the row an `EhosContract.Entities` implementation returned lacks a
    field the domain declares for the entity, or holds one of the wrong type. The
    message names the implementation, the entity and the fields, never their values.
    """

    defexception [:message]
  end

  @doc """
  Returns the row of the entity `entity` of `domain` with the id `id`, or
  `:not_found`. `actor` issued the command. Return only a row that this actor can
  have a decision read.
  """
  @callback fetch(actor :: Actor.t(), domain :: module(), entity :: atom(), id :: String.t()) ::
              {:ok, map()} | :not_found

  # The configured implementation, `config :ehos_contract, entities: MyEntities`, or
  # `nil` when there is none.
  @doc false
  @spec impl() :: module() | nil
  def impl, do: EhosContract.Config.get(:entities)

  # Refuses to go on when a command of `models` reads an entity and the configured
  # implementation is missing, not loaded, or does not export `fetch/4`: every such
  # command would fail. Called when the engine starts. Raises `ArgumentError` naming the
  # contract and the commands.
  @doc false
  @spec check!([map()]) :: :ok
  def check!(models) do
    impl = impl()

    unless impl && Code.ensure_loaded?(impl) && function_exported?(impl, :fetch, 4) do
      for model <- models,
          reading = for(c <- model.commands, Map.get(c, :reads, []) != [], do: c.name),
          reading != [] do
        raise ArgumentError,
              "#{inspect(model.module)} declares commands #{inspect(reading)} that read " <>
                "entities, and " <>
                missing(impl) <>
                ": implement EhosContract.Entities and set config :ehos_contract, entities: " <>
                "MyEntities"
      end
    end

    :ok
  end

  defp missing(nil), do: "no entities implementation is configured"

  defp missing(impl),
    do: "the configured implementation #{inspect(impl)} is not a module that exports fetch/4"

  # The rows `declaration`, a command of `model`, reads for `command`, issued by `actor`:
  # `{:ok, reads}`, each row under its name in `reads:`, `{:ok, %{}}` for a command that
  # reads nothing, or `{:error, {:invalid, [{field, :unknown}]}}` for the first row not
  # found. Called by dispatcher.ex.
  @doc false
  @spec read(map(), map(), struct(), Actor.t(), module() | nil) ::
          {:ok, %{atom() => map()}} | {:error, {:invalid, [{atom(), :unknown}]}}
  def read(model, declaration, command, actor, impl \\ impl()) do
    Enum.reduce_while(Map.get(declaration, :reads, []), {:ok, %{}}, fn {name, field},
                                                                       {:ok, acc} ->
      %{refers_to: entity} = Enum.find(declaration.fields, &(&1.name == field))

      case fetch!(impl, actor, model, entity, Map.fetch!(command, field)) do
        {:ok, row} -> {:cont, {:ok, Map.put(acc, name, row)}}
        :not_found -> {:halt, {:error, {:invalid, [{field, :unknown}]}}}
      end
    end)
  end

  # What a command's record keeps of `reads`: each row under its name, encoded by the
  # entity's fields as an event's payload is. `nil` when it read nothing.
  # Called by dispatcher.ex.
  @doc false
  @spec recorded(map(), map(), %{atom() => map()}) :: map() | nil
  def recorded(_model, _declaration, reads) when reads == %{}, do: nil

  def recorded(model, declaration, reads) do
    values = Codec.values(model.domain)

    Map.new(declaration.reads, fn {name, field} ->
      %{refers_to: entity} = Enum.find(declaration.fields, &(&1.name == field))
      {Atom.to_string(name), Codec.encode(fields(model, entity), Map.fetch!(reads, name), values)}
    end)
  end

  defp fields(model, entity), do: declared(model, entity).fields

  defp declared(model, entity),
    do: Enum.find(Model.fetch(model.domain).entities, &(&1.name == entity))

  defp fetch!(nil, _actor, model, _entity, _id) do
    raise ArgumentError,
          "#{inspect(model.module)} has a command that reads entities, and no entities " <>
            "implementation is configured (config :ehos_contract, entities: MyEntities)"
  end

  defp fetch!(impl, actor, model, entity, id) do
    case impl.fetch(actor, model.domain, entity, id) do
      {:ok, row} when is_map(row) ->
        {:ok, fitted!(impl, model, entity, id, row)}

      :not_found ->
        :not_found

      other ->
        raise ArgumentError,
              "#{inspect(impl)}.fetch/4 returned #{shape(other)} for entity " <>
                "#{inspect(entity)}; it returns {:ok, row} or :not_found"
    end
  end

  # The entity's declared fields of `row`, held to their types, and to the identity
  # asked for: a row of another one would be decided on, and recorded, as this one.
  defp fitted!(impl, model, entity, id, row) do
    %{fields: fields, identity: identity} = declared(model, entity)
    fitted = Map.new(fields, &{&1.name, Map.get(row, &1.name)})

    problems =
      Codec.problems(fields, fitted, Codec.values(model.domain), model.domain) ++
        if(fitted[identity] in [nil, id], do: [], else: [{identity, :not_the_one_asked_for}])

    if problems != [] do
      raise UnfitRowError,
            "#{inspect(impl)}.fetch/4 returned a row of entity #{inspect(entity)} that does " <>
              "not fit its declaration: #{inspect(problems)}"
    end

    fitted
  end

  # The answer's shape, never its values.
  defp shape(%module{}), do: "a %#{inspect(module)}{}"
  defp shape(map) when is_map(map), do: "a bare map"
  defp shape(tuple) when is_tuple(tuple), do: "a tuple of #{tuple_size(tuple)}"
  defp shape(list) when is_list(list), do: "a list"
  defp shape(_other), do: "something else"
end

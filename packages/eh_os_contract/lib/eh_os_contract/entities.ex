defmodule EhOsContract.Entities do
  @moduledoc """
  Where the rows of the entities a command `reads:` come from.

      config :eh_os_contract, entities: MyApp.Entities

  A decision often depends on something the application keeps outside the log: whether
  a booked visit is reported to the state register depends on the service booked, and
  the clinic's application keeps its services. A command that declares
  `reads: [service: :service_id]` gets the service as the third argument of its
  decision, and the row is asked of the configured implementation:

      defmodule MyApp.Entities do
        @behaviour EhOsContract.Entities

        @impl true
        def fetch(Clinic.Domain, :service, id) do
          case MyApp.Repo.get(MyApp.Service, id) do
            nil -> :not_found
            service -> {:ok, service}
          end
        end
      end

  ## What the engine does with the answer

  - **`{:ok, row}`**, a map or a struct with atom keys, an Ecto schema included. The
    engine keeps the fields the domain declares for the entity, its identity among
    them, and drops the rest; the decision gets `%{service: %{service_id: "s-1",
    p1_reported: true}}`. A declared field missing from the row, or of the wrong type,
    raises `EhOsContract.Entities.UnfitRowError`, naming the field and never its value:
    the host's code and the domain disagree.
  - **`:not_found`** refuses the command as a field naming nothing:
    `{:error, {:invalid, [{:service_id, :unknown}]}}`, 422 through
    `EhOsContract.call/3`, and nothing is written.
  - Anything else raises `ArgumentError`.

  ## When it is asked

  Once per command, after the caller is authorized and what it sent is found sound,
  and before the decision's transaction: when the decision meets a conflict and runs
  again, it decides on the same rows. A retry of a command already accepted under its
  idempotency key gets its receipt without asking. What was read is kept with the
  command's record. The call has no time limit of the engine's.

  A node with a contract whose command `reads:` does not start without an
  implementation configured, one that is loaded and exports `fetch/3`.
  """

  alias EhOsContract.{Codec, Model}

  defmodule UnfitRowError do
    @moduledoc """
    Raised when the row an `EhOsContract.Entities` implementation returned lacks a
    field the domain declares for the entity, or holds one of the wrong type. The
    message names the implementation, the entity and the fields, never their values.
    """

    defexception [:message]
  end

  @doc """
  The row of the entity `entity` of `domain` identified by `id`, or `:not_found`.
  """
  @callback fetch(domain :: module(), entity :: atom(), id :: String.t()) ::
              {:ok, map()} | :not_found

  # The configured implementation, `config :eh_os_contract, entities: MyEntities`, or
  # `nil` when there is none.
  @doc false
  @spec impl() :: module() | nil
  def impl, do: EhOsContract.Config.get(:entities)

  # Refuses to go on when a command of `models` reads an entity and the configured
  # implementation is missing, not loaded, or does not export `fetch/3`: every such
  # command would fail. Called when the engine starts. Raises `ArgumentError` naming the
  # contract and the commands.
  @doc false
  @spec check!([map()]) :: :ok
  def check!(models) do
    impl = impl()

    unless impl && Code.ensure_loaded?(impl) && function_exported?(impl, :fetch, 3) do
      for model <- models,
          reading = for(c <- model.commands, Map.get(c, :reads, []) != [], do: c.name),
          reading != [] do
        raise ArgumentError,
              "#{inspect(model.module)} declares commands #{inspect(reading)} that read " <>
                "entities, and " <>
                missing(impl) <>
                ": implement EhOsContract.Entities and set config :eh_os_contract, entities: " <>
                "MyEntities"
      end
    end

    :ok
  end

  defp missing(nil), do: "no entities implementation is configured"

  defp missing(impl),
    do: "the configured implementation #{inspect(impl)} is not a module that exports fetch/3"

  # The rows `declaration`, a command of `model`, reads for `command`: `{:ok, reads}`,
  # each row under its name in `reads:`, `{:ok, %{}}` for a command that reads nothing,
  # or `{:error, {:invalid, [{field, :unknown}]}}` for the first row not found.
  # Called by dispatcher.ex.
  @doc false
  @spec read(map(), map(), struct(), module() | nil) ::
          {:ok, %{atom() => map()}} | {:error, {:invalid, [{atom(), :unknown}]}}
  def read(model, declaration, command, impl \\ impl()) do
    Enum.reduce_while(Map.get(declaration, :reads, []), {:ok, %{}}, fn {name, field},
                                                                       {:ok, acc} ->
      %{refers_to: entity} = Enum.find(declaration.fields, &(&1.name == field))

      case fetch!(impl, model, entity, Map.fetch!(command, field)) do
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

  defp fields(model, entity),
    do: Enum.find(Model.fetch(model.domain).entities, &(&1.name == entity)).fields

  defp fetch!(nil, model, _entity, _id) do
    raise ArgumentError,
          "#{inspect(model.module)} has a command that reads entities, and no entities " <>
            "implementation is configured (config :eh_os_contract, entities: MyEntities)"
  end

  defp fetch!(impl, model, entity, id) do
    case impl.fetch(model.domain, entity, id) do
      {:ok, row} when is_map(row) ->
        {:ok, fitted!(impl, model, entity, row)}

      :not_found ->
        :not_found

      other ->
        raise ArgumentError,
              "#{inspect(impl)}.fetch/3 returned #{shape(other)} for entity " <>
                "#{inspect(entity)}; it returns {:ok, row} or :not_found"
    end
  end

  # The entity's declared fields of `row`, held to their types.
  defp fitted!(impl, model, entity, row) do
    fields = fields(model, entity)
    values = Codec.values(model.domain)
    fitted = Map.new(fields, &{&1.name, Map.get(row, &1.name)})

    case Codec.problems(fields, fitted, values, model.domain) do
      [] ->
        fitted

      problems ->
        raise UnfitRowError,
              "#{inspect(impl)}.fetch/3 returned a row of entity #{inspect(entity)} that does " <>
                "not fit its declaration: #{inspect(problems)}"
    end
  end

  # The answer's shape, never its values.
  defp shape(%module{}), do: "a %#{inspect(module)}{}"
  defp shape(map) when is_map(map), do: "a bare map"
  defp shape(tuple) when is_tuple(tuple), do: "a tuple of #{tuple_size(tuple)}"
  defp shape(list) when is_list(list), do: "a list"
  defp shape(_other), do: "something else"
end

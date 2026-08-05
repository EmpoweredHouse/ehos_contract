defmodule PNS.Registry do
  @moduledoc """
  The registry of handlers and contracts (notes §2).

  Not a generated module holding the whole graph — a per-module macro cannot
  arrange that, because it would require every handler to be compiled already.
  Instead a `__pns_handler__/0` marker plus a scan at boot.

  That property is the whole point: **the graph comes from the binary that
  actually runs.**
  """

  @key {__MODULE__, :graph}

  @typedoc "One handler's declaration, as recorded by `use PNS.Handler`."
  @type handler :: %{
          module: module(),
          contract: module(),
          event: atom(),
          publishes: [atom()],
          async: boolean()
        }

  @doc "Scans the application and caches the result in `:persistent_term`."
  @spec load!(atom()) :: %{handlers: [handler()], contracts: [module()]}
  def load!(app \\ :pns_prototype) do
    {:ok, modules} = :application.get_key(app, :modules)

    # `Code.ensure_loaded?` is needed because modules load lazily in dev; an
    # `:embedded` release has them all.
    loaded = Enum.filter(modules, &Code.ensure_loaded?/1)

    handlers =
      loaded
      |> Enum.filter(&function_exported?(&1, :__pns_handler__, 0))
      |> Enum.map(& &1.__pns_handler__())

    contracts =
      loaded
      |> Enum.filter(&function_exported?(&1, :__pns_contract__, 0))

    graph = %{handlers: handlers, contracts: contracts}
    :persistent_term.put(@key, graph)
    graph
  end

  @doc "The cached scan, loading it on first use."
  @spec graph() :: %{handlers: [handler()], contracts: [module()]}
  def graph do
    case :persistent_term.get(@key, nil) do
      nil -> load!()
      graph -> graph
    end
  end

  @doc "Every handler found in the running binary."
  @spec handlers() :: [handler()]
  def handlers, do: graph().handlers

  @doc "Every contract found in the running binary."
  @spec contracts() :: [module()]
  def contracts, do: graph().contracts

  @doc "Handlers of an event that run inside the emitting transaction."
  @spec sync_handlers_for(atom()) :: [handler()]
  def sync_handlers_for(event), do: for(h <- handlers(), h.event == event, not h.async, do: h)

  @doc "Handlers of an event that run through the queue."
  @spec async_handlers_for(atom()) :: [handler()]
  def async_handlers_for(event), do: for(h <- handlers(), h.event == event, h.async, do: h)

  @doc "Every handler of an event, synchronous and asynchronous alike."
  @spec handlers_for(atom()) :: [handler()]
  def handlers_for(event), do: for(h <- handlers(), h.event == event, do: h)

  @doc """
  The static graph's edges: incoming event -> handler -> published events. This is
  what the dashboard overlays on the log (notes §9).
  """
  @spec edges() :: [%{from: atom(), to: atom(), handler: module(), async: boolean()}]
  def edges do
    for h <- handlers(), published <- h.publishes do
      %{from: h.event, to: published, handler: h.module, async: h.async}
    end
  end

  @doc "Events declared across every contract, each tagged with its contract."
  @spec declared_events() :: [map()]
  def declared_events do
    for contract <- contracts(), event <- contract.events() do
      Map.put(event, :contract, contract)
    end
  end
end

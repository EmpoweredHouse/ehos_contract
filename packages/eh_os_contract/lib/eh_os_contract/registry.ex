defmodule EhOsContract.Registry do
  @moduledoc """
  The registry of handlers and contracts (notes §2).

  Not a generated module holding the whole graph — a per-module macro cannot
  arrange that, because it would require every handler to be compiled already.
  Instead a `__eh_os_contract_handler__/0` marker plus a scan at boot.

  That property is the whole point: **the graph comes from the binary that
  actually runs.**
  """

  @key {__MODULE__, :graph}

  @typedoc "One handler's declaration, as recorded by `use EhOsContract.Handler`."
  @type handler :: %{
          module: module(),
          contract: module(),
          event: atom(),
          publishes: [atom()],
          async: boolean()
        }

  @doc """
  Scans the configured applications and caches the result in `:persistent_term`.

  **Which applications is configuration, and it has to be.** Until the engine was
  extracted (2026-08-20) this defaulted to the one application there was, so the
  question never came up; a library that defaults to its own name scans itself,
  finds no contracts, and reports a perfectly healthy empty graph — which is what
  happened the first time this compiled as a package.

      config :eh_os_contract, applications: [:my_app]

  A list rather than one name, because a host may keep client trees in more than
  one application. Passing `app` explicitly stays for tests.

  **`config :eh_os_contract, exclude: [...]` names namespace prefixes, matched against
  `inspect/1`, to drop from the scan before anything downstream ever sees them.**
  `mix eh_os_contract.check`, `mix eh_os_contract.report`, `EhOsContract.Graph`, and `EhOsContract.Trace` all read
  contracts and handlers through this one registry, so one config key keeps a
  namespace out of every one of them at once — the alternative would be an
  exception written into each report by hand. Not a DSL word: which binary is
  running is an operational fact a deployer states in configuration, never a
  claim the contract itself makes. Empty by default, so the existing property —
  the graph comes from the binary that actually runs, in full — is unchanged
  unless a deployer opts into narrowing it.
  """
  @spec load!(atom() | [atom()] | nil) :: %{handlers: [handler()], contracts: [module()]}
  def load!(app \\ nil) do
    apps =
      case app || Application.get_env(:eh_os_contract, :applications) do
        nil ->
          raise ArgumentError,
                "EhOsContract does not know which applications hold your contracts. " <>
                  "Set `config :eh_os_contract, applications: [:my_app]`."

        one when is_atom(one) ->
          [one]

        many when is_list(many) ->
          many
      end

    modules =
      Enum.flat_map(apps, fn a ->
        case :application.get_key(a, :modules) do
          {:ok, modules} -> modules
          # An application that is configured and not loaded is a typo in
          # configuration, and silence here would look exactly like a client tree
          # with nothing in it.
          :undefined -> raise ArgumentError, "application #{inspect(a)} is not loaded"
        end
      end)

    # `Code.ensure_loaded?` is needed because modules load lazily in dev; an
    # `:embedded` release has them all.
    loaded =
      modules
      |> Enum.filter(&Code.ensure_loaded?/1)
      |> Enum.reject(&excluded?/1)

    handlers =
      loaded
      |> Enum.filter(&function_exported?(&1, :__eh_os_contract_handler__, 0))
      |> Enum.map(& &1.__eh_os_contract_handler__())

    contracts =
      loaded
      |> Enum.filter(&function_exported?(&1, :__eh_os_contract__, 0))

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
  def sync_handlers_for(event) do
    # Sorted, because the scan order is the order modules happen to be listed in the
    # application, and that is not a promise. Two synchronous handlers on one event
    # ran in whichever order a build produced, so behaviour could differ between two
    # deploys of identical code — and "these two are order-independent" was a claim
    # nobody had checked.
    #
    # Sorting makes it reproducible and no more than that: the order is still
    # arbitrary. If it matters, the contract is expressing sequence through an
    # alphabetical coincidence, which `mix eh_os_contract.check` reports as a warning rather
    # than this function pretending to solve.
    handlers()
    |> Enum.filter(&(&1.event == event and not &1.async))
    |> Enum.sort_by(&inspect(&1.module))
  end

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

  @doc "Commands declared across every contract, each tagged with its contract."
  @spec declared_commands() :: [map()]
  def declared_commands do
    for contract <- contracts(), command <- contract.commands() do
      Map.put(command, :contract, contract)
    end
  end

  @spec excluded?(module()) :: boolean()
  defp excluded?(module) do
    prefixes = Application.get_env(:eh_os_contract, :exclude, [])
    name = inspect(module)
    Enum.any?(prefixes, &String.starts_with?(name, &1))
  end
end

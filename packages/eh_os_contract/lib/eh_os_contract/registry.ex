defmodule EhOsContract.Registry do
  @moduledoc """
  The registry of contracts and domains (notes §2).

  Not a generated module holding the whole graph — a per-module macro cannot
  arrange that, because it would require every contract to be compiled already.
  Instead each module compiled from the DSL carries its model as
  `__eh_os_contract_model__/0`, and a scan at boot collects them.

  That property is the whole point: **the graph comes from the binary that
  actually runs.**
  """

  @key {__MODULE__, :graph}

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
  contracts through this one registry, so one config key keeps a
  namespace out of every one of them at once — the alternative would be an
  exception written into each report by hand. Not a DSL word: which binary is
  running is an operational fact a deployer states in configuration, never a
  claim the contract itself makes. Empty by default, so the existing property —
  the graph comes from the binary that actually runs, in full — is unchanged
  unless a deployer opts into narrowing it.
  """
  @spec load!(atom() | [atom()] | nil) :: %{contracts: [module()], domains: [module()]}
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

    contracts =
      Enum.filter(loaded, fn module ->
        function_exported?(module, :__eh_os_contract_model__, 0) and
          match?(%{kind: :contract, units: _}, module.__eh_os_contract_model__())
      end)

    # The domains the contracts share (plan EL2): what `glossary` and `view` start from.
    domains =
      Enum.filter(loaded, fn module ->
        function_exported?(module, :__eh_os_contract_model__, 0) and
          match?(%{kind: :domain}, module.__eh_os_contract_model__())
      end)

    graph = %{contracts: contracts, domains: domains}

    :persistent_term.put(@key, graph)
    graph
  end

  @doc "The cached scan, loading it on first use."
  @spec graph() :: %{contracts: [module()], domains: [module()]}
  def graph do
    case :persistent_term.get(@key, nil) do
      nil -> load!()
      graph -> graph
    end
  end

  @doc "Every contract found in the running binary."
  @spec contracts() :: [module()]
  def contracts, do: Map.get(graph(), :contracts, [])

  @doc "Every `EhOsContract.Domain` found in the running binary."
  @spec domains() :: [module()]
  def domains, do: Map.get(graph(), :domains, [])

  @spec excluded?(module()) :: boolean()
  defp excluded?(module) do
    prefixes = Application.get_env(:eh_os_contract, :exclude, [])
    name = inspect(module)
    Enum.any?(prefixes, &String.starts_with?(name, &1))
  end
end

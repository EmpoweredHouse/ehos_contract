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

    # Plan W2: D13 asked the database configured when the domain compiled; a release
    # may run with another, or none, and then every append of a timestamp would raise.
    # A contract's domain is asked too when the scan did not find it — another
    # application, or one `exclude:` drops — because dispatch tags with it all the same.
    referenced =
      for contract <- contracts,
          domain = contract.__eh_os_contract_model__().domain,
          Code.ensure_loaded?(domain),
          function_exported?(domain, :__eh_os_contract_model__, 0),
          do: domain

    for domain <- Enum.uniq(domains ++ referenced),
        zone = domain.__eh_os_contract_model__().time_zone,
        not EhOsContract.Domain.time_zone_known?(zone) do
      raise ArgumentError,
            "#{inspect(domain)} keeps its days in #{inspect(zone)}, which the time zone " <>
              "database this node runs with (#{inspect(Calendar.get_time_zone_database())}) " <>
              "does not know: configure the one it compiled with " <>
              "(config :elixir, :time_zone_database) and include it in the release"
    end

    :ok = unique_ids!(Enum.map(contracts, & &1.__eh_os_contract_model__()))

    graph = %{contracts: contracts, domains: domains}

    :persistent_term.put(@key, graph)
    graph
  end

  @doc false
  # Plan DD, ID4 (#178): every row and key names a contract by its id, so two contracts
  # of one id would share a history. X7 refuses that within an application at compile
  # time; this refuses it across the applications a node scans, which no compile sees.
  @spec unique_ids!([map()]) :: :ok
  def unique_ids!(models) do
    for {id, [_, _ | _] = same} <- Enum.group_by(models, & &1.id, & &1.module) do
      named =
        Enum.map_join(Enum.sort(same), " and ", fn module ->
          "#{inspect(module)} (#{inspect(Application.get_application(module))})"
        end)

      raise ArgumentError,
            "the id: #{inspect(id)} is declared by #{named}; every row and key the engine " <>
              "stores names a contract by its id, so the two would share one history. Give " <>
              "one of them another id, or leave its application out of " <>
              "config :eh_os_contract, applications:"
    end

    :ok
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

defmodule EhOsContract.Config do
  @schema [
    applications: [
      type: {:custom, __MODULE__, :shape, [:applications]},
      type_doc: "an application or a list of them",
      required: true,
      doc: """
      The OTP applications whose modules hold the domain and its contracts. The engine
      scans them at boot and every task scans them: a library cannot tell whose binary
      it runs in, and one that scanned itself would report a healthy empty graph.
      """
    ],
    repo: [
      type: {:custom, __MODULE__, :shape, [:module]},
      type_doc: "a module",
      required: true,
      doc: """
      The Ecto repo of the engine's tables (the log, subscriptions, the inbox, the
      vault's data keys) and of the read models. Every dispatch runs in its transaction.
      """
    ],
    subscriptions: [
      type: {:custom, __MODULE__, :shape, [:subscriptions]},
      type_doc: "`:run` or `:manual`",
      default: :run,
      doc: """
      `:manual` registers no subscription and starts no runner at boot, so a test
      drains them itself (`EhOsContract.Testing.drain/1`).
      """
    ],
    authorizer: [
      type: {:custom, __MODULE__, :shape, [:module]},
      type_doc: "a module",
      default: EhOsContract.Authorizer.Default,
      doc: """
      The `EhOsContract.Authorizer` deciding whether an actor may issue a command.
      `EhOsContract.Auth`, of `eh_os_contract_auth`, verifies EHOS's credentials.
      """
    ],
    supplier: [
      type: {:custom, __MODULE__, :shape, [:module_or_nil]},
      type_doc: "a module",
      doc: """
      The `EhOsContract.Supplier` giving the fields a contract declares `supplied_by:
      :host`. The engine does not start when such a field exists and this is not set.
      """
    ],
    entities: [
      type: {:custom, __MODULE__, :shape, [:module_or_nil]},
      type_doc: "a module",
      doc: """
      The `EhOsContract.Entities` giving the rows of the entities a command `reads:`.
      The engine does not start when such a command exists and this is not set.
      """
    ],
    vault: [
      type: {:custom, __MODULE__, :shape, [:module]},
      type_doc: "a module",
      default: EhOsContract.Vault.Local,
      doc: """
      The `EhOsContract.Vault` holding the master keys that wrap each subject's data
      key, for example a KMS.
      """
    ],
    "Elixir.EhOsContract.Vault": [
      type: :keyword_list,
      default: [],
      doc: """
      The settings of the master keys, written
      `config :eh_os_contract, EhOsContract.Vault, keys: [...]`: `keys:` for
      `EhOsContract.Vault.Local`, the default vault, and `destroyed:` for any vault.
      """,
      keys: [
        destroyed: [
          type: {:list, :string},
          default: [],
          doc: """
          The ids of the master keys that you destroyed. The engine does not try to
          unwrap their data keys, and reads their subjects as erased.
          """
        ],
        keys: [
          type: {:custom, __MODULE__, :shape, [:master_keys]},
          type_doc: "list of `{id, base64}`",
          default: [],
          doc: """
          The master keys as `{id, base64}`, each 32 bytes. The first wraps every new
          data key; the others only unwrap, until `mix eh_os_contract.rewrap` has moved
          every data key off them. Read them from the runtime environment.
          """
        ]
      ]
    ],
    bus: [
      type: {:custom, __MODULE__, :shape, [:bus]},
      type_doc: "a module or `{module, opts}`",
      doc: """
      The `EhOsContract.Bus` adapter, as a module or `{module, opts}`. Without one,
      nothing a contract publishes leaves the application.
      """
    ],
    exclude: [
      type: {:list, :string},
      default: [],
      doc: """
      Module name prefixes, matched against `inspect/1`, that the scan of
      `applications` leaves out: of dispatch, `check`, `report` and every other
      reader of the registry at once.
      """
    ],
    store: [
      type: {:custom, __MODULE__, :shape, [:module]},
      type_doc: "a module",
      default: EhOsContract.Store.Postgres,
      doc: "The `EhOsContract.Store` the log is appended to and read from."
    ]
  ]

  @moduledoc """
  The library's configuration: every key it reads, in one schema, checked when the
  engine starts.

      config :eh_os_contract,
        applications: [:my_app],
        repo: MyApp.Repo,
        authorizer: EhOsContract.Auth

  **An unknown key stops the engine.** `config :eh_os_contract, autorizer: ...` would
  otherwise run with the default authorizer, and nothing would say so. The same goes
  for a value of the wrong shape, a module that is not loaded (`authorizer:
  MyApp.Authorizr`) and a required key that is missing or `nil`.

  **What is not checked.** A key named after a module configures that module (an
  Ecto repo, Oban), and `:ecto_repos` is Ecto's; both are left alone, except a module
  key that looks like a misspelling of `EhOsContract.Vault` or names one of its
  modules (`EhOsContract.Vault.Local`), which is refused. Whether a configured module
  implements its behaviour is checked at boot, where it is used: the supplier when a
  contract declares a field `supplied_by: :host`, the entities when a command
  `reads:` one, the vault when one declares a
  personal field.

  **No error repeats a value.** The vault's keys and the bus's options may hold
  secrets, so a message names the key and what was expected, never what was given.

  ## Keys

  #{Spark.Options.docs(@schema)}
  """

  @app :eh_os_contract
  @schema Spark.Options.new!(@schema)
  @defaults for {key, opts} <- @schema.schema,
                Keyword.has_key?(opts, :default),
                into: %{},
                do: {key, opts[:default]}

  @typedoc "A key of the schema."
  @type key() :: atom()

  @doc """
  The value of `key`, or its default when it is not set (`nil` when it has none).
  Read on every call, as `Application.get_env/3` is, so a test may change it.
  """
  @spec get(key()) :: term()
  def get(key), do: Application.get_env(@app, key, Map.get(@defaults, key))

  @doc """
  The value of a required `key`. Raises `ArgumentError` naming the key when it is not
  set.
  """
  @spec fetch!(key()) :: term()
  def fetch!(key) do
    case Application.fetch_env(@app, key) do
      {:ok, value} when value != nil -> value
      _unset -> raise ArgumentError, "config :eh_os_contract, #{key}: is not set. #{hint(key)}"
    end
  end

  @doc """
  Checks the configuration against the schema: `:ok`, or `ArgumentError` naming the
  key and what it expects, never the value. Called when the engine starts.
  """
  @spec validate!() :: :ok
  def validate!, do: validate!(Application.get_all_env(@app))

  @doc false
  @spec validate!(keyword()) :: :ok
  def validate!(env) do
    Enum.each(env, &misplaced!/1)

    result =
      try do
        Spark.Options.validate(Enum.filter(env, &checked?/1), @schema)
      rescue
        # A crash inside the check would print the value in its stacktrace.
        _ -> {:error, :crashed}
      end

    case result do
      {:ok, _} ->
        :ok

      {:error, :crashed} ->
        raise ArgumentError,
              "config :eh_os_contract: a value has a shape that cannot be checked, " <>
                "such as an improper list (the value is not shown)"

      {:error, error} ->
        # Spark ends each reason with `, got: <the value>`, which could be a secret.
        message = String.replace(Exception.message(error), ~r/, got: [^\n]*/, "")
        raise ArgumentError, "config :eh_os_contract: " <> message <> hint(error.key, message)
    end
  end

  # The schema's documentation as Markdown, for the generated reference.
  @doc false
  @spec docs() :: String.t()
  def docs, do: Spark.Options.docs(@schema)

  @doc false
  @spec shape(
          term(),
          :applications | :module | :module_or_nil | :subscriptions | :master_keys | :bus
        ) ::
          {:ok, term()} | {:error, String.t()}
  def shape(mode, :subscriptions) when mode in [:run, :manual], do: {:ok, mode}
  def shape(_mode, :subscriptions), do: {:error, "expected :run or :manual"}

  def shape(apps, :applications) do
    if Enum.all?(List.wrap(apps), &(is_atom(&1) and &1 not in [nil, true, false])) and
         List.wrap(apps) != [],
       do: {:ok, apps},
       else: {:error, "expected an application or a non-empty list of them"}
  end

  def shape(module, :module_or_nil) when is_nil(module), do: {:ok, nil}
  def shape(module, :module_or_nil), do: shape(module, :module)

  def shape(module, :module) when is_atom(module) and module not in [nil, true, false] do
    if Code.ensure_loaded?(module),
      do: {:ok, module},
      else: {:error, "#{inspect(module)} is not a module that is loaded"}
  end

  def shape(_module, :module), do: {:error, "expected a module"}

  def shape(keys, :master_keys) do
    if master_keys?(keys),
      do: {:ok, keys},
      else: {:error, "expected a list of {id, base64} strings"}
  end

  def shape(bus, :bus) do
    case bus do
      {module, opts} when is_atom(module) and is_list(opts) -> {:ok, bus}
      module when is_atom(module) -> {:ok, bus}
      _ -> {:error, "expected a module or {module, opts}"}
    end
  end

  # Walked by hand: `Enum` raises on an improper list, and the stacktrace shows its tail.
  defp master_keys?([]), do: true

  defp master_keys?([{id, key} | rest]) when is_binary(id) and is_binary(key),
    do: master_keys?(rest)

  defp master_keys?(_other), do: false

  # A module key is left alone, but one that is nearly `EhOsContract.Vault`, or one of
  # its modules, is where a host meant to configure the vault. Compared without
  # `Elixir.`, a prefix every module shares: a misspelling scores 0.98, the package's
  # own `EhOsContract.TestRepo` 0.82.
  defp misplaced!({key, _}) when is_atom(key) and key != EhOsContract.Vault do
    with "Elixir." <> name <- Atom.to_string(key),
         true <-
           String.starts_with?(name, "EhOsContract.Vault.") or
             String.jaro_distance(name, "EhOsContract.Vault") >= 0.9 do
      raise ArgumentError,
            "config :eh_os_contract, #{name}: is not a key of the library. The vault's " <>
              "settings go under EhOsContract.Vault: " <>
              "`config :eh_os_contract, EhOsContract.Vault, keys: [...]`."
    end

    :ok
  end

  defp misplaced!(_entry), do: :ok

  defp checked?({:ecto_repos, _}), do: false
  defp checked?({EhOsContract.Vault, _}), do: true
  defp checked?({key, _}), do: not String.starts_with?(Atom.to_string(key), "Elixir.")

  defp hint(key, message) do
    if message =~ "required", do: " " <> hint(key), else: ""
  end

  defp hint(:repo), do: "Name the Ecto repo of the engine's tables: `repo: MyApp.Repo`."

  defp hint(:applications),
    do: "Name the applications holding your contracts: `applications: [:my_app]`."

  defp hint(_key), do: ""
end

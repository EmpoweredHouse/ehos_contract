defmodule EhOsContract.Config do
  @schema [
    applications: [
      type: {:or, [:atom, {:list, :atom}]},
      type_doc: "an application or a list of them",
      required: true,
      doc: """
      The OTP applications whose modules hold the domain and its contracts. The engine
      scans them at boot and every task scans them: a library cannot tell whose binary
      it runs in, and one that scanned itself would report a healthy empty graph.
      """
    ],
    repo: [
      type: :atom,
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
      type: :atom,
      default: EhOsContract.Authorizer.Default,
      doc: """
      The `EhOsContract.Authorizer` deciding whether an actor may issue a command.
      `EhOsContract.Auth`, of `eh_os_contract_auth`, verifies EHOS's credentials.
      """
    ],
    supplier: [
      type: :atom,
      doc: """
      The `EhOsContract.Supplier` giving the fields a contract declares `supplied_by:
      :host`. The engine does not start when such a field exists and this is not set.
      """
    ],
    vault: [
      type: :atom,
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
      The settings of `EhOsContract.Vault.Local`, the default vault, written
      `config :eh_os_contract, EhOsContract.Vault, keys: [...]`.
      """,
      keys: [
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
      type: :atom,
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
  for a value of the wrong shape and for a required key that is missing.

  **What is not checked.** A key named after a module other than
  `EhOsContract.Vault` configures that module (an Ecto repo, Oban), and `:ecto_repos`
  is Ecto's; both are left alone. Whether a configured module exists and implements
  its behaviour is checked where it is used: `EhOsContract.Supplier.check!/1` and
  `EhOsContract.Vault.check!/1` at boot.

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
      {:ok, value} -> value
      :error -> raise ArgumentError, "config :eh_os_contract, #{key}: is not set. #{hint(key)}"
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
    case Spark.Options.validate(Enum.filter(env, &checked?/1), @schema) do
      {:ok, _} ->
        :ok

      {:error, %{message: message}} ->
        # Spark ends a message with `, got: <the value>`, which could be a secret.
        raise ArgumentError,
              "config :eh_os_contract: " <> String.replace(message, ~r/, got: .*\z/s, "")
    end
  end

  @doc "The schema's documentation as Markdown, for the generated reference."
  @spec docs() :: String.t()
  def docs, do: Spark.Options.docs(@schema)

  @doc false
  @spec shape(term(), :subscriptions | :master_keys | :bus) ::
          {:ok, term()} | {:error, String.t()}
  def shape(mode, :subscriptions) when mode in [:run, :manual], do: {:ok, mode}
  def shape(_mode, :subscriptions), do: {:error, "expected :run or :manual"}

  def shape(keys, :master_keys) do
    if is_list(keys) and
         Enum.all?(keys, &match?({id, k} when is_binary(id) and is_binary(k), &1)),
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

  defp checked?({:ecto_repos, _}), do: false
  defp checked?({EhOsContract.Vault, _}), do: true
  defp checked?({key, _}), do: not String.starts_with?(Atom.to_string(key), "Elixir.")

  defp hint(:repo), do: "Name the Ecto repo of the engine's tables: `repo: MyApp.Repo`."

  defp hint(:applications),
    do: "Name the applications holding your contracts: `applications: [:my_app]`."

  defp hint(_key), do: ""
end

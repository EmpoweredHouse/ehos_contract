defmodule EhOsContract.Auth.Keys do
  @moduledoc """
  The public keys EHOS signs credentials with, as this application last saw them
  (`eh-os` D-34).

  **The table is the source, memory is a copy.** At start the process loads the
  last good key set from `eh_os_contract_auth_keys`, then fetches the JWKS. A
  restart while EHOS is down therefore comes back with the keys it had, which is
  the property `joken_jwks` lacks: its keys live only in a process's memory.

    * **Every five minutes** it fetches again, so a key removed from the JWKS stops
      being trusted within that interval, with nobody restarting anything.
    * **An unknown `kid`** asks for an early fetch, at most once every thirty
      seconds. Every fetch counts towards that, the scheduled ones and the failed
      ones too.
    * **A failed fetch changes nothing.** It is logged, and the last good set stays
      in force until a later fetch succeeds. A key set with no Ed25519 key in it is
      a failed fetch too: replacing the keys with nothing would lock everyone out on
      one bad answer.
    * **A successful fetch** replaces the set in the table and in memory.

  A key is known by its RFC 7638 thumbprint, computed here, never by the `kid` the
  JWKS writes beside it: the thumbprint is what EHOS puts in a credential's header
  (`eh-os` D-33), so nobody configures it and nothing can claim another key's name.

  Memory is an ETS table owned by this process and read by `verify` without a call,
  so checking a credential costs no message. It is not `:persistent_term`, whose
  every update costs a global garbage collection, and this one updates every five
  minutes.

  `EhOsContract.Auth` starts it; nothing else needs to.
  """

  use GenServer

  require Logger

  @table "eh_os_contract_auth_keys"
  @refresh_every :timer.minutes(5)
  @refetch_at_most_every :timer.seconds(30)
  # A key set is a few hundred bytes: an EHOS that takes longer than this to send one
  # is treated as down, and the keys in force stay.
  @request_options [retry: false, connect_options: [timeout: 2_000], receive_timeout: 3_000]
  @call_timeout 10_000

  @typedoc "What `start_link/1` takes. Every option but `:url` has a default."
  @type option ::
          {:name, atom()}
          | {:url, String.t()}
          | {:repo, module()}
          | {:req_options, keyword()}
          | {:refresh_every, pos_integer()}
          | {:refetch_at_most_every, non_neg_integer()}
          | {:clock, (-> integer())}

  @doc """
  Starts the process and its table, named `:name` (`#{inspect(__MODULE__)}` by
  default), fetching from `:url`.

  `:repo` defaults to the engine's (`config :eh_os_contract, :repo`). The intervals
  are in milliseconds, measured by `:clock`, which defaults to the monotonic clock.
  `:req_options` go to every `Req.get/2`, over its defaults: no retry, two seconds
  to connect, three to receive — an option given replaces the default of the same
  name whole, `:connect_options` included.
  """
  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, Keyword.put(opts, :name, name), name: name)
  end

  @doc """
  The public key whose thumbprint is `kid`, as a JWK map, or why there is none:
  `:no_keys` when this application has never seen a key set, `:unknown_key` when
  the set it has does not hold this one.

  A key not in memory asks for an early fetch first, within the rate limit above,
  and is looked up again after it.
  """
  @spec fetch(String.t(), atom()) :: {:ok, map()} | {:error, :no_keys | :unknown_key}
  def fetch(kid, name \\ __MODULE__) when is_binary(kid) do
    with :error <- lookup(name, kid) do
      refetch(name)

      case lookup(name, kid) do
        {:ok, jwk} ->
          {:ok, jwk}

        :error ->
          if :ets.info(name, :size) == 0, do: {:error, :no_keys}, else: {:error, :unknown_key}
      end
    end
  end

  # A fetch is bounded by the request timeouts below, well inside this, so the call
  # outlives it. Should the process still not answer, the credential is refused with
  # what memory holds rather than taking the caller down with it.
  defp refetch(name) do
    GenServer.call(name, :refetch, @call_timeout)
  catch
    :exit, {:timeout, _} -> :ok
  end

  @doc """
  Fetches now, as the scheduled refresh does, and answers `:ok` or why the fetch
  failed. Not rate-limited: this is the scheduled path, called directly.
  """
  @spec refresh(atom()) :: :ok | {:error, term()}
  def refresh(name \\ __MODULE__), do: GenServer.call(name, :refresh)

  @doc "The thumbprints of the keys in force, sorted."
  @spec kids(atom()) :: [String.t()]
  def kids(name \\ __MODULE__),
    do: name |> :ets.select([{{:"$1", :_}, [], [:"$1"]}]) |> Enum.sort()

  defp lookup(name, kid) do
    if :ets.whereis(name) == :undefined do
      raise ArgumentError,
            "#{inspect(name)} is not running: add EhOsContract.Auth to the application's " <>
              "supervision tree, after its repo"
    end

    case :ets.lookup(name, kid) do
      [{^kid, jwk}] -> {:ok, jwk}
      [] -> :error
    end
  end

  # --- the process ---------------------------------------------------------------------

  @impl GenServer
  def init(opts) do
    name = Keyword.fetch!(opts, :name)
    :ets.new(name, [:named_table, :protected, :set, read_concurrency: true])

    state = %{
      name: name,
      url: Keyword.fetch!(opts, :url),
      repo:
        Keyword.get_lazy(opts, :repo, fn -> Application.fetch_env!(:eh_os_contract, :repo) end),
      req_options: Keyword.get(opts, :req_options, []),
      refresh_every: Keyword.get(opts, :refresh_every, @refresh_every),
      refetch_at_most_every: Keyword.get(opts, :refetch_at_most_every, @refetch_at_most_every),
      clock: Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end),
      fetched_at: nil
    }

    {:ok, state, {:continue, :start}}
  end

  @impl GenServer
  def handle_continue(:start, state) do
    load(state)
    {_result, state} = fetch_now(state)

    if :ets.info(state.name, :size) == 0 do
      Logger.error(
        "eh_os_contract_auth has never seen a key set from #{state.url}, and refuses every " <>
          "credential with :no_keys until a fetch succeeds"
      )
    end

    {:noreply, schedule(state)}
  end

  @impl GenServer
  def handle_call(:refetch, _from, state) do
    if state.fetched_at == nil or state.clock.() - state.fetched_at >= state.refetch_at_most_every do
      {_result, state} = fetch_now(state)
      {:reply, :ok, state}
    else
      {:reply, :ok, state}
    end
  end

  def handle_call(:refresh, _from, state) do
    {result, state} = fetch_now(state)
    {:reply, result, state}
  end

  @impl GenServer
  def handle_info(:refresh, state) do
    {_result, state} = fetch_now(state)
    {:noreply, schedule(state)}
  end

  defp schedule(state) do
    Process.send_after(self(), :refresh, state.refresh_every)
    state
  end

  # The last good set, from the table. A table that cannot be read leaves memory
  # empty and says so: the fetch after it may still succeed.
  defp load(state) do
    %{rows: rows} = state.repo.query!("SELECT kid, jwk FROM #{@table}", [], log: false)
    :ets.insert(state.name, for([kid, jwk] <- rows, do: {kid, jwk}))
  rescue
    exception ->
      Logger.error(
        "eh_os_contract_auth could not read #{@table}: #{Exception.message(exception)}"
      )
  end

  defp fetch_now(state) do
    state = %{state | fetched_at: state.clock.()}

    case get(state) do
      {:ok, keys} ->
        store(state, keys)
        {:ok, state}

      {:error, reason} = error ->
        Logger.warning(
          "eh_os_contract_auth could not fetch the key set from #{state.url} (#{inspect(reason)}); " <>
            "#{:ets.info(state.name, :size)} keys stay in force"
        )

        {error, state}
    end
  end

  defp get(state) do
    case Req.get(state.url, Keyword.merge(@request_options, state.req_options)) do
      {:ok, %Req.Response{status: 200, body: %{"keys" => keys}}} when is_list(keys) ->
        case for(key <- keys, jwk = ed25519(key), do: jwk) do
          [] -> {:error, :no_ed25519_key}
          jwks -> {:ok, Map.new(jwks, &{&1 |> JOSE.JWK.from_map() |> JOSE.JWK.thumbprint(), &1})}
        end

      {:ok, %Req.Response{status: 200}} ->
        {:error, :not_a_key_set}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:status, status}}

      {:error, exception} ->
        {:error, exception}
    end
  end

  # Only the public members of an Ed25519 key are kept: a JWKS that carried a
  # private part by mistake does not get it written to a table.
  defp ed25519(%{"kty" => "OKP", "crv" => "Ed25519", "x" => x}) when is_binary(x),
    do: %{"kty" => "OKP", "crv" => "Ed25519", "x" => x}

  defp ed25519(_key), do: nil

  # The table first, so memory never holds a set the next start would not load.
  # When the table cannot be written the keys still go into memory: they are good,
  # and the next fetch tries the table again.
  defp store(state, keys) do
    now = DateTime.utc_now()
    rows = for {kid, jwk} <- keys, do: %{kid: kid, jwk: jwk, fetched_at: now}

    try do
      state.repo.transaction(fn ->
        state.repo.delete_all(@table)
        state.repo.insert_all(@table, rows)
      end)
    rescue
      exception ->
        Logger.error(
          "eh_os_contract_auth could not write #{@table}: #{Exception.message(exception)}"
        )
    end

    for {kid, _jwk} <- :ets.tab2list(state.name), not Map.has_key?(keys, kid) do
      :ets.delete(state.name, kid)
    end

    :ets.insert(state.name, Map.to_list(keys))
  end
end

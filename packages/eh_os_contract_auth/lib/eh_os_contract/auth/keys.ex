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
  so checking a credential costs no message. It holds each key ready to verify with,
  parsed once per fetch rather than once per credential, and when the rate limit
  above is next open, so a credential with an unknown `kid` inside the window costs
  no message either. It is not `:persistent_term`, whose every update costs a global
  garbage collection, and this one updates every five minutes.

  **A key process that is not running refuses, it does not raise.** While it is
  down or restarting, its table is gone with it, and every credential is refused
  with `:no_keys` — the answer `EhOsContract.Auth.ready?/0` gives for the same
  state.

  `EhOsContract.Auth` starts it; nothing else needs to.
  """

  use GenServer

  require Logger

  @table "eh_os_contract_auth_keys"
  @refresh_every :timer.minutes(5)
  @refetch_at_most_every :timer.seconds(30)
  # A key set is a few hundred bytes: an EHOS that takes longer than this to send one
  # is treated as down, and the keys in force stay.
  # No redirect is followed: the keys come from the configured URL or not at all,
  # so an answer pointing elsewhere cannot move where trust comes from.
  @request_options [
    retry: false,
    redirect: false,
    connect_options: [timeout: 2_000],
    receive_timeout: 3_000
  ]
  # A key set holds a current key and, during a rotation, a previous one. Anything
  # far beyond that is not EHOS's answer, and is not read into memory to find out.
  @max_body 64 * 1024
  @max_keys 16
  @call_timeout 10_000
  # The one entry of the table that is not a key: `{@next, clock, at}`, when the next
  # early fetch is allowed, by the process's clock.
  @next :next_early_fetch

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
  The signer for the key whose thumbprint is `kid`, or why there is none:
  `:no_keys` when this application holds no key — it has never seen a key set, or
  the key process is not running — and `:unknown_key` when the set it holds does not
  have this one.

  A key not in memory asks for an early fetch first, when the rate limit above
  allows one, and is looked up again after it.
  """
  @spec fetch(String.t(), atom()) :: {:ok, Joken.Signer.t()} | {:error, :no_keys | :unknown_key}
  def fetch(kid, name \\ __MODULE__) when is_binary(kid) do
    with :error <- lookup(name, kid) do
      if refetch_open?(name), do: refetch(name)

      case lookup(name, kid) do
        {:ok, signer} -> {:ok, signer}
        :error -> if held(name) > 0, do: {:error, :unknown_key}, else: {:error, :no_keys}
      end
    end
  end

  @doc false
  # How many keys are in force; 0 when the key process is not running.
  @spec held(atom()) :: non_neg_integer()
  def held(name \\ __MODULE__) do
    case :ets.info(name, :size) do
      size when is_integer(size) -> size - 1
      :undefined -> 0
    end
  end

  # The process checks again under its own lock: two callers may both see it open.
  defp refetch_open?(name) do
    case :ets.lookup(name, @next) do
      [{@next, clock, at}] -> at == nil or clock.() >= at
      [] -> false
    end
  rescue
    ArgumentError -> false
  end

  # A fetch is bounded by the request timeouts below, well inside this, so the call
  # outlives it. Should the process not answer — too slow, or not running — the
  # credential is refused with what memory holds rather than taking the caller down.
  defp refetch(name) do
    GenServer.call(name, :refetch, @call_timeout)
  catch
    :exit, _reason -> :ok
  end

  @doc """
  Fetches now, as the scheduled refresh does, and answers `:ok` or why the fetch
  failed. Not rate-limited: this is the scheduled path, called directly.
  """
  @spec refresh(atom()) :: :ok | {:error, term()}
  def refresh(name \\ __MODULE__), do: GenServer.call(name, :refresh, @call_timeout)

  @doc """
  Trusts the public key `jwk` in memory until the process stops, through every
  refresh, without writing it to the table; answers its thumbprint.

  This is how `EhOsContract.Auth.Testing` gets its test key trusted, and nothing
  else calls it: a key pinned here verifies credentials exactly as EHOS's do. So it
  works only where the configuration allows it, which is meant to be a test's:

      # config/test.exs
      config :eh_os_contract_auth, pin_keys: true

  Anywhere else it raises, so no code in a running application can make it trust a
  key EHOS did not publish.
  """
  @spec pin(map(), atom()) :: String.t()
  def pin(jwk, name \\ __MODULE__) when is_map(jwk) do
    unless Application.get_env(:eh_os_contract_auth, :pin_keys, false) == true do
      raise ArgumentError,
            "pinning a key is for tests, and this environment does not allow it: set " <>
              "config :eh_os_contract_auth, pin_keys: true in config/test.exs"
    end

    # Checked here, in the caller: raising in the process would take its table, and
    # every key in force, with it.
    {kid, public} =
      ed25519(jwk) || raise ArgumentError, "only an Ed25519 public key can be pinned"

    GenServer.call(name, {:pin, kid, public})
  end

  @doc "The thumbprints of the keys in force, sorted."
  @spec kids(atom()) :: [String.t()]
  def kids(name \\ __MODULE__),
    do: name |> :ets.select([{{:"$1", :_}, [{:is_binary, :"$1"}], [:"$1"]}]) |> Enum.sort()

  defp lookup(name, kid) do
    case :ets.lookup(name, kid) do
      [{^kid, signer}] -> {:ok, signer}
      [] -> :error
    end
  rescue
    # No table: the key process is not running.
    ArgumentError -> :error
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
      fetched_at: nil,
      pinned: %{}
    }

    :ets.insert(name, {@next, state.clock, nil})
    {:ok, state, {:continue, :start}}
  end

  @impl GenServer
  def handle_continue(:start, state) do
    load(state)
    {_result, state} = fetch_now(state)

    if held(state.name) == 0 do
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

  def handle_call({:pin, kid, public}, _from, state) do
    :ets.insert(state.name, {kid, signer(public)})
    {:reply, kid, %{state | pinned: Map.put(state.pinned, kid, public)}}
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
    :ets.insert(state.name, for([kid, jwk] <- rows, do: {kid, signer(jwk)}))
  rescue
    exception ->
      Logger.error(
        "eh_os_contract_auth could not read #{@table}: #{Exception.message(exception)}"
      )
  end

  defp fetch_now(state) do
    now = state.clock.()
    :ets.insert(state.name, {@next, state.clock, now + state.refetch_at_most_every})
    state = %{state | fetched_at: now}

    case get(state) do
      {:ok, keys} ->
        store(state, keys)
        {:ok, state}

      {:error, reason} = error ->
        Logger.warning(
          "eh_os_contract_auth could not fetch the key set from #{state.url} (#{inspect(reason)}); " <>
            "#{held(state.name)} keys stay in force"
        )

        {error, state}
    end
  end

  defp get(state) do
    options = Keyword.merge([into: &at_most/2] ++ @request_options, state.req_options)

    case Req.get(state.url, options) do
      {:ok, %Req.Response{status: 200, body: :too_large}} ->
        {:error, :too_large}

      {:ok, %Req.Response{status: 200, body: %{"keys" => keys}}}
      when is_list(keys) and length(keys) > @max_keys ->
        {:error, :too_many_keys}

      {:ok, %Req.Response{status: 200, body: %{"keys" => keys}}} when is_list(keys) ->
        case for(key <- keys, entry = ed25519(key), into: %{}, do: entry) do
          empty when map_size(empty) == 0 -> {:error, :no_ed25519_key}
          keys -> {:ok, keys}
        end

      {:ok, %Req.Response{status: 200}} ->
        {:error, :not_a_key_set}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:status, status}}

      {:error, exception} ->
        {:error, exception}
    end
  rescue
    # Whatever the answer holds, it is a failed fetch, never a crash of this process:
    # a crash takes its table with it, and a restart would fetch the same answer.
    exception -> {:error, exception}
  end

  # Collects the body up to `@max_body` and gives up past it.
  defp at_most({:data, data}, {request, response}) do
    body = (response.body || "") <> data

    if byte_size(body) > @max_body,
      do: {:halt, {request, %{response | body: :too_large}}},
      else: {:cont, {request, %{response | body: body}}}
  end

  # `{thumbprint, public members}` of an Ed25519 key, or nil for anything else. Only
  # the public members are kept, so a JWKS that carried a private part by mistake
  # does not get it written to a table; and an `x` that is not 32 bytes is skipped,
  # so one malformed entry costs itself and not the keys beside it.
  defp ed25519(%{"kty" => "OKP", "crv" => "Ed25519", "x" => x}) when is_binary(x) do
    case Base.url_decode64(x, padding: false) do
      {:ok, <<_::binary-size(32)>>} ->
        public = %{"kty" => "OKP", "crv" => "Ed25519", "x" => x}
        {public |> JOSE.JWK.from_map() |> JOSE.JWK.thumbprint(), public}

      _malformed ->
        nil
    end
  end

  defp ed25519(_key), do: nil

  # Parsed once, when the key enters memory, not once per credential.
  defp signer(jwk), do: Joken.Signer.create("Ed25519", jwk)

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

    keep = Map.merge(keys, state.pinned)
    for kid <- kids(state.name), not Map.has_key?(keep, kid), do: :ets.delete(state.name, kid)
    :ets.insert(state.name, for({kid, jwk} <- keys, do: {kid, signer(jwk)}))
  end
end

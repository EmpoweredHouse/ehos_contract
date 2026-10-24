defmodule EhOsContract.Auth.Workload do
  # As agreed with EHOS: the application calls EHOS's API as itself, with OAuth's client
  # credentials grant and `private_key_jwt`, for the people directory (#252) and for mail (eh-os
  # D-140, #436). One credential serves both, as EHOS gives the workload one client key.
  @moduledoc """
  The application's own credential at EHOS, which `EhOsContract.Auth.People` reads the
  company's people with and `EhOsContract.Auth.Mail` sends mail with.

      # config/runtime.exs
      config :eh_os_contract_auth,
        issuer: System.fetch_env!("EHOS_ISSUER"),
        workload: [
          client_id: System.fetch_env!("EHOS_CLIENT_ID"),
          client_key_file: System.fetch_env!("EHOS_CLIENT_KEY_FILE")
        ]

      # the supervision tree
      children = [MyApp.Repo, EhOsContract, EhOsContract.Auth, EhOsContract.Auth.Workload]

  EHOS gives a workload whose `ehos.yaml` asks for people or for mail its client id and
  key, whether or not it signs people in. Asking grants nothing: EHOS answers only what
  someone has agreed for that environment.

  `config :eh_os_contract_auth, :people`, and `EhOsContract.Auth.People` as the child,
  are this process's names before it served mail too, and still start it.

  **The credential.** The process takes one at EHOS's token endpoint,
  `<issuer>/oauth/token`, with the client credentials grant, signing an assertion with
  the client key, the first time it is needed; keeps it for its ten minutes; and takes
  another a minute before it expires, going on with the one it has while it is still
  valid if that fails. Callers that need one at the same time wait for one request.
  When EHOS refuses or cannot be reached, the next five seconds' callers are answered
  the same without asking it again. A call EHOS answers 401, as after its keys rotate,
  takes a new credential and is tried once more. Nothing is fetched at start, so the
  host starts while EHOS is down.

  Each request to EHOS goes over https, follows no redirect and reads a bounded body;
  EHOS's certificate is checked against the system's authorities, or `cacertfile:` /
  `cacerts:` given to the child.

  **What is checked at boot.** `child_spec/1` raises when the configuration is missing,
  is not a keyword list or has a key it does not take, when both `:workload` and
  `:people` are set, when the issuer is not `https://<host>[:port]`, when `client_id`
  is not a non-empty string, or when the client key file is not the one Ed25519 JWK
  EHOS gives. Nothing secret appears in what it raises.
  """

  use GenServer

  require Logger

  alias EhOsContract.Auth.Address
  alias EhOsContract.Auth.SignIn.{ClientKey, Http}
  alias EhOsContract.Auth.Workload.Config

  @keys [:client_id, :client_key_file]
  @assertion_type "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"
  @deadline 10_000
  # How long a caller waits for a credential: the token request's deadline, and a margin.
  @credential_wait @deadline + 2_000
  # A page of 500 people, EHOS's largest, with long names and addresses; a mail answer is less.
  @max_body 1024 * 1024
  # A credential is taken again this long before it expires, so one is never sent expired.
  @renew_before_seconds 60
  # How long a refusal or an outage of the token endpoint is answered without asking again.
  @failure_kept_ms 5_000

  @typedoc "Why no request was made: the credential could not be taken."
  @type reason :: :not_asked | :rate_limited | :unavailable

  @typedoc "EHOS's answer: its status, headers and body, as read."
  @type answer :: {non_neg_integer(), [{charlist(), charlist()}], binary()}

  @doc false
  def child_spec(opts) do
    opts = Keyword.put_new(opts, :name, __MODULE__)
    config = config!(opts)

    %{
      id: opts[:name],
      start: {GenServer, :start_link, [__MODULE__, config, [name: opts[:name]]]}
    }
  end

  @doc false
  # A request to EHOS's API with the credential, and once more with a new one when EHOS answers
  # 401: a second 401 is answered as it came. `body` is JSON to send, or nil. Each attempt has
  # `timeout`, or, with `shared: true`, both share it. The caller reads the status in its own words;
  # what the transport did is `{:error, {:unreachable, reason}}`.
  @spec request(
          GenServer.server(),
          :get | :post,
          String.t(),
          iodata() | nil,
          pos_integer(),
          [{:shared, boolean()}]
        ) :: {:ok, answer()} | {:error, reason() | {:unreachable, term()}}
  def request(server, method, path, body, timeout, opts \\ []) do
    started = System.monotonic_time(:millisecond)

    with {:ok, credential} <- credential(server, nil) do
      case send_request(credential, method, path, body, timeout) do
        {:ok, {401, _headers, _body}} = answer ->
          left =
            if opts[:shared],
              do: timeout - (System.monotonic_time(:millisecond) - started),
              else: timeout

          with true <- left > 0 || answer,
               {:ok, renewed} <- credential(server, credential.id) do
            send_request(renewed, method, path, body, left)
          end

        answer ->
          answer
      end
    end
  end

  # What a caller is given: the credential, an id to say it is stale by, and where to send it.
  # Never the client key, which stays in the process.
  defp credential(server, stale) do
    GenServer.call(server, {:credential, stale}, @credential_wait)
  catch
    :exit, reason ->
      Logger.warning("EhOsContract.Auth.Workload gave no credential: #{exit_reason(reason)}")
      {:error, :unavailable}
  end

  defp exit_reason({:timeout, _call}), do: "it took too long"
  defp exit_reason({:noproc, _call}), do: "it is not running"
  defp exit_reason(_reason), do: "it exited"

  defp send_request(credential, method, path, body, timeout) do
    headers = [{"authorization", "Bearer " <> credential.token}, {"accept", "application/json"}]
    url = credential.issuer <> path

    request =
      if body,
        do: {url, headers, "application/json", body},
        else: {url, headers}

    case Http.request(method, request, [timeout: timeout], [], credential.request_opts) do
      {:ok, {{_version, status, _reason}, headers, body}} -> {:ok, {status, headers, body}}
      {:error, reason} -> {:error, {:unreachable, reason}}
    end
  end

  ## The process

  @impl true
  def init(%Config{} = config) do
    {:ok,
     %{
       config: config,
       credential: nil,
       expires_at: 0,
       renew_at: 0,
       taking: nil,
       waiting: [],
       failed: nil
     }}
  end

  @impl true
  def handle_call({:credential, stale}, from, state) do
    state = forget_stale(state, stale)

    cond do
      # A valid credential is given at once; inside the last minute it is renewed beside, and
      # nobody waits for that.
      valid?(state) ->
        state =
          if renew_due?(state) and is_nil(state.taking) and is_nil(recent_failure(state)),
            do: start_taking(state, []),
            else: state

        {:reply, {:ok, state.credential}, state}

      state.taking ->
        {:noreply, %{state | waiting: [from | state.waiting]}}

      failure = recent_failure(state) ->
        {:reply, failure, state}

      true ->
        {:noreply, start_taking(state, [from])}
    end
  end

  # The request runs in a process of its own, so callers wait for it and not for each other, and
  # its result comes back as its exit: one that crashes is an answer too.
  defp start_taking(state, waiting) do
    config = state.config
    {_pid, ref} = spawn_monitor(fn -> exit({:taken, take(config)}) end)
    %{state | taking: ref, waiting: waiting}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, {:taken, result}}, %{taking: ref} = state),
    do: {:noreply, taken(state, result)}

  def handle_info({:DOWN, ref, :process, _pid, _crashed}, %{taking: ref} = state),
    do: {:noreply, taken(state, {:error, :unavailable})}

  def handle_info(_message, state), do: {:noreply, state}

  # The bearer token and the key are never shown, a crash report's state included.
  @impl true
  def format_status(status) do
    status
    |> Map.update(:state, nil, fn
      %{credential: _} = state -> %{state | credential: state.credential && :redacted}
      other -> other
    end)
    |> Map.update(:message, nil, fn
      {:DOWN, ref, :process, pid, {:taken, {:ok, _token, expires_in}}} ->
        {:DOWN, ref, :process, pid, {:taken, {:ok, :redacted, expires_in}}}

      other ->
        other
    end)
  end

  defp forget_stale(%{credential: %{id: id}} = state, id), do: %{state | credential: nil}
  defp forget_stale(state, _stale), do: state

  defp valid?(state), do: state.credential != nil and state.expires_at > now()
  defp renew_due?(state), do: now() >= state.renew_at

  defp recent_failure(%{failed: {error, at}}) do
    if System.monotonic_time(:millisecond) - at < @failure_kept_ms, do: error
  end

  defp recent_failure(_state), do: nil

  defp taken(state, result) do
    {reply, state} =
      case result do
        {:ok, token, expires_in} ->
          credential = %{
            id: make_ref(),
            token: token,
            issuer: state.config.issuer,
            request_opts: state.config.request_opts
          }

          # Renewed a minute before it expires, or halfway for one that lives less than two.
          renew_in = max(expires_in - @renew_before_seconds, div(expires_in, 2))

          {{:ok, credential},
           %{
             state
             | credential: credential,
               expires_at: now() + expires_in,
               renew_at: now() + renew_in,
               failed: nil
           }}

        {:error, _reason} = error ->
          state = %{state | failed: {error, System.monotonic_time(:millisecond)}}

          # A renewal that fails keeps the credential while it is still valid.
          if state.credential && state.expires_at > now(),
            do: {{:ok, state.credential}, state},
            else: {error, %{state | credential: nil, expires_at: 0}}
      end

    for waiter <- state.waiting, do: GenServer.reply(waiter, reply)
    %{state | taking: nil, waiting: []}
  end

  # RFC 6749 §4.4 with RFC 7523's assertion, as EHOS accepts it: no scope, no resource.
  defp take(config) do
    form =
      URI.encode_query(%{
        "grant_type" => "client_credentials",
        "client_assertion_type" => @assertion_type,
        "client_assertion" => assertion(config)
      })

    request =
      {config.token_endpoint, [{"accept", "application/json"}],
       "application/x-www-form-urlencoded", form}

    case Http.request(:post, request, [timeout: @deadline], [], config.request_opts) do
      {:ok, {{_version, 200, _reason}, _headers, body}} ->
        case Jason.decode(body) do
          {:ok, %{"access_token" => token, "expires_in" => expires_in}}
          when is_binary(token) and is_integer(expires_in) and expires_in > 0 ->
            {:ok, token, expires_in}

          _other ->
            Logger.warning("EHOS's token endpoint answered no credential")
            {:error, :unavailable}
        end

      {:ok, {{_version, 429, _reason}, _headers, _body}} ->
        {:error, :rate_limited}

      {:ok, {{_version, status, _reason}, _headers, body}} ->
        token_refusal(status, body)

      {:error, reason} ->
        Logger.warning("EHOS's token endpoint could not be reached: #{inspect(reason)}")
        {:error, :unavailable}
    end
  end

  defp token_refusal(status, body) do
    error =
      case Jason.decode(body) do
        {:ok, %{"error" => error}} when is_binary(error) -> error
        _other -> nil
      end

    Logger.warning("EHOS refused the workload a credential: #{status} #{inspect(error)}")

    if error == "unauthorized_client", do: {:error, :not_asked}, else: {:error, :unavailable}
  end

  defp assertion(config),
    do: ClientKey.assertion(config.client_key, config.client_id, config.token_endpoint)

  # How long a credential lives is measured on a clock no adjustment moves.
  defp now, do: System.monotonic_time(:second)

  ## The configuration

  defp config!(opts) do
    all = Application.get_all_env(:eh_os_contract_auth)
    issuer = all[:issuer]

    if Address.check(issuer, plain_on_loopback: false, path: false) == :error do
      raise ArgumentError,
            "config :eh_os_contract_auth, issuer: is #{Address.shown(issuer)}, which is not " <>
              "https://<host>[:port] alone, the issuer EHOS's workload client calls"
    end

    {key, workload} = workload!(all)

    case Keyword.keys(workload) -- @keys do
      [] ->
        :ok

      extra ->
        raise ArgumentError,
              "config :eh_os_contract_auth, #{inspect(key)} does not take #{inspect(extra)}"
    end

    client_id = workload[:client_id]

    unless is_binary(client_id) and client_id != "" do
      raise ArgumentError,
            "config :eh_os_contract_auth, #{inspect(key)} needs client_id: a non-empty string"
    end

    file = workload[:client_key_file]

    unless is_binary(file) do
      raise ArgumentError,
            "config :eh_os_contract_auth, #{inspect(key)} needs client_key_file: a path"
    end

    %Config{
      issuer: issuer,
      token_endpoint: issuer <> "/oauth/token",
      client_id: client_id,
      client_key: ClientKey.load!(file),
      request_opts:
        opts
        |> Keyword.take([:cacertfile, :cacerts, :plug])
        |> Map.new()
        |> Map.merge(%{max_body: @max_body, own_query: true})
    }
  end

  # `:people` is the older name of `:workload`, from before the credential served mail.
  defp workload!(all) do
    case {all[:workload], all[:people]} do
      {nil, nil} ->
        raise ArgumentError,
              "config :eh_os_contract_auth, :workload is missing; it takes client_id: and " <>
                "client_key_file:, EHOS_CLIENT_ID and EHOS_CLIENT_KEY_FILE"

      {workload, nil} ->
        {:workload, keyword!(:workload, workload)}

      {nil, people} ->
        Logger.warning(
          "config :eh_os_contract_auth, :people is deprecated; name it :workload, the same " <>
            "configuration, which sending mail shares"
        )

        {:people, keyword!(:people, people)}

      {_workload, _people} ->
        raise ArgumentError,
              "config :eh_os_contract_auth sets both :workload and :people; keep :workload, " <>
                "the newer name of the same configuration"
    end
  end

  defp keyword!(key, value) do
    if Keyword.keyword?(value) and value != [] do
      value
    else
      raise ArgumentError,
            "config :eh_os_contract_auth, #{inspect(key)} is not a keyword list; it takes " <>
              "client_id: and client_key_file:, EHOS_CLIENT_ID and EHOS_CLIENT_KEY_FILE"
    end
  end
end

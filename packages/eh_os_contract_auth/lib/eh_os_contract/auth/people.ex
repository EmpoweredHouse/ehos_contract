defmodule EhOsContract.Auth.People do
  # `eh-os` D-81: the application reads the company's people as itself, with OAuth's client
  # credentials grant and `private_key_jwt`, while a people manager agrees; the people API is
  # `eh-os` `docs/people-api.md` (D-80); the client key's form D-68. Issue #252.
  @moduledoc """
  The company's people, as EHOS holds them, read by the application itself: for a form
  that offers an employee instead of a text field.

      # ehos.yaml
      schema: ehos.yaml/v3
      needs:
        people: read

      # config/runtime.exs
      config :eh_os_contract_auth,
        issuer: System.fetch_env!("EHOS_ISSUER"),
        people: [
          client_id: System.fetch_env!("EHOS_CLIENT_ID"),
          client_key_file: System.fetch_env!("EHOS_CLIENT_KEY_FILE")
        ]

      # the supervision tree
      children = [MyApp.Repo, EhOsContract, EhOsContract.Auth, EhOsContract.Auth.People]

      # anywhere
      {:ok, %{people: people, next: next}} = EhOsContract.Auth.People.list(q: "ad")
      {:ok, %{people: more, next: _}} = EhOsContract.Auth.People.list(after: next)
      {:ok, person} = EhOsContract.Auth.People.get(id)

  EHOS gives a workload whose `ehos.yaml/v3` asks `needs.people: read` its client id
  and key, whether or not it signs people in. Asking grants nothing: EHOS answers only
  once someone who manages people agrees, for that environment, and refuses from the
  next call after they withdraw.

  **A person** is an `EhOsContract.Auth.People.Person`: `id`, `email`, `name` (or nil)
  and `state`. Store the `id`: it never changes, and it is the `sub` sign-in gives for
  the same person. An email can change and be given to someone else later.

  **The credential.** The process takes one at EHOS's token endpoint,
  `<issuer>/oauth/token`, with the client credentials grant, signing an assertion with
  the client key, the first time it is needed; keeps it for its ten minutes; and takes
  another a minute before it expires, going on with the one it has while it is still
  valid if that fails. Callers that need one at the same time wait for one request.
  When EHOS refuses or cannot be reached, the next five seconds' callers are answered
  the same without asking it again. A call EHOS answers 401, as after its keys rotate,
  takes a new credential and is tried once more. Nothing is fetched at start, so the
  host starts while EHOS is down.

  **What a call answers when it does not answer people**, each an `{:error, reason}`
  a page can say in words:

    * `:not_agreed`: EHOS refuses the reading. No people manager has agreed for this
      environment, or the agreement was withdrawn, or the deployment no longer asks;
    * `:not_found`: `get/2` of an id that is no one's;
    * `:not_asked`: EHOS refuses the client the grant: its deployment does not ask
      `needs.people: read`;
    * `:rate_limited`: EHOS's limit on the token endpoint or the people API;
    * `:unavailable`: EHOS cannot be reached, fails, or answers what it never answers.
      The rest of the application goes on; only the list waits for EHOS, which keeps
      no copy of the people in the application.

  A call never raises or exits for what EHOS does, the process not running included.

  Each request to EHOS goes over https, follows no redirect, reads at most 1 MiB and
  ends after ten seconds, as sign-in's do; EHOS's certificate is checked against the
  system's authorities, or `cacertfile:` / `cacerts:` given to the child. A call makes
  at most two requests for the people and waits for at most two credentials, so it
  answers within about forty seconds when EHOS hangs, and at once when it refuses.

  **What is checked at boot.** `child_spec/1` raises when `config :eh_os_contract_auth,
  :people` is missing, is not a keyword list or has a key it does not take, when the
  issuer is not `https://<host>[:port]`, when `client_id` is not a non-empty string, or
  when the client key file is not the one Ed25519 JWK EHOS gives. Nothing secret
  appears in what it raises.
  """

  use GenServer

  require Logger

  alias EhOsContract.Auth.Address
  alias EhOsContract.Auth.People.{Config, Person}
  alias EhOsContract.Auth.SignIn.{ClientKey, Http}

  @keys [:client_id, :client_key_file]
  @assertion_type "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"
  @deadline 10_000
  # How long a caller waits for a credential: the token request's deadline, and a margin.
  @credential_wait @deadline + 2_000
  # A page of 500 people, EHOS's largest, with long names and addresses.
  @max_body 1024 * 1024
  # A credential is taken again this long before it expires, so one is never sent expired.
  @renew_before_seconds 60
  # How long a refusal or an outage of the token endpoint is answered without asking again.
  @failure_kept_ms 5_000
  # EHOS keeps an assertion's `jti` until it expires: a minute is enough for one request.
  @assertion_lifetime_seconds 60
  # EHOS's bound on `q`, in bytes (`eh-os` `docs/people-api.md`).
  @max_q_bytes 2048
  # EHOS lists the invited and the joined to an application; the disabled only to a manager.
  @states ~w(invited joined)a
  # The parameters EHOS's next page keeps from the request, which a cursor carries.
  @page_params ~w(q state limit after)
  # EHOS's ids are UUIDs: anything else is no one's, and is not sent.
  @id ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/

  @typedoc "Why a call answered no people."
  @type reason :: :not_agreed | :not_found | :not_asked | :rate_limited | :unavailable

  @typedoc """
  What `list/1` asks for, each optional: `q`, a prefix of the name or the email, at most
  2048 bytes; `state`, `:invited`, `:joined` or both (the default); `limit`, from 1 to 500
  (100 by default). Or `after:` alone, the `next` of the page before, which carries the
  rest. EHOS never lists the disabled to an application.
  """
  @type list_option ::
          {:q, String.t()}
          | {:state, :invited | :joined | [:invited | :joined]}
          | {:limit, 1..500}
          | {:after, String.t()}
          | {:server, GenServer.server()}

  @doc false
  def child_spec(opts) do
    opts = Keyword.put_new(opts, :name, __MODULE__)
    config = config!(opts)

    %{
      id: opts[:name],
      start: {GenServer, :start_link, [__MODULE__, config, [name: opts[:name]]]}
    }
  end

  @doc """
  One page of the people, in the order of their email, and the cursor of the next page,
  `nil` on the last. The cursor carries the page's `q`, `state` and `limit`: ask for the
  next page with `after:` alone.

  Raises `ArgumentError` for an option it does not take, as documented in
  `t:list_option/0`.
  """
  @spec list([list_option()]) ::
          {:ok, %{people: [Person.t()], next: String.t() | nil}} | {:error, reason()}
  def list(opts \\ []) do
    {server, opts} = Keyword.pop(opts, :server, __MODULE__)
    query = query!(opts)

    with {:ok, body, headers} <- call(server, "/api/people?" <> URI.encode_query(query)),
         {:ok, people} <- people(body) do
      {:ok, %{people: people, next: next(headers)}}
    end
  end

  @doc "The person `id` names, a disabled one included."
  @spec get(String.t(), [{:server, GenServer.server()}]) ::
          {:ok, Person.t()} | {:error, reason()}
  def get(id, opts \\ []) when is_binary(id) do
    server = Keyword.get(opts, :server, __MODULE__)
    id = String.downcase(id)

    with true <- id =~ @id || {:error, :not_found},
         {:ok, body, _headers} <- call(server, "/api/people/" <> id),
         %{"person" => person} <- body,
         {:ok, person} <- Person.from_map(person) do
      {:ok, person}
    else
      {:error, reason} -> {:error, reason}
      _other -> {:error, :unavailable}
    end
  end

  ## The calls

  # A credential, the call, and once more with a new credential when EHOS answers 401.
  defp call(server, path) do
    with {:ok, credential} <- credential(server, nil) do
      case get_json(credential, path) do
        {:error, :unauthorized} ->
          with {:ok, renewed} <- credential(server, credential.id) do
            case get_json(renewed, path) do
              {:error, :unauthorized} -> {:error, :unavailable}
              answer -> answer
            end
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
      Logger.warning("EhOsContract.Auth.People gave no credential: #{exit_reason(reason)}")
      {:error, :unavailable}
  end

  defp exit_reason({:timeout, _call}), do: "it took too long"
  defp exit_reason({:noproc, _call}), do: "it is not running"
  defp exit_reason(_reason), do: "it exited"

  defp get_json(credential, path) do
    headers = [{"authorization", "Bearer " <> credential.token}, {"accept", "application/json"}]
    request = {credential.issuer <> path, headers}

    case Http.request(:get, request, [timeout: @deadline], [], credential.request_opts) do
      {:ok, {{_version, 200, _reason}, headers, body}} ->
        case Jason.decode(body) do
          {:ok, json} when is_map(json) -> {:ok, json, headers}
          _other -> unexpected("an answer that is not a JSON object")
        end

      {:ok, {{_version, status, _reason}, _headers, _body}} ->
        refusal(status)

      {:error, reason} ->
        Logger.warning("EHOS's people API could not be reached: #{inspect(reason)}")
        {:error, :unavailable}
    end
  end

  defp refusal(401), do: {:error, :unauthorized}
  defp refusal(403), do: {:error, :not_agreed}
  defp refusal(404), do: {:error, :not_found}
  defp refusal(429), do: {:error, :rate_limited}
  defp refusal(status), do: unexpected("status #{status}")

  defp unexpected(what) do
    Logger.warning("EHOS's people API answered #{what}")
    {:error, :unavailable}
  end

  defp query!(after: cursor) when is_binary(cursor) do
    with {:ok, query} <- Base.url_decode64(cursor, padding: false),
         params = URI.decode_query(query),
         true <- Map.keys(params) -- @page_params == [] do
      Enum.sort(params)
    else
      _bad -> raise ArgumentError, "after: takes the next of a page list/1 answered"
    end
  end

  defp query!(opts) do
    Enum.map(opts, fn
      {:q, q} when is_binary(q) and byte_size(q) <= @max_q_bytes ->
        {"q", q}

      {:state, states} when states != [] ->
        states = List.wrap(states)

        if Enum.all?(states, &(&1 in @states)),
          do: {"state", Enum.join(states, ",")},
          else: bad!()

      {:limit, limit} when is_integer(limit) and limit in 1..500 ->
        {"limit", Integer.to_string(limit)}

      _other ->
        bad!()
    end)
  end

  defp bad!,
    do:
      raise(
        ArgumentError,
        "list/1 takes q: (at most #{@max_q_bytes} bytes), state: (:invited, :joined), " <>
          "limit: (1..500), or after: alone"
      )

  defp people(%{"people" => people}) when is_list(people) do
    people
    |> Enum.reduce_while([], fn person, acc ->
      case Person.from_map(person) do
        {:ok, person} -> {:cont, [person | acc]}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      :error -> unexpected("a person it never writes")
      people -> {:ok, Enum.reverse(people)}
    end
  end

  defp people(_body), do: unexpected("no people")

  # EHOS's `Link: <…?q=…&after=…>; rel="next"`: its query, the page's parameters and the
  # cursor, becomes the next cursor. The address is never followed: the issuer's is rebuilt
  # from the configuration.
  defp next(headers) do
    with {_name, value} <-
           Enum.find(headers, fn {name, _value} -> String.downcase(to_string(name)) == "link" end),
         [_all, url] <- Regex.run(~r/<([^>]*)>\s*;\s*rel="next"/, to_string(value)),
         %URI{query: query} when is_binary(query) <- URI.parse(url),
         params = Map.take(URI.decode_query(query), @page_params),
         true <- Map.has_key?(params, "after") do
      params |> URI.encode_query() |> Base.url_encode64(padding: false)
    else
      _none -> nil
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
       taking: nil,
       waiting: [],
       failed: nil
     }}
  end

  @impl true
  def handle_call({:credential, stale}, from, state) do
    state = forget_stale(state, stale)

    cond do
      fresh?(state) ->
        {:reply, {:ok, state.credential}, state}

      state.taking ->
        {:noreply, %{state | waiting: [from | state.waiting]}}

      failure = recent_failure(state) ->
        {:reply, failure, state}

      true ->
        # The request runs in a process of its own, so callers wait for it and not for each other,
        # and its result comes back as its exit: one that crashes is an answer too.
        config = state.config
        {_pid, ref} = spawn_monitor(fn -> exit({:taken, take(config)}) end)
        {:noreply, %{state | taking: ref, waiting: [from]}}
    end
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
    Map.update(status, :state, nil, fn
      %{credential: _} = state -> %{state | credential: state.credential && :redacted}
      other -> other
    end)
  end

  defp forget_stale(%{credential: %{id: id}} = state, id), do: %{state | credential: nil}
  defp forget_stale(state, _stale), do: state

  defp fresh?(state),
    do: state.credential != nil and state.expires_at - now() > @renew_before_seconds

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

          {{:ok, credential},
           %{state | credential: credential, expires_at: now() + expires_in, failed: nil}}

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

  # RFC 6749 §4.4 with RFC 7523's assertion, as `eh-os` D-81 accepts it: no scope, no resource.
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

    Logger.warning("EHOS refused the people client a credential: #{status} #{inspect(error)}")

    if error == "unauthorized_client", do: {:error, :not_asked}, else: {:error, :unavailable}
  end

  defp assertion(config) do
    issued_at = System.os_time(:second)

    claims = %{
      "iss" => config.client_id,
      "sub" => config.client_id,
      "aud" => config.token_endpoint,
      "jti" => Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false),
      "iat" => issued_at,
      "exp" => issued_at + @assertion_lifetime_seconds
    }

    %{"kid" => kid} = config.client_key.fields

    {_modules, token} =
      config.client_key
      |> JOSE.JWT.sign(%{"alg" => "Ed25519", "kid" => kid}, claims)
      |> JOSE.JWS.compact()

    token
  end

  # How long a credential lives is measured on a clock no adjustment moves.
  defp now, do: System.monotonic_time(:second)

  ## The configuration

  defp config!(opts) do
    all = Application.get_all_env(:eh_os_contract_auth)
    issuer = all[:issuer]

    if Address.check(issuer, plain_on_loopback: false, path: false) == :error do
      raise ArgumentError,
            "config :eh_os_contract_auth, issuer: is #{Address.shown(issuer)}, which is not " <>
              "https://<host>[:port] alone, the issuer EHOS's people client calls"
    end

    people = all[:people]

    unless Keyword.keyword?(people) and people != [] do
      raise ArgumentError,
            "config :eh_os_contract_auth, :people is missing or not a keyword list; it takes " <>
              "client_id: and client_key_file:, EHOS_CLIENT_ID and EHOS_CLIENT_KEY_FILE"
    end

    case Keyword.keys(people) -- @keys do
      [] ->
        :ok

      extra ->
        raise ArgumentError,
              "config :eh_os_contract_auth, :people does not take #{inspect(extra)}"
    end

    client_id = people[:client_id]

    unless is_binary(client_id) and client_id != "" do
      raise ArgumentError,
            "config :eh_os_contract_auth, :people needs client_id: a non-empty string"
    end

    file = people[:client_key_file]

    unless is_binary(file) do
      raise ArgumentError, "config :eh_os_contract_auth, :people needs client_key_file: a path"
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
end

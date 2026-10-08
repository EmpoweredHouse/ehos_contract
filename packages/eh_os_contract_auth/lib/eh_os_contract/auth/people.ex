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
      {:ok, person} = EhOsContract.Auth.People.get(id)

  EHOS gives a workload whose `ehos.yaml/v3` asks `needs.people: read` its client id
  and key, whether or not it signs people in. Asking grants
  nothing: EHOS answers only once someone who manages people agrees, for that
  environment, and refuses from the next call after they withdraw.

  **A person** is an `EhOsContract.Auth.People.Person`: `id`, `email`, `name` (or nil)
  and `state`. Store the `id`: it never changes, and it is the `sub` sign-in gives for
  the same person. An email can change and be given to someone else later.

  **The credential.** The process takes one at EHOS's token endpoint,
  `<issuer>/oauth/token`, with the client credentials grant, signing an assertion with
  the client key, the first time it is needed; keeps it for its ten minutes; and takes
  another a minute before it expires. A call EHOS answers 401, as after its keys
  rotate, takes a new one and is tried once more. Nothing is fetched at start, so the
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

  Every call to EHOS goes over https, follows no redirect, reads at most 1 MiB and ends
  after ten seconds, as sign-in's do; EHOS's certificate is checked against the system's
  authorities, or `cacertfile:` / `cacerts:` given to the child.

  **What is checked at boot.** `child_spec/1` raises when `config :eh_os_contract_auth,
  :people` is missing, is not a keyword list or has a key it does not take, when the
  issuer is not `https://<host>[:port]`, when `client_id` is not a non-empty string, or
  when the client key file is not the one Ed25519 JWK EHOS gives. Nothing
  secret appears in what it raises.
  """

  use GenServer

  require Logger

  alias EhOsContract.Auth.Address
  alias EhOsContract.Auth.People.{Config, Person}
  alias EhOsContract.Auth.SignIn.{ClientKey, Http}

  @keys [:client_id, :client_key_file]
  @assertion_type "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"
  @deadline 10_000
  # A page of 500 people, EHOS's largest, with long names and addresses.
  @max_body 1024 * 1024
  # A credential is taken again this long before it expires, so one is never sent expired.
  @renew_before_seconds 60
  # EHOS keeps an assertion's `jti` until it expires: a minute is enough for one request.
  @assertion_lifetime_seconds 60
  @states ~w(invited joined disabled)a

  @typedoc "Why a call answered no people."
  @type reason :: :not_agreed | :not_found | :not_asked | :rate_limited | :unavailable

  @typedoc """
  What `list/2` asks for, each optional: `q`, a prefix of the name or the email; `state`,
  one or more of `:invited`, `:joined` (both by default) and `:disabled`, which EHOS
  never lists to an application; `limit`, from 1 to 500 (100 by default); `after`, the
  `next` of the page before.
  """
  @type list_option ::
          {:q, String.t()}
          | {:state, atom() | [atom()]}
          | {:limit, pos_integer()}
          | {:after, String.t()}
          | {:server, GenServer.server()}

  @doc false
  def child_spec(opts) do
    opts = Keyword.put_new(opts, :name, __MODULE__)
    config = config!(opts)
    %{id: opts[:name], start: {GenServer, :start_link, [__MODULE__, config, [name: opts[:name]]]}}
  end

  @doc """
  One page of the people, in the order of their email, and the cursor of the next page,
  `nil` on the last. Give that cursor back as `after:` for the next page.
  """
  @spec list([list_option()]) ::
          {:ok, %{people: [Person.t()], next: String.t() | nil}} | {:error, reason()}
  def list(opts \\ []) do
    {server, opts} = Keyword.pop(opts, :server, __MODULE__)

    with {:ok, query} <- query(opts),
         {:ok, body, headers} <- call(server, "/api/people?" <> URI.encode_query(query)),
         {:ok, people} <- people(body) do
      {:ok, %{people: people, next: next(headers)}}
    end
  end

  @doc "The person `id` names, a disabled one included."
  @spec get(String.t(), [{:server, GenServer.server()}]) ::
          {:ok, Person.t()} | {:error, reason()}
  def get(id, opts \\ []) when is_binary(id) do
    server = Keyword.get(opts, :server, __MODULE__)

    with {:ok, body, _headers} <-
           call(server, "/api/people/" <> URI.encode(id, &URI.char_unreserved?/1)),
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
    with {:ok, token, config} <- credential(server) do
      case get_json(config, path, token) do
        {:error, :unauthorized} ->
          with {:ok, token, config} <- credential(server, token) do
            case get_json(config, path, token) do
              {:error, :unauthorized} -> {:error, :unavailable}
              answer -> answer
            end
          end

        answer ->
          answer
      end
    end
  end

  defp credential(server, stale \\ nil),
    do: GenServer.call(server, {:credential, stale}, @deadline * 2)

  defp get_json(config, path, token) do
    request =
      {config.issuer <> path,
       [{"authorization", "Bearer " <> token}, {"accept", "application/json"}]}

    case Http.request(:get, request, [timeout: @deadline], [], config.request_opts) do
      {:ok, {{_version, 200, _reason}, headers, body}} ->
        case Jason.decode(body) do
          {:ok, json} when is_map(json) -> {:ok, json, headers}
          _other -> {:error, :unavailable}
        end

      {:ok, {{_version, status, _reason}, _headers, _body}} ->
        {:error, refusal(status)}

      {:error, reason} ->
        Logger.warning("EHOS's people API could not be reached: #{inspect(reason)}")
        {:error, :unavailable}
    end
  end

  defp refusal(401), do: :unauthorized
  defp refusal(403), do: :not_agreed
  defp refusal(404), do: :not_found
  defp refusal(429), do: :rate_limited
  defp refusal(_status), do: :unavailable

  defp query(opts) do
    Enum.reduce_while(opts, {:ok, []}, fn
      {:q, q}, {:ok, query} when is_binary(q) ->
        {:cont, {:ok, [{"q", q} | query]}}

      {:state, states}, {:ok, query} ->
        states = List.wrap(states)

        if states != [] and Enum.all?(states, &(&1 in @states)),
          do: {:cont, {:ok, [{"state", Enum.join(states, ",")} | query]}},
          else: {:halt, :bad}

      {:limit, limit}, {:ok, query} when is_integer(limit) and limit in 1..500 ->
        {:cont, {:ok, [{"limit", Integer.to_string(limit)} | query]}}

      {:after, cursor}, {:ok, query} when is_binary(cursor) ->
        {:cont, {:ok, [{"after", cursor} | query]}}

      _other, _query ->
        {:halt, :bad}
    end)
    |> case do
      {:ok, query} ->
        {:ok, Enum.reverse(query)}

      :bad ->
        raise ArgumentError, "list/1 takes q:, state:, limit: (1..500) and after:, as documented"
    end
  end

  defp people(%{"people" => people}) when is_list(people) do
    Enum.reduce_while(people, {:ok, []}, fn person, {:ok, acc} ->
      case Person.from_map(person) do
        {:ok, person} -> {:cont, {:ok, [person | acc]}}
        :error -> {:halt, {:error, :unavailable}}
      end
    end)
    |> case do
      {:ok, people} -> {:ok, Enum.reverse(people)}
      error -> error
    end
  end

  defp people(_body), do: {:error, :unavailable}

  # EHOS's `Link: <…?…&after=…>; rel="next"`: only its cursor is kept, never the address, which
  # is the issuer's and is rebuilt from the configuration.
  defp next(headers) do
    with {_name, value} <-
           Enum.find(headers, fn {name, _value} -> to_string(name) =~ ~r/\Alink\z/i end),
         [_all, url] <- Regex.run(~r/<([^>]*)>\s*;\s*rel="next"/, to_string(value)),
         %URI{query: query} when is_binary(query) <- URI.parse(url),
         %{"after" => cursor} <- URI.decode_query(query) do
      cursor
    else
      _none -> nil
    end
  end

  ## The process

  @impl true
  def init(config), do: {:ok, %{config: config, token: nil, expires_at: 0}}

  @impl true
  def handle_call({:credential, stale}, _from, state) do
    state = if stale && stale == state.token, do: %{state | token: nil}, else: state

    if state.token && state.expires_at - now() > @renew_before_seconds do
      {:reply, {:ok, state.token, state.config}, state}
    else
      case take(state.config) do
        {:ok, token, expires_in} ->
          state = %{state | token: token, expires_at: now() + expires_in}
          {:reply, {:ok, token, state.config}, state}

        {:error, reason} ->
          {:reply, {:error, reason}, %{state | token: nil, expires_at: 0}}
      end
    end
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
        {:ok, %{"error" => error}} -> error
        _other -> nil
      end

    Logger.warning("EHOS refused the people client a credential: #{status} #{inspect(error)}")

    if error == "unauthorized_client", do: {:error, :not_asked}, else: {:error, :unavailable}
  end

  defp assertion(config) do
    issued_at = now()

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

  defp now, do: System.os_time(:second)

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
              "client_id: and client_key_file:, EHOS_CLIENT_ID and EHOS_CLIENT_KEY_FILE (eh-os D-81)"
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

defmodule EhOsContract.Auth.People do
  # As agreed with EHOS: the application reads the company's people as itself, with OAuth's
  # client credentials grant and `private_key_jwt`, while a people manager agrees. The people API
  # and the client key's form are EHOS's. Issue #252.
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
        workload: [
          client_id: System.fetch_env!("EHOS_CLIENT_ID"),
          client_key_file: System.fetch_env!("EHOS_CLIENT_KEY_FILE")
        ]

      # the supervision tree
      children = [MyApp.Repo, EhOsContract, EhOsContract.Auth, EhOsContract.Auth.Workload]

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

  **The credential** is the application's own, which `EhOsContract.Auth.Workload`
  takes, keeps and renews; its moduledoc says how. `EhOsContract.Auth.People` as a child,
  with `config :eh_os_contract_auth, :people`, are that process's older names, and still
  start it.

  **What a call answers when it does not answer people**, each an `{:error, reason}`
  a page can say in words:

    * `:not_agreed`: EHOS refuses the reading. No people manager has agreed for this
      environment, or the agreement was withdrawn, or the deployment no longer asks;
    * `:not_found`: `get/2` of an id that is no one's;
    * `:not_asked`: EHOS refuses the client the grant: its deployment asks for neither
      the people nor mail. One that asks for mail alone is `:not_agreed`;
    * `:rate_limited`: EHOS's limit on the token endpoint or the people API;
    * `:unavailable`: EHOS cannot be reached, fails, or answers what it never answers.
      The rest of the application goes on; only the list waits for EHOS, which keeps
      no copy of the people in the application.

  A call never raises or exits for what EHOS does, the process not running included.

  Each request to EHOS reads at most 1 MiB and ends after ten seconds, as sign-in's do.
  A call makes at most two requests for the people and waits for at most two
  credentials, so it answers within about forty seconds when EHOS hangs, and at once
  when it refuses.
  """

  require Logger

  alias EhOsContract.Auth.People.Person
  alias EhOsContract.Auth.Workload

  @deadline 10_000
  # EHOS's bound on `q`, in bytes, as its people API documents it.
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
  # The older name of `EhOsContract.Auth.Workload` as a child, from before it served mail.
  def child_spec(opts), do: Workload.child_spec(opts)

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
    {server, opts} = Keyword.pop(opts, :server, Workload)
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
    server = Keyword.get(opts, :server, Workload)
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

  defp call(server, path) do
    case Workload.request(server, :get, path, nil, @deadline) do
      {:ok, {200, headers, body}} ->
        case Jason.decode(body) do
          {:ok, json} when is_map(json) -> {:ok, json, headers}
          _other -> unexpected("an answer that is not a JSON object")
        end

      {:ok, {status, _headers, _body}} ->
        refusal(status)

      {:error, {:unreachable, reason}} ->
        Logger.warning("EHOS's people API could not be reached: #{inspect(reason)}")
        {:error, :unavailable}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # A second 401 is EHOS refusing a credential it has just given: an answer it never gives.
  defp refusal(403), do: {:error, :not_agreed}
  defp refusal(404), do: {:error, :not_found}
  defp refusal(429), do: {:error, :rate_limited}
  defp refusal(status), do: unexpected("status #{status}")

  defp unexpected(what) do
    Logger.warning("EHOS's people API answered #{what}")
    {:error, :unavailable}
  end

  # A cursor is a value a page may have handed a browser: what it carries is held to the same
  # rules as the options, and it must carry EHOS's `after`.
  defp query!(after: cursor) when is_binary(cursor) do
    with {:ok, query} <- Base.url_decode64(cursor, padding: false),
         params = URI.decode_query(query),
         true <- Map.keys(params) -- @page_params == [],
         {after_key, params} when is_binary(after_key) and after_key != "" <-
           Map.pop(params, "after"),
         {:ok, opts} <- cursor_opts(params) do
      [{"after", after_key} | query!(opts)]
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

  defp cursor_opts(params) do
    Enum.reduce_while(params, {:ok, []}, fn
      {"q", q}, {:ok, opts} ->
        {:cont, {:ok, [{:q, q} | opts]}}

      {"state", states}, {:ok, opts} ->
        named =
          for name <- String.split(states, ","), state <- @states, "#{state}" == name, do: state

        if length(named) == length(String.split(states, ",")),
          do: {:cont, {:ok, [{:state, named} | opts]}},
          else: {:halt, :error}

      {"limit", limit}, {:ok, opts} ->
        case Integer.parse(limit) do
          {limit, ""} -> {:cont, {:ok, [{:limit, limit} | opts]}}
          _other -> {:halt, :error}
        end
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
end

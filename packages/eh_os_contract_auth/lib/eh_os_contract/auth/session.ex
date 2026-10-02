defmodule EhOsContract.Auth.Session do
  @moduledoc """
  A person signed in through EHOS (`EhOsContract.Auth.SignIn.Router`), for the pages
  that need one: a plug, and `actor/2` for a controller or a LiveView (S7 in
  docs/adr/browser-session.md).

      # in the host's router
      pipeline :signed_in do
        plug EhOsContract.Auth.Session
      end

      # a controller; a LiveView passes the session map `mount/3` is given
      {:ok, actor} = EhOsContract.Auth.Session.actor(conn)

  **The plug.** A request whose session names a person signed in goes on with
  `conn.assigns.eh_os_contract_session`: their `subject`, `sid` and `auth_time`, and
  nothing of EHOS's tokens. With `assign_actor: true`, the plug also sets
  `conn.assigns.eh_os_contract_actor`, as `EhOsContract.Auth.Plug` does for a bearer
  token, so a pipeline that forwards to `EhOsContract.Plug` serves the person.

  **When it stops a request.** A browser's navigation (`GET` or `HEAD` with
  `sec-fetch-mode: navigate`, or one that accepts `text/html`) without a session, or
  whose credential has expired, is redirected to sign in and come back
  (`sign_in_path:`, `/auth/ehos/sign-in` by default). Any other such request, a
  `fetch()` from a page for one, answers 401: a redirect would take it to EHOS, across
  origins. A credential `verify/2` refuses for any other reason answers 401 and is
  logged: signing in again would get the same credential, and the browser would go
  round EHOS for ever.

  **The actor.** `actor/2` is the actor of the person's credential for this
  application, verified by `EhOsContract.Auth.verify/2` against its own audience
  (S8), as a bearer credential is: the person is never read from the session's row's
  plain columns. Until renewal comes (EB3), a credential past its expiry gives
  `{:error, :expired}`.

  Both take `sign_in:`, the name of the `EhOsContract.Auth.SignIn` child, and
  `verify/2`'s `:keys`, `:audience` and `:issuer`.
  """

  @behaviour Plug

  import Plug.Conn

  require Logger

  alias EhOsContract.Actor
  alias EhOsContract.Auth.SignIn
  alias EhOsContract.Auth.SignIn.Sessions

  @session_key "eh_os_contract_auth_session"
  @verify_opts [:keys, :audience, :issuer]

  @typedoc "Why there is no actor."
  @type refusal :: :signed_out | EhOsContract.Auth.reason()

  @doc "The key under which the Plug session holds the token naming the person's session."
  @spec session_key() :: String.t()
  def session_key, do: @session_key

  @doc "Keeps the plug's options, and raises on any other: a misspelt one would be ignored."
  @impl Plug
  @spec init(keyword()) :: keyword()
  def init(opts) do
    Keyword.validate!(
      opts,
      [sign_in: SignIn, sign_in_path: "/auth/ehos/sign-in", assign_actor: false] ++ @verify_opts
    )
  end

  @doc "Lets a signed-in person's request through, or sends them to sign in."
  @impl Plug
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, opts) do
    conn = fetch_session(conn)

    with {:ok, session} <- Sessions.fetch(opts[:sign_in], get_session(conn, @session_key)),
         conn =
           assign(conn, :eh_os_contract_session, Map.take(session, [:subject, :sid, :auth_time])),
         {:ok, conn} <- maybe_actor(conn, session, opts) do
      conn
    else
      {:error, reason} when reason in [:signed_out, :expired] ->
        not_signed_in(conn, opts)

      {:error, reason} ->
        Logger.warning("eh_os_contract_auth refused a signed-in person's credential: #{reason}")
        refuse(conn)
    end
  end

  @doc """
  The actor of the person `session` names: a `Plug.Conn` with its session fetched, or
  the session map a LiveView's `mount/3` is given. `{:error, :signed_out}` when it
  names nobody, `{:error, :expired}` when the credential has expired, and
  `verify/2`'s refusal otherwise. On a connection the plug has already given an actor
  (`assign_actor: true`), that actor, without reading the session again.
  """
  @spec actor(Plug.Conn.t() | map(), keyword()) :: {:ok, Actor.t()} | {:error, refusal()}
  def actor(session, opts \\ [])

  def actor(%Plug.Conn{assigns: %{eh_os_contract_actor: %Actor{} = actor}}, _opts),
    do: {:ok, actor}

  def actor(%Plug.Conn{} = conn, opts), do: actor(get_session(conn), opts)

  def actor(session, opts) when is_map(session) do
    name = Keyword.get(opts, :sign_in, SignIn)

    with {:ok, row} <- Sessions.fetch(name, Map.get(session, @session_key)) do
      verified(row, name, opts)
    end
  end

  defp maybe_actor(conn, session, opts) do
    if opts[:assign_actor] do
      with {:ok, actor} <- verified(session, opts[:sign_in], opts) do
        {:ok, assign(conn, :eh_os_contract_actor, actor)}
      end
    else
      {:ok, conn}
    end
  end

  defp verified(session, name, opts) do
    address = SignIn.config(name).address

    # `verify/2` refuses a credential past its `exp` by `EhOsContract.Clock`, so the row's
    # `expires_at` is not read here; renewal (EB3) reads it, ahead of the expiry.
    case Map.get(session.credentials, address) do
      %{token: token} when is_binary(token) ->
        EhOsContract.Auth.verify(token, opts |> Keyword.take(@verify_opts) |> drop_nil())

      _none ->
        {:error, :signed_out}
    end
  end

  defp drop_nil(opts), do: Enum.reject(opts, fn {_key, value} -> is_nil(value) end)

  defp not_signed_in(conn, opts) do
    if navigation?(conn), do: to_sign_in(conn, opts), else: refuse(conn)
  end

  defp navigation?(%Plug.Conn{method: method} = conn) when method in ["GET", "HEAD"] do
    get_req_header(conn, "sec-fetch-mode") == ["navigate"] or
      Enum.any?(get_req_header(conn, "accept"), &String.contains?(&1, "text/html"))
  end

  defp navigation?(_conn), do: false

  defp to_sign_in(conn, opts) do
    return_to =
      if conn.query_string == "",
        do: conn.request_path,
        else: conn.request_path <> "?" <> conn.query_string

    location = opts[:sign_in_path] <> "?" <> URI.encode_query(%{"return_to" => return_to})

    conn
    |> put_resp_header("location", location)
    |> send_resp(302, "")
    |> halt()
  end

  defp refuse(conn) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(401, "Sign in through EHOS first.")
    |> halt()
  end
end

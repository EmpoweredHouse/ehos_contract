defmodule EhOsContract.Auth.Session do
  # The design is docs/adr/browser-session.md: this module is S7; the actor verified as a bearer
  # credential is S8; one renewal per session S4, its timing S10; the browser kept from EHOS's
  # tokens S2. Another application's credential, with its address as `resource`, as EHOS takes it.
  @moduledoc """
  A person signed in through EHOS (`EhOsContract.Auth.SignIn.Router`), for the pages
  that need one: a plug, `actor/2` for a controller or a LiveView, and `credential/3`
  for calling another application as the person.

      # in the host's router
      pipeline :signed_in do
        plug EhOsContract.Auth.Session
      end

      # a controller; a LiveView passes the session map `mount/3` is given
      {:ok, actor} = EhOsContract.Auth.Session.actor(conn)

      # another application, by its name in `sign_in: [applications: ...]`
      {:ok, token} = EhOsContract.Auth.Session.credential(conn, "ledger")

  **The plug.** A request whose session names a person signed in goes on with
  `conn.assigns.eh_os_contract_session`: their `subject`, `sid` and `auth_time`, and
  nothing of EHOS's tokens. With `assign_actor: true`, the plug also sets
  `conn.assigns.eh_os_contract_actor`, as `EhOsContract.Auth.Plug` does for a bearer
  token, so a pipeline that forwards to `EhOsContract.Plug` serves the person.

  **When it stops a request.** A browser's navigation (`GET` or `HEAD` with
  `sec-fetch-mode: navigate`, or one that accepts `text/html`) without a session, or
  whose sign-in has ended (at EHOS, or at renewal), is redirected to sign in and come back
  (`sign_in_path:`, `/auth/ehos/sign-in` by default). Any other such request, a
  `fetch()` from a page for one, answers 401: a redirect would take it to EHOS, across
  origins. A credential `verify/2` refuses for any other reason answers 401 and is
  logged: signing in again would get the same credential, and the browser would go
  round EHOS for ever. While EHOS cannot renew an expired credential, or another
  request of the session is renewing past 15 seconds, the request answers 503.

  **The actor.** `actor/2` is the actor of the person's credential for this
  application, verified by `EhOsContract.Auth.verify/2` against its own audience,
  as a bearer credential is: the person is never read from the session's row's
  plain columns. A credential about to expire is renewed first, through EHOS, with
  the session's refresh token; renewing is the only thing these two
  functions do beyond reading, and nothing renews without a request asking.

  **Another application's credential.** `credential/3` is the credential EHOS issues
  the person for an application named in `sign_in: [applications: ...]`, renewed the
  same way, with that application's address as `resource`. It is
  handed out as EHOS issued it, to be sent to that application as a bearer token, which
  verifies it: its `aud` is that application's, not this one's.

  Both take `sign_in:`, the name of the `EhOsContract.Auth.SignIn` child; `actor/2`
  also `verify/2`'s `:keys`, `:audience` and `:issuer`.
  """

  @behaviour Plug

  import Plug.Conn

  require Logger

  alias EhOsContract.Actor
  alias EhOsContract.Auth.SignIn
  alias EhOsContract.Auth.SignIn.{Renewal, Sessions}

  @session_key "eh_os_contract_auth_session"
  @verify_opts [:keys, :audience, :issuer]

  @typedoc "Why there is no credential: `credential/3`'s refusals."
  @type credential_refusal :: :signed_out | :ehos_unavailable | :renewal_busy | :refused

  @typedoc "Why there is no actor."
  @type refusal :: credential_refusal() | EhOsContract.Auth.reason()

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

      # Signing in again would not help: EHOS is down, or another request of this session is
      # renewing and did not finish in time.
      {:error, reason} when reason in [:ehos_unavailable, :renewal_busy] ->
        Logger.warning(
          "eh_os_contract_auth could not renew a signed-in person's credential: #{reason}"
        )

        unavailable(conn)

      {:error, reason} ->
        Logger.warning("eh_os_contract_auth refused a signed-in person's credential: #{reason}")
        refuse(conn)
    end
  end

  @doc """
  The actor of the person `session` names: a `Plug.Conn` with its session fetched, or
  the session map a LiveView's `mount/3` is given. A credential good for less than 30
  seconds is renewed first, once for the session however many requests ask at
  once. `{:error, :signed_out}` when the session names nobody or ended at
  renewal, `{:error, :ehos_unavailable}` when EHOS cannot renew an expired one,
  `{:error, :renewal_busy}` when another request's renewal did not finish within
  15 seconds, and `verify/2`'s refusal otherwise. On a connection the plug has already given an actor
  (`assign_actor: true`), that actor, without reading the session again.
  """
  @spec actor(Plug.Conn.t() | map(), keyword()) :: {:ok, Actor.t()} | {:error, refusal()}
  def actor(session, opts \\ [])

  def actor(%Plug.Conn{assigns: %{eh_os_contract_actor: %Actor{} = actor}}, _opts),
    do: {:ok, actor}

  def actor(%Plug.Conn{} = conn, opts), do: actor(get_session(conn), opts)

  def actor(session, opts) when is_map(session) do
    name = Keyword.get(opts, :sign_in, SignIn)

    verified(Map.get(session, @session_key), name, opts, [])
  end

  @doc """
  The credential for `application`, a name in `sign_in: [applications: ...]`, of the
  person `session` names: a `Plug.Conn` with its session fetched, or the session map a
  LiveView's `mount/3` is given. It is EHOS's token as issued, not verified here,
  for the application to verify; renewed first when it is good for less than 30
  seconds, as `actor/2`'s is. Send it from the server and keep it there: in a
  LiveView's assigns or a page, it reaches the browser, which the session keeps
  EHOS's tokens from.

  `{:error, :refused}` when EHOS refused the person a credential there (`invalid_target`:
  no role, or the application is outside the sign-in's granted set). The refusal is
  remembered for 10 minutes, and EHOS is not asked again until then; the session and
  every other application's credential go on. The other refusals are `actor/2`'s:
  `:signed_out`, `:ehos_unavailable`, `:renewal_busy`.

  Raises `ArgumentError` for a name `applications` does not have: a typo in the host's
  code, not something a person can change by signing in again.
  """
  @spec credential(Plug.Conn.t() | map(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, credential_refusal()}
  def credential(session, application, opts \\ [])

  def credential(%Plug.Conn{} = conn, application, opts),
    do: credential(get_session(conn), application, opts)

  def credential(session, application, opts) when is_map(session) do
    name = Keyword.get(opts, :sign_in, SignIn)
    applications = SignIn.config(name).applications

    case Map.fetch(applications, application) do
      {:ok, address} ->
        Renewal.credential(name, Map.get(session, @session_key), address)

      :error ->
        raise ArgumentError,
              "no application named #{inspect(application)} in sign_in: applications, " <>
                "which names #{inspect(Enum.sort(Map.keys(applications)))}"
    end
  end

  # The session the plug has read goes along, so the renewal's fast path does not read it again.
  defp maybe_actor(conn, session, opts) do
    if opts[:assign_actor] do
      browser_token = get_session(conn, @session_key)

      with {:ok, actor} <- verified(browser_token, opts[:sign_in], opts, session: session) do
        {:ok, assign(conn, :eh_os_contract_actor, actor)}
      end
    else
      {:ok, conn}
    end
  end

  # The credential for this application, renewed when it is stale (S4), verified as a bearer
  # credential is (S8).
  defp verified(browser_token, name, opts, read) do
    address = SignIn.config(name).address
    verify_opts = opts |> Keyword.take(@verify_opts) |> drop_nil()

    with {:ok, token} <- Renewal.credential(name, browser_token, address, verify_opts ++ read) do
      EhOsContract.Auth.verify(token, verify_opts)
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

  defp unavailable(conn) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(503, "Signing in through EHOS is unavailable. Try again shortly.")
    |> halt()
  end

  defp refuse(conn) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(401, "Sign in through EHOS first.")
    |> halt()
  end
end

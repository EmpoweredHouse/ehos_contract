defmodule EhosContract.Auth.SignIn.Router do
  # Sign-in through EHOS, with OpenID Connect, is EHOS's design, and these routes are S7 in
  # docs/adr/browser-session.md. The encrypted cookie session is S2, the callback's checks and
  # what the document must say S6; the exact post-logout address is EHOS's rule.
  @moduledoc """
  The routes that sign a browser in to the application's pages through EHOS, and
  out. Forward to it at `/auth/ehos`, behind the host's session, since EHOS returns to
  `address <> "/auth/ehos/callback"`:

      # in the host's router, in a scope whose pipeline fetches the session
      forward "/auth/ehos", EhosContract.Auth.SignIn.Router

  | Route | What it does |
  | --- | --- |
  | `GET /sign-in?return_to=<path>` | redirects to EHOS's authorization endpoint, with PKCE |
  | `GET /callback` | EHOS returns here; the code is exchanged and the person is signed in |
  | `POST /sign-out` | ends the session here and at EHOS; behind CSRF protection |

  **Signing in.** `oidcc_plug` keeps the request's `state`, nonce and PKCE verifier
  in the host's cookie session between the redirect and the callback, so the host
  encrypts it (`encryption_salt:`). The callback is refused unless EHOS's `iss`
  is the issuer, and the code is exchanged with `private_key_jwt` alone. A
  person signed in gets a new session token, and the Plug session is renewed, so a
  token planted before sign-in names nothing after it. `return_to` is followed only
  as a path of this application: anything else returns to `/`.

  **In the development mode.** Where `EhosContract.Auth.Development` runs under `sign_in:`,
  `GET /sign-in` sends the browser to `/dev/sign-in`, with the same `return_to`: there is
  no EHOS to sign in at.

  **When it cannot.** `GET /sign-in` answers 503 while EHOS's document and keys are
  not held, or do not say what signing in needs (`EhosContract.Auth.SignIn.provider/1`).
  A callback that does not sign anyone in answers 401, and is logged with its
  reason's name only.

  **Signing out.** The session's row goes, the Plug session is dropped, and the
  browser is sent to EHOS's end-session endpoint with the ID token as
  `id_token_hint` and `post_logout_redirect_uri` exactly `address <> "/"`. A
  request without a valid CSRF token raises `Plug.CSRFProtection.InvalidCSRFTokenError`,
  a 403.

  Takes `sign_in:`, the name of the `EhosContract.Auth.SignIn` child, by default
  `EhosContract.Auth.SignIn`.
  """

  @behaviour Plug

  import Plug.Conn

  require Logger

  alias EhosContract.Auth.{Development, ReturnTo, Session}
  alias EhosContract.Auth.SignIn
  alias EhosContract.Auth.SignIn.{ClientStore, Renewal, Sessions}
  alias Oidcc.Plug.{AuthorizationCallback, Authorize}

  @verify_opts [:keys, :audience, :issuer]

  @doc "Keeps `sign_in:` and `verify/2`'s `:keys`, `:audience` and `:issuer`; raises on any other."
  @impl Plug
  @spec init(keyword()) :: keyword()
  def init(opts), do: Keyword.validate!(opts, [sign_in: SignIn] ++ @verify_opts)

  @doc "Serves `GET /sign-in`, `GET /callback` and `POST /sign-out`; 404 otherwise."
  @impl Plug
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, opts) do
    name = Keyword.fetch!(opts, :sign_in)
    conn = put_private(conn, :ehos_contract_auth_sign_in, name)

    case {conn.method, conn.path_info} do
      {"GET", ["sign-in"]} -> sign_in(conn, name)
      {"GET", ["callback"]} -> callback(conn, name, verify_opts(opts))
      {"POST", ["sign-out"]} -> sign_out(conn, name)
      _other -> conn |> send_resp(404, "") |> halt()
    end
  end

  defp sign_in(conn, name) do
    conn = conn |> fetch_session() |> fetch_query_params()

    # Where the development mode runs, there is no EHOS to go to: its page signs people in.
    case Development.sign_in_path(name) do
      nil -> sign_in_through_ehos(conn, name)
      path -> redirect(conn, path <> "?" <> URI.encode_query(%{"return_to" => return_to(conn)}))
    end
  end

  defp return_to(conn), do: ReturnTo.local_path(conn.params["return_to"])

  defp sign_in_through_ehos(conn, name) do
    case SignIn.provider(name) do
      {:ok, _configuration} ->
        config = SignIn.config(name)
        # `oidcc_plug` relays the request's `state` parameter to the callback.
        conn = %{
          conn
          | params: Map.put(conn.params, "state", return_to(conn))
        }

        # EHOS's limit may be longer than this application's. `max_age` makes EHOS
        # ask for the password past this one's, so it never returns a sign-in the session would
        # refuse at once, sending the browser round and round EHOS.
        opts =
          Authorize.init(
            client_store: ClientStore,
            redirect_uri: config.redirect_uri,
            require_pkce: true,
            request_opts: config.request_opts,
            url_extension: [{"max_age", Integer.to_string(config.absolute_limit)}]
          )

        try do
          conn |> Authorize.call(opts) |> halt()
        rescue
          # `oidcc_plug` raises when the client store answers an error: the held document went
          # between `provider/1` and the redirect.
          Authorize.Error -> unavailable(conn, :ehos_unavailable)
        end

      {:error, reason} ->
        unavailable(conn, reason)
    end
  end

  defp unavailable(conn, reason) do
    Logger.warning("ehos_contract_auth cannot sign anyone in: #{describe(reason)}")
    text(conn, 503, "Signing in through EHOS is unavailable. Try again shortly.")
  end

  defp callback(conn, name, verify_opts) do
    conn = conn |> fetch_session() |> fetch_query_params()
    config = SignIn.config(name)

    # `oidcc_plug` merges the body's parameters into the query's; a GET has none.
    conn =
      if match?(%Plug.Conn.Unfetched{}, conn.body_params),
        do: %{conn | body_params: %{}},
        else: conn

    opts =
      AuthorizationCallback.init(
        client_store: ClientStore,
        redirect_uri: config.redirect_uri,
        preferred_auth_methods: [:private_key_jwt],
        # Behind an ingress with several pods, the redirect and the callback may come from
        # different peers (S6). The user agent is still checked.
        check_peer_ip: false,
        retrieve_userinfo: false,
        request_opts: config.request_opts
      )

    conn = AuthorizationCallback.call(conn, opts)
    result = conn.private[AuthorizationCallback]
    # It holds every token of the exchange; nothing after this reads it.
    conn = put_private(conn, AuthorizationCallback, nil)

    with {:ok, {token, _userinfo}} <- result,
         {:ok, signed_in} <- signed_in(token, config),
         :ok <- verified(signed_in, verify_opts) do
      # A sign-in in a browser already signed in ends the session it had, so its row cannot be
      # used again; and the Plug session starts empty, so nothing put in it before sign-in, a
      # planted CSRF token for one, outlives it (S2).
      :ok = Sessions.delete(get_session(conn, Session.session_key()))
      {:ok, browser_token} = Sessions.create(name, signed_in)
      Plug.CSRFProtection.delete_csrf_token()

      conn
      |> clear_session()
      |> configure_session(renew: true)
      |> put_session(Session.session_key(), browser_token)
      |> redirect(ReturnTo.local_path(conn.private[Authorize.State]))
    else
      {:error, reason} ->
        Logger.warning("ehos_contract_auth refused a sign-in through EHOS: #{describe(reason)}")
        text(conn, 401, "Signing in through EHOS did not succeed. Start again from the page.")
    end
  end

  # What the code exchange gave, as a session: the ID token's `sub`, `sid` and `auth_time`, and the
  # credential for this application, which EHOS issues for the client's own when no `resource` is
  # named. Nothing is matched in a function head, so a refusal prints no token.
  defp signed_in(token, config) do
    with %Oidcc.Token{id: %Oidcc.Token.Id{token: id_token, claims: claims}} <- token,
         %Oidcc.Token.Access{token: credential, expires: expires_in} <- token.access,
         %Oidcc.Token.Refresh{token: refresh_token} <- token.refresh,
         true <- is_integer(expires_in) and expires_in > 0,
         %{"sub" => subject, "sid" => sid, "auth_time" => auth_time} <- claims,
         true <- Enum.all?([subject, sid, refresh_token, id_token, credential], &text?/1),
         {:ok, auth_time} <- DateTime.from_unix(auth_time),
         # An EHOS that ignored `max_age` returns a sign-in the session would not read.
         :ok <- within_limit(auth_time, config.absolute_limit),
         expires_at = Renewal.expires_at(credential, EhosContract.Clock.now(), expires_in),
         # A credential within the renewal margin would be renewed by every request.
         true <- Renewal.beyond_margin?(expires_at) do
      {:ok,
       %{
         subject: subject,
         sid: sid,
         auth_time: auth_time,
         refresh_token: refresh_token,
         id_token: id_token,
         credential: %{
           resource: config.address,
           token: credential,
           expires_at: expires_at
         }
       }}
    else
      {:error, :past_absolute_limit} = past -> past
      _incomplete -> {:error, :incomplete_token_response}
    end
  end

  defp text?(value), do: is_binary(value) and value != ""

  # As the session reads it (`Sessions`): no older than the limit, the limit itself included.
  defp within_limit(auth_time, limit) do
    if DateTime.diff(EhosContract.Clock.now(), auth_time) <= limit,
      do: :ok,
      else: {:error, :past_absolute_limit}
  end

  # The credential is checked here as every request will check it, so one that can never pass
  # (another audience, keys not yet held) refuses this sign-in instead of sending the browser
  # round and round EHOS; and it must be the person the ID token names.
  defp verified(signed_in, verify_opts) do
    case EhosContract.Auth.verify(signed_in.credential.token, verify_opts) do
      {:ok, %{subject: subject}} when subject == signed_in.subject -> :ok
      {:ok, _other} -> {:error, :subject_mismatch}
      {:error, reason} -> {:error, {:credential_refused, reason}}
    end
  end

  defp verify_opts(opts),
    do: opts |> Keyword.take(@verify_opts) |> Enum.reject(&is_nil(elem(&1, 1)))

  defp sign_out(conn, name) do
    conn = conn |> fetch_session() |> Plug.CSRFProtection.call(Plug.CSRFProtection.init([]))
    config = SignIn.config(name)
    token = get_session(conn, Session.session_key())

    location =
      with {:ok, session} <- Sessions.fetch(name, token),
           {:ok, context} <- SignIn.client_context(name),
           {:ok, url} <-
             Oidcc.Logout.initiate_url(session.id_token, context, %{
               post_logout_redirect_uri: config.post_logout_redirect_uri
             }) do
        IO.iodata_to_binary(url)
      else
        # Not signed in here, or EHOS unavailable: the session here ends all the same.
        _other -> config.post_logout_redirect_uri
      end

    :ok = Sessions.delete(token)

    conn
    |> configure_session(drop: true)
    |> redirect(location)
  end

  defp redirect(conn, location) do
    conn
    |> put_resp_header("location", location)
    |> send_resp(302, "")
    |> halt()
  end

  defp text(conn, status, body) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(status, body)
    |> halt()
  end

  # A reason's name, never its value: some of `oidcc`'s carry the token they refused.
  defp describe({:credential_refused, reason}) when is_atom(reason),
    do: "credential_refused (#{reason})"

  defp describe(reason) when is_atom(reason), do: Atom.to_string(reason)

  defp describe(reason) when is_tuple(reason) and is_atom(elem(reason, 0)),
    do: Atom.to_string(elem(reason, 0))

  defp describe(_reason), do: "unexpected"
end

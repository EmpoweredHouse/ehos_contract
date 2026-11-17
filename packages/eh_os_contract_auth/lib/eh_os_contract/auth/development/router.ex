defmodule EhOsContract.Auth.Development.Router do
  @moduledoc """
  The pages and the endpoint of the development mode (`EhOsContract.Auth.Development`),
  for the application's router, at `/dev`:

      # the router, in the `dev_routes` block, outside any pipeline, after the block's
      # other `/dev` routes
      if Application.compile_env(:my_app, :dev_routes) do
        scope "/dev" do
          pipe_through :browser
          live_dashboard "/dashboard", metrics: MyAppWeb.Telemetry
        end

        forward "/dev", EhOsContract.Auth.Development.Router
      end

  The router answers each path under `/dev` that reaches it, so Phoenix must match the
  block's other `/dev` routes, the dashboard and the mailbox preview among them, first.

  It answers:

    * `GET /dev/sign-in`: a page that lists the actors of the domain
      (`EhOsContract.Auth.Development.actors/0`) and a field for each scope of their
      capabilities;
    * `POST /dev/sign-in`: signs the browser in as the person the form names
      (`EhOsContract.Auth.Development.sign_in/3`), and sends it to `return_to`, a path of
      this application, or to `/`. A refusal shows the page again, with the reason;
    * `POST /dev/credential`: a credential for `mix eh_os_contract.dev.credential`. It takes
      JSON, `{"subject": "u-dev", "actors": ["clinic.receptionist"], "scopes":
      {"clinic_id": "clinic-1"}}`, and answers `{"credential": "<token>"}`, or 422 with
      `{"error": "<reason>"}`.

  Each answer comes only where the mode has started, to a request from a loopback address,
  with a `Host` of `localhost`, `127.0.0.1` or `[::1]`, and with the token the mode printed
  at start, as the `token` parameter or the `x-dev-sign-in-token` header. After the first
  request, the browser's session keeps a hash of the token, so the page's links and form
  need no token. Each other request gets 403. A request that passes gets 404 for a path
  the router does not know. No answer carries
  an `Access-Control-Allow-*` header. A CORS plug in the endpoint that answers a preflight
  `OPTIONS` itself, or adds its headers as the answer is sent, is not covered: keep such a
  plug off the `/dev` paths.

  The pages use the session of the endpoint's `Plug.Session`, which a Phoenix endpoint
  has, and check a CSRF token on the form (`Plug.CSRFProtection`): a form sent without a
  valid one gets 403. A request that passes the checks above, but whose query string or body
  Plug cannot read, gets the status of Plug's error, such as 400, or 413 for a body that is
  too large.
  Mount the router at `/dev`: `EhOsContract.Auth.Session` and
  `EhOsContract.Auth.SignIn.Router`'s `GET /sign-in` send a browser to `/dev/sign-in`.

  ## The look of the page

  The page links the application's stylesheet, `/assets/css/app.css` by default, the path a
  Phoenix 1.8 application serves its CSS at in development. With the EmpoweredHouse design
  system (`ehos_design`) imported there, the page takes the application's fonts, colours,
  buttons and fields. Without it, or when the path does not exist, the page keeps a plain look
  of its own. Name another path, or none:

      forward "/dev", EhOsContract.Auth.Development.Router, stylesheet: "/assets/app.css"
      forward "/dev", EhOsContract.Auth.Development.Router, stylesheet: nil

  The stylesheet is the page's only link. The browser asks for it, and for what it loads, such
  as fonts, only after the router let the page through. The page has no script. A stylesheet
  with Tailwind but without daisyUI's `btn`, `input` and `checkbox` classes leaves the button and
  the fields bare: give `stylesheet: nil` there.
  """

  @behaviour Plug

  import Plug.Conn

  alias EhOsContract.Auth.{Development, ReturnTo, Session}
  alias EhOsContract.Auth.Development.{Credential, Guard, Page}

  @form Plug.Parsers.init(parsers: [:urlencoded], pass: ["*/*"])
  @csrf Plug.CSRFProtection.init([])

  @doc """
  Takes `stylesheet:`, the path of the application's stylesheet that the page links, or `nil`
  for none (the module's doc has an example). It raises on any other option, and on a
  stylesheet that is not a path of this application, such as `"https://cdn.example/app.css"` or
  `"//cdn.example/app.css"`.
  """
  @impl Plug
  @spec init(keyword()) :: keyword()
  def init(opts) do
    opts = Keyword.validate!(opts, stylesheet: "/assets/css/app.css")
    stylesheet = opts[:stylesheet]

    if is_nil(stylesheet) or local_path?(stylesheet) do
      opts
    else
      raise ArgumentError,
            "the stylesheet must be a path of this application, such as " <>
              "\"/assets/css/app.css\", or nil, got: #{inspect(stylesheet)}"
    end
  end

  # A path on this origin: one leading slash, and no backslash or control character, which a
  # browser may read as another slash or drop.
  defp local_path?(path) when is_binary(path),
    do: String.match?(path, ~r{\A/(?![/\\])[^\\\x00-\x20\x7f]*\z})

  defp local_path?(_path), do: false

  @doc "Answers the request, as the module's doc lists."
  @impl Plug
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, opts) do
    case {conn.method, conn.path_info} do
      {_method, ["credential" | rest]} -> Plug.forward(conn, rest, Credential, [])
      {"GET", ["sign-in"]} -> conn |> browser() |> then(&page(&1, opts, 200, nil))
      {"POST", ["sign-in"]} -> conn |> browser() |> then(&create(&1, opts))
      _other -> conn |> fetch_session() |> Guard.call([]) |> not_found()
    end
  rescue
    # A query string or a body that Plug cannot read raises, and the error page an endpoint
    # renders starts from its own conn, which keeps a CORS header the guard strips. Plug's own
    # refusals are answered here instead; any other error is raised as it was.
    error ->
      if plug_refusal?(error),
        do: unreadable(conn, error),
        else: reraise(error, __STACKTRACE__)
  end

  defp plug_refusal?(%module{} = error),
    do:
      String.starts_with?(inspect(module), "Plug.") and
        Plug.Exception.status(error) in 400..499

  # After the guard, as each other answer: a request the guard refuses gets its 403. The guard
  # reads the token from the query string, the header and the session, not from a body Plug
  # could not read.
  defp unreadable(conn, error) do
    conn =
      conn
      |> fetch_session()
      |> readable_query()
      |> secure()
      |> Guard.call([])

    if conn.halted do
      conn
    else
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(Plug.Exception.status(error), "The request could not be read.")
      |> halt()
    end
  end

  defp readable_query(conn) do
    fetch_query_params(conn)
  rescue
    Plug.Conn.InvalidQueryError -> %{conn | query_params: %{}}
  end

  defp secure(conn) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("referrer-policy", "no-referrer")
    |> put_resp_header("x-frame-options", "DENY")
  end

  defp not_found(%Plug.Conn{halted: true} = conn), do: conn
  defp not_found(conn), do: conn |> send_resp(404, "") |> halt()

  # The guard, then the CSRF check: a request without the token gets the guard's 403, not
  # Plug's CSRF error.
  defp browser(conn) do
    conn =
      conn
      |> fetch_session()
      |> fetch_query_params()
      |> Plug.Parsers.call(@form)
      |> secure()
      |> Guard.call([])

    if conn.halted, do: conn, else: csrf(conn)
  end

  # Answered from this conn, not raised: the error page an endpoint renders for the exception
  # starts from the conn before the guard, so it would keep a CORS header the guard strips.
  defp csrf(conn) do
    Plug.CSRFProtection.call(conn, @csrf)
  rescue
    Plug.CSRFProtection.InvalidCSRFTokenError ->
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(403, "The form has no valid CSRF token. Open /dev/sign-in again.")
      |> halt()
  end

  defp page(%Plug.Conn{halted: true} = conn, _opts, _status, _error), do: conn

  defp page(conn, opts, status, error) do
    params = Map.merge(conn.query_params, body(conn))

    html =
      Page.render(
        actors: Development.actors(),
        csrf_token: Plug.CSRFProtection.get_csrf_token(),
        return_to: ReturnTo.local_path(params["return_to"]),
        subject: params["subject"],
        chosen: list(params["actors"]),
        scopes: map(params["scopes"]),
        error: error,
        stylesheet: opts[:stylesheet]
      )

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(status, html)
    |> halt()
  end

  defp create(%Plug.Conn{halted: true} = conn, _opts), do: conn

  defp create(conn, opts) do
    params = body(conn)
    subject = blank_to(params["subject"], "dev")
    scopes = params["scopes"] |> map() |> Map.reject(fn {_scope, value} -> value == "" end)

    case Development.sign_in(subject, list(params["actors"]), scopes) do
      {:ok, token} ->
        conn
        |> configure_session(renew: true)
        |> put_session(Session.session_key(), token)
        |> put_resp_header("location", ReturnTo.local_path(params["return_to"]))
        |> send_resp(303, "")
        |> halt()

      {:error, reason} ->
        page(conn, opts, 422, Development.describe(reason))
    end
  end

  defp body(%Plug.Conn{body_params: %Plug.Conn.Unfetched{}}), do: %{}
  defp body(conn), do: conn.body_params

  defp list(values) when is_list(values), do: Enum.filter(values, &is_binary/1)
  defp list(_values), do: []

  defp map(values) when is_map(values),
    do: Map.filter(values, fn {scope, value} -> is_binary(scope) and is_binary(value) end)

  defp map(_values), do: %{}

  defp blank_to(value, default) when is_binary(value) do
    case String.trim(value) do
      "" -> default
      trimmed -> trimmed
    end
  end

  defp blank_to(_value, default), do: default
end

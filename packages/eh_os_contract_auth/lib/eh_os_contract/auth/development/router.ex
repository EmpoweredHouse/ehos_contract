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
  has, and check a CSRF token on the form (`Plug.CSRFProtection`). Mount the router at
  `/dev`: `EhOsContract.Auth.Session` sends a browser to `/dev/sign-in`.
  """

  @behaviour Plug

  import Plug.Conn

  alias EhOsContract.Auth.{Development, ReturnTo, Session}
  alias EhOsContract.Auth.Development.{Credential, Guard, Page}

  @form Plug.Parsers.init(parsers: [:urlencoded], pass: ["*/*"])
  @csrf Plug.CSRFProtection.init([])

  @doc "Takes no options, and raises on any."
  @impl Plug
  @spec init(keyword()) :: keyword()
  def init(opts), do: Keyword.validate!(opts, [])

  @doc "Answers the request, as the module's doc lists."
  @impl Plug
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    case {conn.method, conn.path_info} do
      {_method, ["credential" | rest]} -> Plug.forward(conn, rest, Credential, [])
      {"GET", ["sign-in"]} -> conn |> browser() |> then(&page(&1, 200, nil))
      {"POST", ["sign-in"]} -> conn |> browser() |> then(&create/1)
      _other -> conn |> Guard.call([]) |> not_found()
    end
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
      |> put_resp_header("cache-control", "no-store")
      |> put_resp_header("referrer-policy", "no-referrer")
      |> put_resp_header("x-frame-options", "DENY")
      |> Guard.call([])

    if conn.halted, do: conn, else: Plug.CSRFProtection.call(conn, @csrf)
  end

  defp page(%Plug.Conn{halted: true} = conn, _status, _error), do: conn

  defp page(conn, status, error) do
    params = Map.merge(conn.query_params, body(conn))

    html =
      Page.render(
        actors: Development.actors(),
        csrf_token: Plug.CSRFProtection.get_csrf_token(),
        return_to: ReturnTo.local_path(params["return_to"]),
        subject: params["subject"],
        chosen: list(params["actors"]),
        scopes: map(params["scopes"]),
        error: error
      )

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(status, html)
    |> halt()
  end

  defp create(%Plug.Conn{halted: true} = conn), do: conn

  defp create(conn) do
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
        page(conn, 422, Development.describe(reason))
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

defmodule EhOsContract.Auth.Development.Guard do
  @moduledoc """
  The plug in front of the development mode's pages and endpoint
  (`EhOsContract.Auth.Development`): `/dev/sign-in` and the terminal's
  `EhOsContract.Auth.Development.Credential`.

      # the router, in the `dev_routes` block
      scope "/dev" do
        pipe_through [:browser, EhOsContract.Auth.Development.Guard]
        get "/sign-in", MyAppWeb.DevSignInController, :new
      end

  It lets a request through only when all of these hold, whatever address the endpoint
  listens on, and answers 403 otherwise:

    * the mode has started;
    * the request comes from a loopback address, `127.0.0.0/8` or `::1`;
    * its `Host` is `localhost`, `127.0.0.1` or `[::1]`, which also refuses a page that DNS
      rebinding points at the computer;
    * it carries the token the mode printed at start, as the `token` parameter or in the
      `x-dev-sign-in-token` header; or its Plug session, when fetched, holds the token's hash,
      which the guard leaves there for the requests after the first.

  Its answers, and every answer of a request it lets through, carry no
  `Access-Control-Allow-*` header, whatever plug added one.
  """

  @behaviour Plug

  import Plug.Conn

  alias EhOsContract.Auth.{Development, SignIn}

  @header "x-dev-sign-in-token"
  @session_key "eh_os_contract_auth_development_token"
  @hosts ["localhost", "127.0.0.1", "[::1]", "::1"]

  @typedoc "Why a request is refused."
  @type refusal :: :not_started | :not_loopback | :wrong_host | :no_token | :wrong_token

  @doc "Takes no options, and raises on any."
  @impl Plug
  @spec init(keyword()) :: keyword()
  def init(opts), do: Keyword.validate!(opts, [])

  @doc "Lets the request through, or answers 403."
  @impl Plug
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    conn = register_before_send(conn, &without_cors/1)

    case check(conn) do
      {:ok, token} ->
        remember(conn, token)

      {:error, reason} ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(403, message(reason))
        |> halt()
    end
  end

  @doc """
  Whether `conn` may reach the development mode, as the module's doc lists: `{:ok, hash}`,
  the hash of the token it carries, or the first condition that fails.
  """
  @spec check(Plug.Conn.t()) :: {:ok, String.t()} | {:error, refusal()}
  def check(conn) do
    cond do
      not Development.started?(SignIn) -> {:error, :not_started}
      not loopback?(conn.remote_ip) -> {:error, :not_loopback}
      conn.host not in @hosts -> {:error, :wrong_host}
      true -> token(conn)
    end
  end

  defp loopback?({127, _, _, _}), do: true
  defp loopback?({0, 0, 0, 0, 0, 0, 0, 1}), do: true
  # An IPv4 loopback address mapped to IPv6, `::ffff:127.x.y.z`.
  defp loopback?({0, 0, 0, 0, 0, 0xFFFF, high, _low}), do: Bitwise.bsr(high, 8) == 127
  defp loopback?(_address), do: false

  # The session keeps the token's hash, not the token: a session cookie that is signed and not
  # encrypted is readable by whatever else the browser sends `localhost`'s cookies to.
  defp token(conn) do
    conn = fetch_query_params(conn)
    given = Enum.filter([List.first(get_req_header(conn, @header)), param(conn)], &is_binary/1)
    remembered = if session?(conn), do: get_session(conn, @session_key)

    cond do
      token = Enum.find(given, &Development.token?/1) -> {:ok, hash(token)}
      is_binary(remembered) and Development.token_hash?(remembered) -> {:ok, remembered}
      given == [] and remembered == nil -> {:error, :no_token}
      true -> {:error, :wrong_token}
    end
  end

  defp param(conn) do
    body = if is_struct(conn.body_params), do: %{}, else: conn.body_params
    Map.get(conn.query_params, "token") || Map.get(body, "token")
  end

  defp hash(token), do: Base.url_encode64(:crypto.hash(:sha256, token), padding: false)

  defp remember(conn, hash),
    do: if(session?(conn), do: put_session(conn, @session_key, hash), else: conn)

  defp session?(conn), do: Map.get(conn.private, :plug_session_fetch) == :done

  defp without_cors(conn) do
    headers = Enum.reject(conn.resp_headers, fn {name, _} -> cors?(name) end)
    %{conn | resp_headers: headers}
  end

  defp cors?(name), do: String.starts_with?(String.downcase(name), "access-control-allow-")

  defp message(:not_started), do: "The development sign-in has not started."

  defp message(reason) when reason in [:not_loopback, :wrong_host],
    do: "The development sign-in answers only on localhost, from this computer."

  defp message(_token),
    do: "Open the address the application printed in its terminal when it started."
end

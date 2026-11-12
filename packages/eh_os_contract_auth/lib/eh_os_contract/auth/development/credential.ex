defmodule EhOsContract.Auth.Development.Credential do
  @moduledoc false
  # `POST /dev/credential` of `EhOsContract.Auth.Development.Router`, for
  # `mix eh_os_contract.dev.credential`: JSON in, `{"credential": …}` or 422 out, behind the
  # guard, which it runs itself.

  @behaviour Plug

  import Plug.Conn

  alias EhOsContract.Auth.Development
  alias EhOsContract.Auth.Development.Guard

  @parsers Plug.Parsers.init(parsers: [:json], json_decoder: Jason, pass: ["*/*"])

  @doc "Takes no options, and raises on any."
  @impl Plug
  @spec init(keyword()) :: keyword()
  def init(opts), do: Keyword.validate!(opts, [])

  @doc "Answers `POST /` with a credential, behind the guard; 404 otherwise."
  @impl Plug
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    conn = Guard.call(conn, [])

    cond do
      conn.halted -> conn
      conn.method == "POST" and conn.path_info == [] -> answer(parse(conn))
      true -> conn |> send_resp(404, "") |> halt()
    end
  end

  defp parse(%Plug.Conn{body_params: %Plug.Conn.Unfetched{}} = conn),
    do: Plug.Parsers.call(conn, @parsers)

  defp parse(conn), do: conn

  defp answer(conn) do
    params = conn.body_params

    result =
      Development.credential(
        Map.get(params, "subject", "dev"),
        Map.get(params, "actors", []),
        Map.get(params, "scopes", %{})
      )

    case result do
      {:ok, token} -> json(conn, 200, %{credential: token})
      {:error, reason} -> json(conn, 422, %{error: Development.describe(reason)})
    end
  end

  defp json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
    |> halt()
  end
end

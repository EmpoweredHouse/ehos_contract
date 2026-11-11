defmodule EhOsContract.Auth.Development.Credential do
  @moduledoc """
  The endpoint `mix eh_os_contract.dev.credential` asks the running application for a
  credential through, in the development mode (`EhOsContract.Auth.Development`). The key
  stays in the application's memory; only the signed credential leaves it.

      # the router, in the `dev_routes` block
      forward "/dev/credential", EhOsContract.Auth.Development.Credential

  It runs `EhOsContract.Auth.Development.Guard` itself, so it needs no pipeline.
  `POST /` takes a JSON object,

      {"subject": "u-dev", "actors": ["clinic.receptionist"], "scopes": {"clinic_id": "clinic-1"}}

  and answers `{"credential": "<token>"}`, or 422 with `{"error": "<reason>"}` for what
  `EhOsContract.Auth.Development.credential/3` refuses. `subject` defaults to `"dev"`, and
  `scopes` to none.
  """

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
      {:error, reason} -> json(conn, 422, %{error: describe(reason)})
    end
  end

  defp describe({reason, values}), do: "#{reason}: #{Enum.join(values, ", ")}"
  defp describe(reason), do: Atom.to_string(reason)

  defp json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
    |> halt()
  end
end

defmodule EhOsContract.Web.Api.Conformance do
  @moduledoc """
  The conformance report, as data, for one contract.

  `GET <mount>/conformance?contract=<contract id>&since=…&until=…`

  The projection is `EhOsContract.Conformance.as_data/2` and lives in the engine, not here:
  the shape a consumer compares version to version is part of what the engine
  promises, and a transport that owned it would make that promise a property of
  whichever web package happened to serve it.

  ## What this exposes, said out loud

  `report.deployment.in_log` carries per-version event counts with timestamps —
  volume data about the client's business, which is on the other side of the line
  `EhOsContract.Conformance`'s own moduledoc draws between paths and companies. It is not
  redacted here, because a package deciding how sensitive a client's data is would
  be the package knowing that client's domain. It is named here so a host's
  resolver can decide.

  `Jason.encode_to_iodata!/1` directly rather than `Phoenix.Controller.json/2`: the
  latter reads `config :phoenix, :json_library`, which is host configuration a
  mountable package has no business assuming — the same argument this package's
  router already makes about `Plug.Parsers`.
  """

  @behaviour Plug

  import Plug.Conn

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, opts) do
    conn = EhOsContract.Web.Api.Authorize.call(conn, opts)

    if conn.halted do
      conn
    else
      conn = fetch_query_params(conn)

      with {:ok, contract} <- contract(conn.params["contract"]),
           {:ok, since} <- at(conn.params["since"], "since"),
           {:ok, until} <- at(conn.params["until"], "until") do
        body = EhOsContract.Conformance.as_data(contract, since: since, until: until)
        json(conn, 200, body)
      else
        {:error, detail} ->
          json(conn, 400, %{"error" => "bad_request", "detail" => detail})
      end
    end
  end

  # Resolved against the registry rather than through `String.to_existing_atom/1`:
  # a parameter naming any loaded module would otherwise reach `report/2`, and the
  # answer to "is this one of ours" belongs to the registry that already knows.
  @spec contract(String.t() | nil) :: {:ok, module()} | {:error, String.t()}
  defp contract(nil) do
    case EhOsContract.Registry.contracts() do
      [only] -> {:ok, only}
      [] -> {:error, "no contract is registered"}
      _many -> {:error, "several contracts are registered; name one with `contract=`"}
    end
  end

  defp contract(name) do
    case EhOsContract.Registry.contract(name) do
      nil -> {:error, "unknown contract #{name}"}
      contract -> {:ok, contract}
    end
  end

  @spec at(String.t() | nil, String.t()) :: {:ok, DateTime.t() | nil} | {:error, String.t()}
  defp at(nil, _which), do: {:ok, nil}

  defp at(value, which) do
    case DateTime.from_iso8601(value) do
      {:ok, at, _offset} -> {:ok, at}
      {:error, _} -> {:error, "#{which} is not an ISO 8601 timestamp"}
    end
  end

  @spec json(Plug.Conn.t(), pos_integer(), map()) :: Plug.Conn.t()
  defp json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode_to_iodata!(body))
  end
end

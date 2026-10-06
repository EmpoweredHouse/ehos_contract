defmodule EhOsContract.Web.Api.AsyncAPI do
  @moduledoc """
  The generated AsyncAPI document for one contract, or the index of all of them.

  `GET <mount>/asyncapi` — every contract, with its version and document digest.
  `GET <mount>/asyncapi/<contract id>` — that contract's document.

  The digest is served twice, in `info["x-eh-os-contract-digest"]` and as the `ETag`. Not
  redundant: a consumer comparing what an instance claims against what its build
  recorded can do it with a `HEAD` and no body at all.

  **Authenticated, like the report.** A document naming every event, every field
  and every label in the client's own words is a map of their business, not "just a
  schema", and the same `EhOsContract.Web.Resolver` decides who sees it.
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
      case conn.path_params["contract"] do
        nil -> json(conn, 200, %{"contracts" => EhOsContract.AsyncAPI.index()})
        name -> one(conn, name)
      end
    end
  end

  @spec one(Plug.Conn.t(), String.t()) :: Plug.Conn.t()
  defp one(conn, name) do
    case EhOsContract.Registry.contract(name) do
      nil ->
        json(conn, 404, %{"error" => "not_found", "detail" => "unknown contract #{name}"})

      contract ->
        document = EhOsContract.AsyncAPI.document(contract)

        conn
        |> put_resp_header("etag", ~s("#{document["info"]["x-eh-os-contract-digest"]}"))
        |> json(200, document)
    end
  end

  @spec json(Plug.Conn.t(), pos_integer(), map()) :: Plug.Conn.t()
  defp json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode_to_iodata!(body))
  end
end

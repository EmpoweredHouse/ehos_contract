defmodule EhOsContract.Auth.Plug do
  @moduledoc """
  The bearer token of a request, verified, as the actor `EhOsContract.Plug` serves:

      # in the host's router
      pipeline :eh_os_contract_api do
        plug :accepts, ["json"]
        plug EhOsContract.Auth.Plug
      end

      scope "/api" do
        pipe_through :eh_os_contract_api
        forward "/", EhOsContract.Plug, contracts: [Rehmed.Contracts.VisitSettlement]
      end

  A request with `authorization: Bearer <credential>` that `EhOsContract.Auth.verify/2`
  accepts goes on with `conn.assigns.eh_os_contract_actor` set. Anything else stops
  here with 401 and a `www-authenticate: Bearer` header:

  | Request | Body |
  | --- | --- |
  | no `authorization` header, or not a bearer one | `{"error": "no_credential"}` |
  | a credential `verify/2` refuses | `{"error": "<reason>"}` — `expired`, `unknown_key`, … |

  A refused credential is logged with its reason and nothing of the token. It gets
  no row in `eh_os_contract_auth_decisions`: a credential that does not verify names
  nobody to record, and a flood of them would fill the table. The rows are the
  `EhOsContract.Authorizer`'s decisions about actors that did verify.

  Takes `verify/2`'s options — `:audience`, `:issuer`, `:keys` — to override the
  configuration.
  """

  @behaviour Plug

  import Plug.Conn

  require Logger

  @doc "Keeps `verify/2`'s options."
  @impl Plug
  @spec init(keyword()) :: keyword()
  def init(opts), do: Keyword.take(opts, [:audience, :issuer, :keys])

  @doc "Verifies the bearer token and assigns its actor, or answers 401."
  @impl Plug
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, opts) do
    case bearer(conn) do
      nil ->
        refuse(conn, "no_credential", "Bearer")

      token ->
        case EhOsContract.Auth.verify(token, opts) do
          {:ok, actor} ->
            assign(conn, :eh_os_contract_actor, actor)

          {:error, reason} ->
            Logger.info("eh_os_contract_auth refused a credential: #{reason}")
            refuse(conn, Atom.to_string(reason), ~s(Bearer error="invalid_token"))
        end
    end
  end

  defp bearer(conn) do
    with [header | _] <- get_req_header(conn, "authorization"),
         [scheme, token] <- String.split(header, " ", parts: 2),
         "bearer" <- String.downcase(scheme),
         token when token != "" <- String.trim(token) do
      token
    else
      _ -> nil
    end
  end

  defp refuse(conn, error, challenge) do
    conn
    |> put_resp_header("www-authenticate", challenge)
    |> put_resp_content_type("application/json")
    |> send_resp(401, Jason.encode!(%{error: error}))
    |> halt()
  end
end

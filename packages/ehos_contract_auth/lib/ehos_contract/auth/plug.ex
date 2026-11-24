defmodule EhosContract.Auth.Plug do
  @moduledoc """
  The bearer token of a request, verified, as the actor `EhosContract.Plug` serves:

      # in the host's router
      pipeline :ehos_contract_api do
        plug :accepts, ["json"]
        plug EhosContract.Auth.Plug
      end

      scope "/api" do
        pipe_through :ehos_contract_api
        forward "/", EhosContract.Plug, contracts: [Clinic.Contracts.VisitSettlement]
      end

  A request with `authorization: Bearer <credential>` that `EhosContract.Auth.verify/2`
  accepts goes on with `conn.assigns.ehos_contract_actor` set. Anything else stops
  here with 401:

  | Request | `www-authenticate` | Body |
  | --- | --- | --- |
  | no `authorization` header, not a bearer one, or an empty token | `Bearer` | `{"error": "no_credential"}` |
  | a credential `verify/2` refuses | `Bearer error="invalid_token"` | `{"error": "<reason>"}` — `expired`, `unknown_key`, … |

  A refused credential is logged with its reason and nothing of the token. It gets
  no row in `ehos_contract_auth_decisions`: a credential that does not verify names
  nobody to record, and a flood of them would fill the table. The rows are the
  `EhosContract.Authorizer`'s decisions about actors that did verify.

  Takes `verify/2`'s options — `:audience`, `:issuer`, `:keys` — to override the
  configuration.
  """

  @behaviour Plug

  import Plug.Conn

  require Logger

  @doc "Keeps `verify/2`'s options, and raises on any other: a misspelt one would be ignored."
  @impl Plug
  @spec init(keyword()) :: keyword()
  def init(opts) do
    case Keyword.keys(opts) -- [:audience, :issuer, :keys] do
      [] ->
        opts

      unknown ->
        raise ArgumentError,
              "EhosContract.Auth.Plug takes :audience, :issuer and :keys, not #{inspect(unknown)}"
    end
  end

  @doc "Verifies the bearer token and assigns its actor, or answers 401."
  @impl Plug
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, opts) do
    case bearer(conn) do
      nil ->
        refuse(conn, "no_credential", "Bearer")

      token ->
        case EhosContract.Auth.verify(token, opts) do
          {:ok, actor} ->
            assign(conn, :ehos_contract_actor, actor)

          {:error, reason} ->
            Logger.info("ehos_contract_auth refused a credential: #{reason}")
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

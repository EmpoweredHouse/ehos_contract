defmodule PNS.Web.LocalLogin do
  @moduledoc """
  A provisional login screen, mounted alongside the dashboard by
  `pns_dashboard/2` — GET renders a form, POST mints a token with
  `PNS.Auth.LocalToken.sign/1` and writes it to the session key
  `PNS.Web.Plug.Authenticate` reads back.

  **This disappears the day a real login flow exists**, the same way
  `LocalToken` itself is documented as "the first thing to disappear when
  it is swapped." `docs/adr/identity-seam.md`'s "Not decided" section
  still lists a real login screen route as open — a provider redirect,
  a callback, a session bridge to whatever token that exchange produces.
  This is not that. It exists so a host can look at its own dashboard in a
  browser today, typing in who it is instead of curling a header by hand.

  A plain HTTP form, not a LiveView: setting a session requires a `conn`,
  and a LiveView only has one at the moment it first mounts, disconnected
  from every request after. Needs `Plug.Parsers` for the urlencoded POST
  body — see `test/support/test_host/endpoint.ex` for the one line a real
  host almost certainly already has.
  """

  @behaviour Plug

  import Plug.Conn
  use Phoenix.Component

  @doc false
  @impl true
  def init(opts), do: opts

  @doc false
  @impl true
  def call(%{method: "POST"} = conn, opts), do: create(conn, opts)
  def call(conn, opts), do: new(conn, opts)

  @spec new(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  defp new(conn, opts) do
    respond(conn, form_assigns(opts))
  end

  @spec create(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  defp create(conn, opts) do
    case conn.body_params do
      %{"subject" => subject, "role" => role} when subject != "" ->
        token = PNS.Auth.LocalToken.sign(%{"sub" => subject, "roles" => [role]})

        conn
        |> put_session(:pns_local_token, token)
        |> put_resp_header("location", Keyword.fetch!(opts, :redirect_to))
        |> send_resp(303, "")

      _ ->
        respond(conn, form_assigns(opts, error: "Subject is required."))
    end
  end

  defp form_assigns(opts, extra \\ []) do
    [
      action: Keyword.fetch!(opts, :action),
      csrf_token: Plug.CSRFProtection.get_csrf_token(),
      error: nil
    ]
    |> Keyword.merge(extra)
    |> Map.new()
  end

  defp respond(conn, assigns) do
    html =
      assigns
      |> page()
      |> Phoenix.HTML.Safe.to_iodata()
      |> IO.iodata_to_binary()

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, html)
  end

  attr :action, :string, required: true
  attr :csrf_token, :string, required: true
  attr :error, :string, default: nil

  # A standalone document, not `PNS.Web.Layouts` — that layout takes
  # `@inner_content` from a LiveView, and this is a plain Plug. Links the
  # same stylesheet by the same fixed, mount-independent URL so it does not
  # look like a different product from the screens it leads to.
  defp page(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>PNS Dashboard — Log in</title>
        <link rel="stylesheet" href="/pns_web/assets/app.css" />
      </head>
      <body>
        <main>
          <h2>Provisional login</h2>
          <p>
            <code>PNS.Auth.LocalToken</code>, dev only — mints a token for whoever you say
            you are. Disappears when a real login screen exists.
          </p>
          <p :if={@error} class="outcome-breached">{@error}</p>
          <form method="post" action={@action}>
            <input type="hidden" name="_csrf_token" value={@csrf_token} />
            <input type="text" name="subject" placeholder="who are you" required />
            <select name="role">
              <option value="pns_admin">Admin (all access)</option>
              <option value="pns_read">Read only</option>
            </select>
            <button type="submit">Log in</button>
          </form>
        </main>
      </body>
    </html>
    """
  end
end

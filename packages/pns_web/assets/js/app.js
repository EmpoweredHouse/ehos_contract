// The dashboard's only client-side code: connect the LiveView socket.
// Everything else — access control, the four questions, the accounts
// roster — is server-rendered; this file has no business logic of its own.
import "phoenix_html"
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"

const csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content")

const liveSocket = new LiveSocket("/live", Socket, {
  params: { _csrf_token: csrfToken },
})

liveSocket.connect()

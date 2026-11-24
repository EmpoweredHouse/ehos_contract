// The dashboard's client-side code: connect the LiveView socket and draw the graph renderer's
// pictures. Everything else — access control and the four questions — is server-rendered.
import "phoenix_html"
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
// The graph renderer's hook (plan E13b), bundled into this file from the package beside this one.
import { EhosContractGraph } from "../../../ehos_contract_graph/priv/static/ehos_contract_graph.esm.js"

const csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content")

const liveSocket = new LiveSocket("/live", Socket, {
  params: { _csrf_token: csrfToken },
  hooks: { EhosContractGraph },
})

liveSocket.connect()

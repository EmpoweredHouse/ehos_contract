# Draw a graph document

This page tells you how to draw one picture of one graph document on a page of your application,
with `EhOsContract.GraphRenderer.Canvas`. It is for a developer who has installed this package.
It also says what the reader of the page can do in the picture, and which Content-Security-Policy
the page needs.

A *graph document* is the facts of a domain, a contract or a process module as JSON, in the format
`graph.v1`. An *overlay* gives what the log says about the same facts. The
[glossary of the engine](https://github.com/EmpoweredHouse/eh-os-contract/blob/main/packages/eh_os_contract/docs/glossary.md)
defines both.

## Before you start

- Install the package, as the [README](../README.md) says.
- Get a graph document with string keys, as JSON decodes it. The engine writes it with
  `EhOsContract.Graph.Document`. The JSON API of an application gives it at `GET <mount>/graph/<id>`.
- Optional: get the overlay of the same document, from `EhOsContract.Graph.Overlay` or
  `GET <mount>/graph/<id>/overlay`.

## Steps

1. Import the script of the package in the bundle of your application, and register its hook.
   The script is an ES module, `priv/static/eh_os_contract_graph.esm.js`:

   ```js
   import { EhOsContractGraph } from "<path to the dependency>/priv/static/eh_os_contract_graph.esm.js"

   const liveSocket = new LiveSocket("/live", Socket, { hooks: { EhOsContractGraph } })
   ```

2. Add the stylesheet of the package, `priv/static/eh_os_contract_graph.css`. Import it into your
   own stylesheet, or serve it beside it. It uses the tokens of the EmpoweredHouse design system,
   `--surface-*`, `--border-*`, `--text-*`, `--accent-*`, `--error-*` and `--radius-*`. Define them in your page: the picture then
   follows the theme of your page.

3. Render the canvas, with the document, the overlay and the view:

   ```heex
   <.live_component
     module={EhOsContract.GraphRenderer.Canvas}
     id="contract-graph"
     document={@document}
     overlay={@overlay}
     view={:contract}
   />
   ```

   `id` is the DOM id of the canvas, so make it unique on the page. `overlay` is optional.
   `view` names the picture: see [Which view do I choose?](#which-view-do-i-choose).

4. Optional: to show the actors of a domain, add the table of its actors. Give it the graph
   document of the domain and the DOM id of a canvas of the same document:

   ```heex
   <EhOsContract.GraphRenderer.Actors.table document={@domain_document} canvas="domain-map" />
   ```

   No picture shows all the actors of a domain. A row of the table selects its actor in the
   canvas. The panel of the canvas then says what the actor can do, contract by contract. Give the
   table `audience={:owner}` if the canvas has it too.

**Result:** the page shows the picture, with a bar over it. If you gave an overlay, the cards and
the arrows show the numbers of the log.

`EhOsContract.GraphRenderer.Canvas` has more attributes:

- `audience={:owner}` shows the page to the owner of the business, in the words of the client.
  [Explore a domain](explore-a-domain.md) says what it removes.
- `select` selects a card, a group or an arrow by its id, and opens its panel.
- `link` makes the boxes of a landscape lead to pages of your application.
  [Join applications](join-applications.md) tells you how.

## Which view do I choose?

| `view` | Of | The picture |
| --- | --- | --- |
| `:contract` | a contract | its full graph: commands and events in their units, the reactions and timers between them, read models and queries, and the actors and external systems they touch |
| `{:unit, id}` | a contract | one unit: its state, commands, events and rules, and how many scenarios cover each path |
| `{:lifecycle, id}` | a contract | the statuses of an aggregate, and the events that move it between them |
| `:process` | a process module | its stages in order, the events of each stage with their contracts, the events that end a run, and its promises with their windows |
| `:context_map` | a domain | its subdomains, contexts and external systems, and their relations |
| `:system` | a domain | its contracts in their contexts, what one consumes from another, and its process modules with the contracts of their events |
| `:landscape` | a landscape | several domains, and the names on the wire between them: see [Join applications](join-applications.md) |
| `:all`, the default | any document | each node and relation: the test bed of the drawing layer |

`EhOsContract.GraphRenderer.View` gives each view in full. `EhOsContract.GraphRenderer.View.views/1`
lists the views that a document has, with their titles.

## What can the reader do in a picture?

- **Move the picture.** Drag to pan. To zoom, use Ctrl or ⌘ with the wheel, or pinch on a
  trackpad. The wheel alone scrolls the page. The zoom menu at the top right has "Closer",
  "Farther", "Readable" and "Whole picture".
- **Select.** Click a card, the title of a group, a label or an arrow. The panel opens and says
  what it is. Click it again, click the close button of the panel, or press Escape to clear the
  selection.
- **Search.** Type in the search of the bar. The cards that do not match become faint. Press Enter
  to select the first match and move the picture to it.
- **Show or hide the log.** If the overlay is of this version of the document, a switch in the
  bar shows or hides the numbers of the log.
- **Focus.** "Focus on the selection" draws only the selection and what its relations reach.
  "Show the whole picture" draws all of it again.
- **Follow a name.** A name in the panel selects that node, also if the picture does not draw it.
- **Read the facts of the code.** The panel says the business first. The facts of the code, such
  as a grant or a stored type, are under "Technical details", which the reader unfolds.

A picture starts at a size that the reader can read. If it does not fit at that size, it starts
at its left or top edge. The reader then pans to the rest, or asks for the whole picture.

The panel is a sidebar at the right of the window, as tall as the window. It lies over the page,
so it does not change the size of a canvas. Only one panel is open on a page: a selection in one
canvas closes the panel of another canvas. The reader drags the left edge of the panel to set
its width, and the browser keeps that width. The panel opens at the width
`--eh-os-contract-graph-panel-width`, which you can set.

If the width of a canvas changes, the canvas fits the picture to it again, unless the reader has
zoomed or panned. While the reader pans or zooms, the browser moves the graph as one layer, and
does not paint it again.

## What can go wrong

- **The picture has no numbers of the log.** The `document_digest` of the overlay is not the
  `digest` of the document. The overlay is of another version of the document, so the canvas does
  not draw it.
- **A click on a card selects nothing.** The id of the card has a carriage return or a NUL. The
  browser changes both in the id that a click sends. A `select` of the id opens its panel, but the
  picture does not move to it.

## Which Content-Security-Policy does the page need?

The package works under a Content-Security-Policy of `default-src 'self'`:

- It renders no `style` attribute and no inline `<style>`, and it uses no `eval`.
- The script keeps the positions and the sizes in constructed stylesheets.
- The zoom, and the edge of the panel while the reader drags it, are Web Animations. WebKit styles
  the whole page again each time a stylesheet changes, so a change on each frame made Safari
  stutter.
- The only style that the package sets is the tap highlight of d3-zoom on a touch device. It sets
  it through the CSSOM, which the policy allows.

## Next steps

- [Explore a domain](explore-a-domain.md): show each picture of one domain, with a path between
  them.
- [Join applications](join-applications.md): draw a landscape of several applications.
- `EhOsContract.GraphRenderer.Canvas`, `EhOsContract.GraphRenderer.View` and
  `EhOsContract.GraphRenderer.Actors`: the reference.

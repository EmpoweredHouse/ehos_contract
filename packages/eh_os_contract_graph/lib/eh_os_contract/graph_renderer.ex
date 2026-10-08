defmodule EhOsContract.GraphRenderer do
  @moduledoc """
  Draws a `graph.v1` document, and the overlay the log lays over it, in a LiveView
  (plan E13b; `docs/adr/graph-renderer.md`, option C).

  The engine says **what** is in a contract or a domain — its facts, as a document —
  and this package says **how it is drawn**: which facts are shown together (a view,
  `EhOsContract.GraphRenderer.View`), the cards, the arrows, the palette and the
  panels. It does not depend on the engine: a document is plain data, the same from
  `EhOsContract.Graph.Document` in the same process as from `GET <mount>/graph/:contract`
  decoded, so the EHOS Console draws it without the engine's tables, jobs or
  migrations.

  `EhOsContract.GraphRenderer.Canvas` is the component a host renders, with its panel
  (`EhOsContract.GraphRenderer.Panel`); `EhOsContract.GraphRenderer.Actors` is a
  domain's actors as a table, a row selecting one in a canvas. The server
  renders every card and every relation's label in HEEx; a hook in
  `priv/static/eh_os_contract_graph.esm.js` measures them, lays them out with dagre,
  draws the arrows in SVG and pans and zooms with `d3-zoom`. What is selected, and
  what the overlay says, are classes the server puts in the template, so the state
  lives on the server alone.
  """

  use Boundary, deps: [], exports: [Actors, Canvas, View]
end

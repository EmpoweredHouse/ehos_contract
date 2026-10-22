defmodule EhOsContract.GraphRenderer do
  # Plan E13b; the choice of how it draws is option C of `docs/adr/graph-renderer.md`.
  @moduledoc """
  Draws a `graph.v1` document, and the overlay the log lays over it, in a LiveView.

  The engine says **what** is in a contract or a domain — its facts, as a document —
  and this package says **how it is drawn**: which facts are shown together (a view,
  `EhOsContract.GraphRenderer.View`), the cards, the arrows, the palette and the
  panels. It does not depend on the engine: a document is plain data, the same from
  `EhOsContract.Graph.Document` in the same process as from `GET <mount>/graph/:contract`
  decoded, so the EHOS Console draws it without the engine's tables, jobs or
  migrations.

  `EhOsContract.GraphRenderer.Canvas` is the component a host renders, with the panel
  that says what is selected; `EhOsContract.GraphRenderer.Actors` is a domain's actors
  as a table, a row selecting one in a canvas; `EhOsContract.GraphRenderer.Explorer` moves
  through a domain's pictures, and `EhOsContract.GraphRenderer.Landscape` joins several
  applications' domains into one. The server renders every card and every
  relation's label in HEEx; a hook in
  `priv/static/eh_os_contract_graph.esm.js` measures them, lays them out with dagre,
  draws the arrows in SVG and pans and zooms with `d3-zoom`. What is selected, and
  what the overlay says, are classes the server puts in the template, so the state
  lives on the server alone.
  """

  use Boundary, deps: [], exports: [Actors, Canvas, Explorer, Landscape, Loader, View]

  # #400: a host that checks the documents it is sent reads the schema from the package it
  # draws them with, rather than keeping a copy.
  @doc """
  Where the JSON Schema of the `graph.v1` format this package draws is: the same as the
  engine's `priv/schema/graph.v1.json`.
  """
  @spec schema_path() :: Path.t()
  def schema_path, do: Application.app_dir(:eh_os_contract_graph, "priv/schema/graph.v1.json")
end

defmodule EhosContract.GraphRenderer do
  # Plan E13b; the choice of how it draws is option C of `docs/adr/graph-renderer.md`.
  @moduledoc """
  Draws a `graph.v1` document, and the overlay the log lays over it, in a LiveView.

  The engine says **what** is in a contract or a domain — its facts, as a document —
  and this package says **how it is drawn**: which facts are shown together (a view,
  `EhosContract.GraphRenderer.View`), the cards, the arrows, the palette and the
  panels. It does not depend on the engine: a document is plain data, the same from
  `EhosContract.Graph.Document` in the same process as from `GET <mount>/graph/:contract`
  decoded, so the EHOS Console draws it without the engine's tables, jobs or
  migrations.

  `EhosContract.GraphRenderer.Canvas` is the component a host renders, with the panel
  that says what is selected; `EhosContract.GraphRenderer.Actors` is a domain's actors
  as a table, a row selecting one in a canvas; `EhosContract.GraphRenderer.Explorer` moves
  through a domain's pictures, and `EhosContract.GraphRenderer.Landscape` joins several
  applications' domains into one. The server renders every card and every
  relation's label in HEEx; a hook in
  `priv/static/ehos_contract_graph.esm.js` measures them, lays them out with dagre,
  draws the arrows in SVG and pans and zooms with `d3-zoom`. What is selected, and
  what the overlay says, are classes the server puts in the template, so the state
  lives on the server alone.
  """

  use Boundary, deps: [], exports: [Actors, Canvas, Explorer, Landscape, Loader, View]

  # #400: a host that checks the documents it is sent reads the schema from the package it
  # draws them with, rather than keeping a copy.
  @doc """
  Where the JSON Schema of the `graph.v1` format this package draws is, whose `$id` is
  `urn:ehos-contract:schema:graph.v1`: the same file as `EhosContract.Graph.Document.schema_path/0`
  returns for a host that has the engine. A host that checks the documents it is sent
  validates them against it with a JSON Schema validator:

      schema = EhosContract.GraphRenderer.schema_path() |> File.read!() |> JSON.decode!()
  """
  @spec schema_path() :: Path.t()
  def schema_path, do: Application.app_dir(:ehos_contract_graph, "priv/schema/graph.v1.json")
end

defmodule EhosContract.GraphRenderer.Actors do
  # Point 2 of the maintainer's working plan for the Graph screen: the domain's
  # actors, which no picture draws, as a table beside the canvas.
  @moduledoc """
  The actors of a domain's `graph.v1` document as a table, people and systems apart:
  who each is, their role in EHOS, what they answer for and where that comes from; for
  a system, what it stands for and its context.

      <EhosContract.GraphRenderer.Actors.table document={@domain} canvas="map-graph" />

  No picture draws the domain's actors, so a row selects its actor in the canvas whose
  DOM id `canvas` names — a `EhosContract.GraphRenderer.Canvas` of the same document —
  and that canvas's panel says what the role may do, contract by contract. For the owner
  (`audience={:owner}`) the table leaves out the role in EHOS, which is the code's.
  """

  use Phoenix.Component

  alias EhosContract.GraphRenderer.{Audience, Lookup}

  attr :document, :map, required: true, doc: "a domain's `graph.v1` document"
  attr :canvas, :string, required: true, doc: "the DOM id of the canvas a row selects in"
  attr :audience, :atom, default: :engineering, doc: "who reads it: `:engineering` or `:owner`"

  @doc "The table, or nothing when the domain declares no actor."
  @spec table(map()) :: Phoenix.LiveView.Rendered.t()
  def table(assigns) do
    lookup = Lookup.new(assigns.document)

    {systems, people} =
      Enum.split_with(Lookup.nodes(lookup, "actor"), &(&1["actor_kind"] in ["system", "seed"]))

    assigns =
      assign(assigns,
        lookup: lookup,
        people: people,
        systems: systems,
        code?: Audience.code?(assigns.audience)
      )

    ~H"""
    <div :if={@people != [] or @systems != []} class="ehg-actors">
      <table :if={@people != []}>
        <caption>People</caption>
        <thead>
          <tr>
            <th>Actor</th><th :if={@code?}>Role in EHOS</th><th>Responsible for</th><th>Source</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={actor <- @people}>
            <td><.pick actor={actor} canvas={@canvas} /></td>
            <td :if={@code?}><code :if={actor["role"]}>{actor["role"]}</code></td>
            <td>
              <span :for={r <- actor["responsibilities"] || []} class="ehg-cell-line">
                {r["label"] || r["name"]}
              </span>
            </td>
            <td class="ehg-quiet">{actor["source"]}</td>
          </tr>
        </tbody>
      </table>
      <table :if={@systems != []}>
        <caption>Systems</caption>
        <thead>
          <tr><th>Actor</th><th>Stands for</th><th>Context</th><th>Source</th></tr>
        </thead>
        <tbody>
          <tr :for={actor <- @systems}>
            <td><.pick actor={actor} canvas={@canvas} /></td>
            <td>
              <span :for={r <- Lookup.out(@lookup, actor["id"], "backed_by")} class="ehg-cell-line">
                {Lookup.title(@lookup, r["to"])}
              </span>
            </td>
            <td>{Lookup.title(@lookup, actor["context"])}</td>
            <td class="ehg-quiet">{actor["source"]}</td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  # The canvas's id inside a quoted attribute selector, so that any id names it: the
  # dashboard's own have colons and dots.
  defp escape(id), do: id |> String.replace("\\", "\\\\") |> String.replace(~s("), ~s(\\"))

  attr :actor, :map, required: true
  attr :canvas, :string, required: true

  defp pick(assigns) do
    ~H"""
    <button
      type="button"
      class="ehg-ref"
      phx-click="select"
      phx-value-id={@actor["id"]}
      phx-target={~s([id="#{escape(@canvas)}"])}
    >{@actor["label"] || @actor["name"]}</button>
    """
  end
end

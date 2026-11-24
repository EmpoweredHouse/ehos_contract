defmodule EhosContract.GraphRenderer.Icons do
  # The icon of each kind of card, drawn in the card's own colour (`currentColor`) on a
  # 24-unit grid with a stroke, as a card's badge and the legend show it. Shapes, not
  # pictures: a lightning bolt for an event, a clock for a timer, a person for an actor.
  # A kind not in the table gets a dot.
  @moduledoc false

  use Phoenix.Component

  @shapes %{
    "actor" => [{:circle, 12, 8, 4}, {:path, "M4 21c1.5-4 5-6 8-6s6.5 2 8 6"}],
    "command" => [{:path, "M4 12h15M13 6l6 6-6 6"}],
    "unit" => [{:path, "M12 3l8 4.5v9L12 21l-8-4.5v-9zM4 7.5l8 4.5 8-4.5M12 12v9"}],
    "event" => [{:path, "M13 2 4 14h7l-1 8 9-12h-7z"}],
    "status" => [{:circle, 12, 12, 8}, {:circle, 12, 12, 3}],
    "policy" => [{:path, "M6 4v16M6 12h7l5-5M13 12l5 5"}],
    "process_manager" => [{:path, "M20 12a8 8 0 1 1-3-6.2M20 4v5h-5"}, {:circle, 12, 12, 2}],
    "timer" => [{:circle, 12, 13, 8}, {:path, "M12 9v4l3 2M10 2h4"}],
    "effect" => [{:path, "M3 11l18-8-8 18-2-8z"}],
    "read_model" => [{:rect, 3, 4, 18, 16}, {:path, "M3 10h18M9 10v10"}],
    "query" => [{:circle, 11, 11, 7}, {:path, "m20 20-4-4"}],
    "invariant" => [{:rect, 5, 11, 14, 10}, {:path, "M8 11V8a4 4 0 0 1 8 0v3"}],
    "constraint" => [{:path, "M4 5h16l-6 7v6l-4 2v-8z"}],
    "domain_service" => [
      {:circle, 12, 12, 3},
      {:path,
       "M12 3v3M12 18v3M3 12h3M18 12h3M5.6 5.6l2.1 2.1M16.3 16.3l2.1 2.1M5.6 18.4l2.1-2.1M16.3 7.7l2.1-2.1"}
    ],
    "external" => [{:rect, 3, 4, 18, 6}, {:rect, 3, 14, 18, 6}],
    "process" => [{:path, "M3 12h4l3-7 4 14 3-7h4"}],
    "context" => [{:rect, 3, 3, 18, 18}, {:path, "M3 9h18"}],
    "contract" => [{:path, "M6 3h8l5 5v13H6zM14 3v5h5M9 13h7M9 17h5"}],
    "publication" => [
      {:circle, 12, 14, 1.5},
      {:path, "M8 10.5a5 5 0 0 1 8 0M5 7.5a9 9 0 0 1 14 0"}
    ]
  }

  attr :kind, :string, required: true

  @doc "The icon of `kind`, hidden from assistive technology: the kind is said in words beside it."
  @spec icon(map()) :: Phoenix.LiveView.Rendered.t()
  def icon(assigns) do
    assigns = assign(assigns, :shapes, Map.get(@shapes, assigns.kind, [{:circle, 12, 12, 4}]))

    ~H"""
    <svg class="ehg-icon" viewBox="0 0 24 24" aria-hidden="true" focusable="false"><.shape
        :for={shape <- @shapes}
        shape={shape}
      /></svg>
    """
  end

  attr :shape, :any, required: true

  defp shape(%{shape: {:path, d}} = assigns) do
    assigns = assign(assigns, :d, d)
    ~H|<path d={@d} />|
  end

  defp shape(%{shape: {:circle, cx, cy, r}} = assigns) do
    assigns = assign(assigns, cx: cx, cy: cy, r: r)
    ~H|<circle cx={@cx} cy={@cy} r={@r} />|
  end

  defp shape(%{shape: {:rect, x, y, w, h}} = assigns) do
    assigns = assign(assigns, x: x, y: y, w: w, h: h)
    ~H|<rect x={@x} y={@y} width={@w} height={@h} rx="1.5" />|
  end
end

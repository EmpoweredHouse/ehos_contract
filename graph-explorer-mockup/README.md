# A mock-up of one explorable graph

Step 2 of `graph-explorer-plan.md`: a clickable page to see how one canvas of the contracts reads, drawn with the
same two libraries as today's renderer (dagre lays the cards out, d3-zoom pans, zooms and flies the camera), on the
real `graph.v1` documents of the test set for drawing (`sandbox/lib/graph_lab/`) and what the log says over them. It
is not the product, and it goes with the plan before this branch is merged.

**Open** `index.html` in a browser. It needs the network: it loads d3 and dagre from jsDelivr.

The switches at the top are the plan's open decisions, to compare live: going deeper with the camera's flight or by
swapping the picture, doors or the faded map around a home, frames or a colour for subdomains, what the start shows,
and where the trace's arrows are. "Scale" on the left opens AppUnite's computer, a unit of about forty cards, to try
a large inside on.

**The data** is `data.js`, written by `export.exs` from the development database:

```bash
cd sandbox && mix ecto.reset && mix graph_lab.traffic && mix run ../graph-explorer-mockup/export.exs
```

`mix ecto.reset` empties the whole development database; the traffic task says why it wants an empty one.

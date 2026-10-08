# Changelog

The format is [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Unreleased

- **E13b, batch 1: the package and its drawing layer.** `EhOsContract.GraphRenderer.Canvas` draws a
  `graph.v1` document and its overlay: every node a card and every relation a label, rendered in HEEx, laid
  out by the `EhOsContractGraph` hook with dagre and its arrows drawn in SVG; pan and zoom with d3-zoom; a
  click on a card, a label or an arrow selects it and opens a raw panel. A relation from a card to itself is a
  loop out of the card. The graph is fitted to the canvas when its cards change, and the reader's zoom is kept
  otherwise. An overlay of another version of the document is not drawn, and an update that names only some
  attributes keeps the rest. It draws one view for now, everything in the document. The script is an ES module
  and the stylesheet a plain file under `priv/static/`, built by esbuild and committed; nothing in them needs
  more than `default-src 'self'`.

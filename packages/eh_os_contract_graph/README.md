# EhOsContract.GraphRenderer

This package draws the model of an application as a graph in a Phoenix LiveView. This page is for a
developer who wants to show a domain, a contract or a process module on a page of their own
application. It says what the package draws, what it needs, and how to install it.

The engine, [`eh_os_contract`](https://github.com/EmpoweredHouse/eh-os-contract/tree/main/packages/eh_os_contract),
describes each domain, contract and process module as a *graph document*: its facts as JSON, in the
format `graph.v1`. An *overlay* gives what the log says about the same facts, such as how many
times each event occurred. The
[glossary of the engine](https://github.com/EmpoweredHouse/eh-os-contract/blob/main/packages/eh_os_contract/docs/glossary.md)
defines both words. This package draws them:

- a card for each node, such as a command, an event or a contract;
- an arrow for each relation;
- the numbers of the overlay on the cards and the arrows;
- a panel that says what the reader selected.

## What does it draw?

| Component | What it shows | Page |
| --- | --- | --- |
| `EhOsContract.GraphRenderer.Explorer` | The pictures of one domain, which the reader moves through along one path. | [Explore a domain](docs/explore-a-domain.md) |
| `EhOsContract.GraphRenderer.Canvas` | One picture of one graph document, with its panel. | [Draw a graph document](docs/draw-a-document.md) |
| `EhOsContract.GraphRenderer.Actors` | The actors of a domain as a table. A row selects its actor in a canvas. | [Draw a graph document](docs/draw-a-document.md) |
| `EhOsContract.GraphRenderer.Landscape` | The domains of several applications, joined where one publishes an event that another subscribes to. | [Join applications](docs/join-applications.md) |

The package draws 7 pictures, which it calls *views*:

- the full graph of a contract;
- one unit of a contract;
- the lifecycle of an aggregate;
- the stages and promises of a process module;
- the context map of a domain;
- the system of a domain: its contracts in their contexts;
- a landscape of several domains.

An eighth view, `:all`, draws each node and relation of a document. It is the test bed of the
drawing layer. `EhOsContract.GraphRenderer.View` says what each view shows.

The panel says what the reader selected, from the document alone. Some examples:

- for a command: its fields, and who can issue it;
- for an event: its fields, and where it comes from;
- for a reaction: its rules, its delivery and its scenarios;
- for a query: its parameters and its answers;
- for a context: its terms;
- for an actor: its role, and what it can do;
- for an arrow: the scenarios behind it.

## What does it need?

- **At run time**, the package needs `phoenix_live_view`, and `phoenix`, which LiveView needs too.
  `boundary` and `esbuild` are tools of its own build.
- **It does not need the engine.** A graph document is plain data. A document from
  `EhOsContract.Graph.Document` in the same application and a document decoded from
  `GET <mount>/graph/<id>` of another application are the same data.
- **The page needs the script and the stylesheet of the package.**
  [Draw a graph document](docs/draw-a-document.md) tells you how to add them.

The dashboard of [`eh_os_contract_web`](https://github.com/EmpoweredHouse/eh-os-contract/tree/main/packages/eh_os_contract_web)
draws its graphs with this package.

## Install it

Add the package from git, as the other packages of this repository:

```elixir
{:eh_os_contract_graph,
 git: "https://github.com/EmpoweredHouse/eh-os-contract.git",
 sparse: "packages/eh_os_contract_graph"}
```

If your application mounts the dashboard of `eh_os_contract_web`, do not add this package. The
dashboard declares it, and carries its script and its stylesheet in its own. The script of the
dashboard reads the markup that this package renders, so update the two packages together:

```bash
mix deps.update eh_os_contract_web eh_os_contract_graph
```

## Next steps

- [Explore a domain](docs/explore-a-domain.md): show each picture of one domain on one page.
- [Draw a graph document](docs/draw-a-document.md): add the script and the stylesheet, and draw one
  picture.
- [Join applications](docs/join-applications.md): draw a landscape of several applications.

The modules of the package are the reference: each one says what it accepts and what it refuses.

## Licence

Apache 2.0. The script carries dagre and d3-zoom. `NOTICE` says what each one is, its licence, and
how it was taken.

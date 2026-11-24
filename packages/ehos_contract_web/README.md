# EhosContract.Web

This package is a dashboard that shows if an application does what its contracts say. This page is
for a developer who adds the dashboard to an application built on
[`ehos_contract`](https://github.com/EmpoweredHouse/eh-os-contract/tree/main/packages/ehos_contract).
It says what the dashboard shows, and links to the pages that tell you how to add it.

The dashboard reads the *conformance* of the application: the comparison of the log with what the
contracts and the process modules declare. The
[glossary of the engine](https://github.com/EmpoweredHouse/eh-os-contract/blob/main/packages/ehos_contract/docs/glossary.md)
defines each word of the contract language that these pages use.

## What does the dashboard show?

The dashboard has 2 screens, and no more:

- **Contract status:** the conformance of each contract and each process module.
- **Graph:** the pictures of each domain, contract and process module:
  - for a domain: its context map, and its system of contracts;
  - for a contract: its full graph with the numbers of the log over it, and its units with their
    lifecycles;
  - for a process module: its stages, events and promises, with the numbers of the log over them.

The package
[`ehos_contract_graph`](https://github.com/EmpoweredHouse/eh-os-contract/tree/main/packages/ehos_contract_graph)
draws the graphs. A click on a card, an arrow or a label opens a panel that says what it is.

The package also has a read-only JSON API, for a client that does not use the dashboard, such as a
CI job or a renderer.

The dashboard does not show the state of the business, such as the open orders. That is the job of
the application.

## Next steps

- [Mount the dashboard](docs/mount-the-dashboard.md): install the package, add the routes and
  serve the assets.
- [Decide who can see the dashboard](docs/who-can-see-it.md): write the resolver that the
  dashboard and the API need.
- [The JSON API](docs/api.md): the routes, what each one returns, and its errors.

## Why is it not on Hex?

This package is not published on Hex, for 2 reasons:

- It depends on `ehos_contract`, which is not on Hex either. A package on Hex can depend only on
  packages on Hex.
- `priv/static/assets/fonts/` holds 2 fonts of third parties, and `priv/static/assets/app.js`
  carries dagre and d3 from the graph renderer. A package on Hex would distribute the work of
  other people. `NOTICE` gives the attribution. To publish the package is a separate decision.

## Licence

Apache 2.0. `NOTICE` lists the components of third parties.

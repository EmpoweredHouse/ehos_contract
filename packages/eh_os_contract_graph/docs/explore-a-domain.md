# Explore a domain

This page tells you how to show each picture of one domain on one page of your application, with
`EhOsContract.GraphRenderer.Explorer`. It is for a developer who has installed this package. The
reader of the page moves through the pictures along one path. The path goes from the domain to a
contract and one of its units, or to a process module.

## Before you start

- Install the package, as the [README](../README.md) says.
- Add the script and the stylesheet of the package to your page. Steps 1 and 2 of
  [Draw a graph document](draw-a-document.md) tell you how.
- Know the module of the domain, as its graph document names it. Example: `"Lending.Domain"`.

## Write a loader

The explorer gets each graph document and each overlay from a module of your application: a
*loader*, which implements `EhOsContract.GraphRenderer.Loader`. The explorer calls it in the
background.

1. Write `document/2`. It gets a reference and returns `{:ok, document}`, with string keys, as
   JSON decodes it. A reference is one of these:
   - `{:domain, module}`, such as `{:domain, "Lending.Domain"}`;
   - `{:contract, name}`, by the `name` of the contract node in the graph document of the domain,
     such as `{:contract, "lending.circulation"}`;
   - `{:process, name}`, by the `name` of the process node in the same document.

   The `id` of a node, such as `"contract:lending.circulation"`, is not a reference.
2. Write `overlay/2`. It gets the same references. It returns `{:ok, overlay}`, or `{:ok, nil}` if
   the log says nothing.
3. If a document cannot be read, return `{:error, reason}`. The explorer then shows "This picture
   could not be loaded." in place of the picture.

If the engine runs in the same application, read it directly. The moduledoc of
`EhOsContract.GraphRenderer.Loader` has an example. If you have only the JSON API of the
application, read `GET <mount>/graph/domain/<module>`, `<mount>/graph/<name>` and
`<mount>/graph/process/<name>`, each with `/overlay`, and decode them.

If you read another application, keep these rules:

- Use `https`, and do not follow redirects. The loader sends the credential of your application
  with each request.
- Give the credential that the resolver of the other application needs to let your application in.
- Bound the size of each response.
- Give each request a timeout. The explorer waits for the loader with no timeout of its own.
- Render the explorer only for the viewers who can see that application. The explorer does not
  check who the viewer is.

## Render the explorer

1. Render the explorer as a live component, with the domain and the loader:

   ```heex
   <.live_component
     module={EhOsContract.GraphRenderer.Explorer}
     id="graph"
     domain="Lending.Domain"
     loader={MyAppWeb.GraphLoader}
   />
   ```

   To give the loader options, write `loader={{MyAppWeb.GraphLoader, app: "lending"}}`. The
   explorer gives the options to each call. One loader can then serve several applications.

2. To start at a place other than the domain, give `at`:

   ```heex
   <.live_component
     module={EhOsContract.GraphRenderer.Explorer}
     id="graph"
     domain="Lending.Domain"
     loader={MyAppWeb.GraphLoader}
     at={{:contract, "lending.circulation"}}
   />
   ```

   `at` accepts `:domain`, the default, `:processes`, `{:contract, id}` and `{:process, id}`. The
   explorer goes there when the graph document of the domain arrives. The path leads back up from
   there.

3. To show the page to the owner of the business, give `audience={:owner}`. Each card then shows
   the label of its declaration in the words of the client, and the numbers of the log. It does
   not show the facts of the code, such as a module, a stored type or a delivery. Without
   `audience`, the cards show the label and, under it, the name in the code. `audience` is a way
   to read the page, not a permission: the page still holds the ids, which name the code.

**Result:** the page shows the system of the domain: its contracts in their contexts. A domain
with no contract shows its context map instead. Over the
picture, the path starts with the name of the domain. A line under the path says what the
picture shows.

## Which path does the explorer follow?

The path has two branches. *The structure* goes from the domain to a contract, and then to one
of its units. *The processes* are a step beside the domain: the list of its process modules, and
the picture of one.

![The reader opens a contract, then a unit, or a process module from the domain or its list; its events open their contracts.](img/explorer-path.svg)

1. The panel of a contract in the domain has the button "Open this contract". It opens the full
   graph of the contract.
2. The panel of a unit has the button "Open this unit". The panel of an event of the unit has
   "Open its unit".
3. The panel of a process module in the domain has the button "Open this process".
4. The step "Processes" beside the path lists the process modules of the domain. It shows only
   if the domain has a process module.
5. A process module in the list opens its picture: its stages, the events of each stage, and its
   promises.
6. The panel of an event of a process module has the button "Open its contract". It opens the
   contract that records the event, in the structure.

The panel of an event that a contract consumes from another contract also has "Open its
contract". Each step of the path, except the last, is a button back to that place. Each move
shows the first picture of the new place.

Two places can show two pictures. The explorer offers both, and the line under the path says
what the chosen one shows:

| Place | First picture | Second picture | Numbers of the log |
| --- | --- | --- | --- |
| The domain | Contracts: its contracts in their contexts | Contexts and their relations: its context map | on the contracts only |
| A unit with a lifecycle | Commands and events | Lifecycle: its statuses and the events that move it | on the lifecycle only |

A contract and a process module show the numbers of the log. The list of process modules has no
picture: it shows a button for each process module. Only at the domain, the explorer also shows
the table of the actors of the domain.

## What can go wrong

- **A picture shows "This picture could not be loaded."** The loader returned `{:error, reason}`,
  or it failed. The explorer asks the loader again when the reader comes back to the place. A
  loader that fails does not stop the page of the host.
- **The explorer starts at the domain, not at `at`.** The graph document of the domain does not
  name that contract or process module, or it could not be loaded. The explorer also starts at
  the domain for each other value of `at`. A move of the reader before the document arrives wins
  over `at`.
- **A picture has no numbers of the log, and no message.** `overlay/2` failed. The explorer draws
  the picture without the numbers, and asks the loader again when the reader comes back.
- **A new `at` or `audience` changes nothing.** The explorer reads both when it starts. If you
  render it again with another value, it keeps the first.
- **The page fails with an `ArgumentError`.** `audience` is not `:engineering` or `:owner`.

The explorer loads the graph document of the domain first. It loads the document of each place
the first time the reader goes there; a unit uses the document of its contract. It loads an
overlay only for a picture that shows the numbers of the log. It never loads a place that the
documents of the domain do not hold.

## Next steps

- [Draw a graph document](draw-a-document.md): draw one picture without the explorer, and what
  the reader can do in a picture.
- [Join applications](join-applications.md): draw several applications, and open the explorer of
  one from there.
- `EhOsContract.GraphRenderer.Explorer` and `EhOsContract.GraphRenderer.Loader`: the reference.

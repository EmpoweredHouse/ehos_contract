# Join applications

This page tells you how to draw the domains of several applications as one picture, a
*landscape*, with `EhosContract.GraphRenderer.Landscape`. It is for a developer whose application
sees other applications, and who has their graph documents. The landscape shows where one
application publishes an event that another subscribes to.

## Before you start

- Add the script and the stylesheet of the package to your page, as
  [Draw a graph document](draw-a-document.md) says.
- Get the graph document of the domain of each application, with string keys.
  `GET <mount>/graph/domain/<module>` of the JSON API of an application gives it.
- Bound what you read from another application, such as the size of each response. The landscape
  shows each document that you give it.
- Give only the applications that the viewer of the page can see. The landscape does not check
  who the viewer is.

## How does the landscape join the documents?

The graph document of a domain says which of its contracts publish an event to other
applications, and under which name on the wire. It also says which contracts subscribe to an
event by its name. Each document knows only its own side. `join/1` matches the two sides by the
name on the wire.

## Steps

1. Join the documents. Give each one with the name of its application:

   ```elixir
   landscape = EhosContract.GraphRenderer.Landscape.join([{"billing", billing}, {"ledger", ledger}])
   ```

2. If you know that an application is there, but you have no graph document of it, give it with
   `:none`:

   ```elixir
   EhosContract.GraphRenderer.Landscape.join([{"billing", billing}, {"office", :none}])
   ```

3. Draw the landscape with the view `:landscape`:

   ```heex
   <.live_component
     module={EhosContract.GraphRenderer.Canvas}
     id="landscape"
     document={@landscape}
     view={:landscape}
   />
   ```

**Result:** the picture shows these parts:

- **A box for each domain.** It holds the contracts of the domain that publish or subscribe. Its
  title says how many other contracts the domain has.
- **A box for a domain with nothing on the wire.** It is empty, and says how many contracts the
  domain has. It also says that the domain publishes and subscribes to nothing.
- **A card for each name on the wire**, between the boxes. An arrow goes from each contract that
  publishes the name, and to each contract that subscribes to it.
- **A dashed, see-through box for an application with `:none`.** Its title is the name of the
  application and "no graph described". It is empty and has no arrow. The landscape does not know
  the contracts of the application; that does not mean the application has none.

Two domains of one application are joined as two applications are. A name that a document
subscribes to, and that no document of the set publishes, is drawn as coming from outside the
set. The landscape is a document of this package, not a graph document: the engine does not
write it.

## Lead from the landscape to your pages

If your application has a page for each domain, give the canvas `link`. `link` is a function of
the name of the application, the module of the domain and the id of a contract. It gets `nil` for
the contract when it asks for the page of the domain. It returns a path, an `http` or `https`
URL, or `nil` if you have no page.

1. Give `link` to the canvas of the landscape:

   ```heex
   <.live_component
     module={EhosContract.GraphRenderer.Canvas}
     id="landscape"
     document={@landscape}
     view={:landscape}
     link={fn
       application, nil, nil -> ~p"/apps/#{application}"
       application, domain, contract ->
         ~p"/apps/#{application}/domains/#{domain}?#{[contract: contract || ""]}"
     end}
   />
   ```

2. Escape the names when you build the address, as `~p` does. The names come from the documents
   of other applications.
3. On the page of a domain, render the explorer at the contract, with `at={{:contract, id}}`.
   [Explore a domain](explore-a-domain.md) tells you how.

**Result:** the panel of a box offers "Open this domain", and the panel of a contract in a box
offers "Open this contract". Each is a link to what `link` returned. The title of a box that leads
somewhere ends in a mark, "›".

## What can go wrong

- **The box of an application with `:none` has a broken link.** For that box, the panel offers
  "Open this application", and `link` gets `nil` for the domain too. Answer a `nil` domain with
  the page of the application, or with `nil`. The first clause of the example does this.
- **A panel offers no link.** `link` returned `nil`, raised, threw or exited, or returned
  something that is not a path or an `http` or `https` URL. An address that starts with `//`, or
  that has a space that is not escaped, is not one.
- **The landscape has no names on the wire.** The canvas has `audience={:owner}`. The owner does
  not see the wire between applications.
- **A node of a document is missing.** The landscape leaves out a node or a relation that does
  not have the shape of `graph.v1`, such as one with no id. It does not fail the whole landscape.

`link` builds an address and looks nothing up. The canvas calls it for each box when it draws the
picture, and again when the reader selects a box or a contract.

To open the landscape at one application, give the canvas
`select={EhosContract.GraphRenderer.Landscape.box(@landscape, "billing")}`.

## Next steps

- [Explore a domain](explore-a-domain.md): the page that a box of the landscape can lead to.
- `EhosContract.GraphRenderer.Landscape` and `EhosContract.GraphRenderer.Canvas`: the reference.

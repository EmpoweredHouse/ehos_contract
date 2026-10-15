defmodule EhOsContract.GraphRenderer.Landscape do
  # Plan DD, stage G1 (#297): the joining function of the user's decision of 15 October,
  # and the shape of the decision recorded on #297 the same evening — by domain document,
  # by the publication's name on the wire, only what is on the wire.
  @moduledoc """
  Several applications' domains as one picture, joined where one publishes what another
  subscribes to.

  An application says, in its domain's `graph.v1` document, which of its contracts publish
  an event to other applications and under which name on the wire (`publishes`), and which
  take one by its name (`subscribed_by`). Each document knows only its own side. `join/1`
  puts several of them together and matches the two sides by that name, so a publication
  becomes one card with an arrow from every contract that publishes it and to every
  contract that subscribes to it, whichever application each is in. It is how a host that
  sees several applications, as the EHOS Console does, draws them together from the
  documents it already reads, `GET <mount>/graph/domain/<name>` of each:

      landscape =
        Landscape.join([{"taxvision", taxvision_domain}, {"ledger", ledger_domain}])

  ```heex
  <.live_component
    module={EhOsContract.GraphRenderer.Canvas}
    id="landscape"
    document={landscape}
    view={:landscape}
  />
  ```

  The picture has a box per domain, titled with its application and its name, holding
  the contracts that publish or subscribe; the title says how many other contracts the
  domain has, which the landscape leaves out; a domain with nothing on the wire has no
  box. Between the boxes, a card per name on the
  wire. Two domains of one application that pass a publication between them are joined
  just as two applications are. A name some document subscribes to and none of the set
  publishes is still drawn, as coming from outside the set.

  The landscape is a document of this package, of `"kind" => "landscape"`, not a
  `graph.v1` document: the engine does not write it, and nothing but `Canvas` and
  `EhOsContract.GraphRenderer.View` reads it. It keeps the domain documents' facts on its
  nodes and relations, so the panel says of a contract and a publication what it says on
  the domain's own map; their ids are each document's, with its application in front, so
  two applications may have contracts of the same id.
  """

  @typedoc "An application's name, as the host knows it, and one of its domains' `graph.v1` document."
  @type entry :: {application :: String.t(), domain_document :: map()}

  @doc """
  One landscape of the domain documents in `entries`, joined by the names on the wire.

  Each entry is an application's name and a `graph.v1` document of one of its domains, as
  `GET <mount>/graph/domain/<name>` answers it, decoded. An application with several
  domains has an entry for each. The order of the entries is the order of their boxes.

      Landscape.join([{"taxvision", taxvision_domain}, {"ledger", ledger_domain}])
      #=> %{"kind" => "landscape", "nodes" => %{"domain" => [...], "contract" => [...],
      #     "publication" => [...], "event" => [...]},
      #     "relations" => %{"publishes" => [...], "subscribed_by" => [...]}}

  Raises `ArgumentError` for a document that is not a domain's.
  """
  @spec join([entry()]) :: map()
  def join(entries) when is_list(entries) do
    parts = Enum.map(entries, &part/1)
    published = MapSet.new(for p <- parts, r <- p.publishes, do: r["to"])

    publications =
      parts
      |> Enum.flat_map(& &1.publications)
      |> Enum.group_by(& &1["id"])
      |> Enum.map(fn {id, [first | _] = all} ->
        %{
          "id" => id,
          "name" => first["name"],
          "label" => Enum.find_value(all, & &1["label"]),
          "source" => Enum.find_value(all, & &1["source"]),
          "outside" => not MapSet.member?(published, id)
        }
      end)
      |> Enum.sort_by(& &1["name"])

    %{
      "kind" => "landscape",
      "nodes" => %{
        "domain" => Enum.map(parts, & &1.domain),
        "contract" => Enum.flat_map(parts, & &1.contracts),
        "publication" => publications,
        "event" => Enum.flat_map(parts, & &1.events)
      },
      "relations" => %{
        "publishes" => Enum.flat_map(parts, & &1.publishes),
        "subscribed_by" => Enum.flat_map(parts, & &1.subscribed)
      }
    }
  end

  # One domain document's share of the landscape: its box, the contracts on the wire, the
  # events they publish, its publications under the name they share with every other
  # document, and its relations to them.
  defp part({application, %{"kind" => "domain"} = document}) when is_binary(application) do
    at = &"#{application}/#{&1}"
    wire = Map.new(nodes(document, "publication"), &{&1["id"], publication_id(&1["name"])})
    publishes = relations(document, "publishes")
    subscribed = relations(document, "subscribed_by")
    on_wire = MapSet.new(Enum.map(publishes, & &1["from"]) ++ Enum.map(subscribed, & &1["to"]))
    {contracts, others} = Enum.split_with(nodes(document, "contract"), &(&1["id"] in on_wire))
    box = at.("domain:#{document["domain"]}")
    events = MapSet.new(publishes, & &1["event"])

    %{
      domain: %{
        "id" => box,
        "application" => application,
        "domain" => document["domain"],
        "name" => document["name"],
        "label" => "#{application} · #{document["name"]}",
        "others" => length(others)
      },
      contracts:
        for(
          c <- contracts,
          do: %{c | "id" => at.(c["id"])} |> Map.merge(%{"context" => nil, "in" => box})
        ),
      events:
        for(e <- nodes(document, "event"), e["id"] in events, do: %{e | "id" => at.(e["id"])}),
      publications: for(p <- nodes(document, "publication"), do: %{p | "id" => wire[p["id"]]}),
      publishes:
        for r <- publishes do
          %{r | "id" => at.(r["id"]), "from" => at.(r["from"]), "to" => wire[r["to"]]}
          |> Map.update("event", nil, &(&1 && at.(&1)))
        end,
      subscribed:
        for r <- subscribed do
          %{r | "id" => at.(r["id"]), "from" => wire[r["from"]], "to" => at.(r["to"])}
        end
    }
  end

  defp part({application, document}) do
    kind = if is_map(document), do: document["kind"]

    raise ArgumentError,
          "a landscape joins domain documents, got #{inspect(kind)} " <>
            "for the application #{inspect(application)}"
  end

  defp publication_id(name), do: "publication:#{name}"

  defp nodes(document, kind), do: get_in(document, ["nodes", kind]) || []
  defp relations(document, type), do: get_in(document, ["relations", type]) || []
end

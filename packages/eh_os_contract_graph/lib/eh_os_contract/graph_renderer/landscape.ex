defmodule EhOsContract.GraphRenderer.Landscape do
  # Plan DD, stage G1 (#297): the joining function of the user's decision of 15 October,
  # and the shape of the decision recorded on #297 the same evening — by domain document,
  # by the publication's name on the wire, only what is on the wire. The EHOS Console takes
  # the domain documents with each deployment, not from the JSON API.
  @moduledoc """
  Several applications' domains as one picture, joined where one publishes what another
  subscribes to.

  An application says, in its domain's `graph.v1` document, which of its contracts publish
  an event to other applications and under which name on the wire (`publishes`), and which
  take one by its name (`subscribed_by`). Each document knows only its own side. `join/1`
  puts several of them together and matches the two sides by that name, so a publication
  becomes one card with an arrow from every contract that publishes it and to every
  contract that subscribes to it, whichever application each is in. It is how a host that
  sees several applications draws them together from the domain documents it holds; the
  EHOS Console holds those each application submitted with its deployment:

      landscape =
        Landscape.join([{"billing", billing_domain}, {"ledger", ledger_domain}])

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
  domain has, which the landscape leaves out; a domain with nothing on the wire has a box
  all the same, holding none and saying how many contracts it has. Between the boxes, a
  card per name on the wire. Two domains of one application that pass a publication
  between them are joined just as two applications are. A name some document subscribes
  to and none of the set publishes is still drawn, as coming from outside the set.

  The landscape is a document of this package, of `"kind" => "landscape"`, not a
  `graph.v1` document: the engine does not write it, and nothing but `Canvas` and
  `EhOsContract.GraphRenderer.View` reads it. It keeps the domain documents' facts on its
  nodes and relations, so the panel says of a contract and a publication what it says on
  the domain's own map; their ids are each document's, with the entry's place in the list
  in front, so two applications may have contracts of the same id.

  **The documents come from other applications**, so the host bounds what it reads (the
  size of each response) and joins only the applications its viewer may see: the landscape
  shows whatever it is given. A node or a relation a document holds in a shape `graph.v1`
  does not give it — no id, an end that is not a string, a name that is not text — is left
  out rather than failing the whole landscape, and a publication's label and source are
  taken only from the documents that publish it, where one in the set does.
  """

  # The words of a node the landscape draws or names: text, or nothing.
  @words ~w(name label source module)

  @typedoc "An application's name, as the host knows it, and one of its domains' `graph.v1` document."
  @type entry :: {application :: String.t(), domain_document :: map()}

  @doc """
  One landscape of the domain documents in `entries`, joined by the names on the wire.

  Each entry is an application's name and a `graph.v1` document of one of its domains, as
  `GET <mount>/graph/domain/<name>` answers it, decoded. An application with several
  domains has an entry for each. The order of the entries is the order of their boxes.

      Landscape.join([{"billing", billing_domain}, {"ledger", ledger_domain}])
      #=> %{"kind" => "landscape", "digest" => "…", "nodes" => %{"domain" => [...],
      #     "contract" => [...], "publication" => [...], "event" => [...]},
      #     "relations" => %{"publishes" => [...], "subscribed_by" => [...]}}

  Raises `ArgumentError` for an entry that is not an application's name with a domain's
  document (`"kind" => "domain"`), which a host checks before joining what it fetched.
  """
  @spec join([entry()]) :: map()
  def join(entries) when is_list(entries) do
    parts = entries |> Enum.with_index() |> Enum.map(&part/1)
    published = MapSet.new(for p <- parts, r <- p.publishes, do: r["to"])

    # A publication's words come from the documents that publish it, where any does, so a
    # subscriber cannot relabel another's publication.
    publications =
      for(p <- parts, n <- p.publications, do: {n, MapSet.member?(p.sends, n["id"])})
      |> Enum.group_by(&elem(&1, 0)["id"], fn {n, sends} -> {n, sends} end)
      |> Enum.map(fn {id, all} ->
        ordered =
          case for({n, true} <- all, do: n) do
            [] -> Enum.map(all, &elem(&1, 0))
            publishers -> publishers
          end

        %{
          "id" => id,
          "name" => hd(ordered)["name"],
          "label" => Enum.find_value(ordered, & &1["label"]),
          "source" => Enum.find_value(ordered, & &1["source"]),
          "outside" => not MapSet.member?(published, id)
        }
      end)
      |> Enum.sort_by(& &1["name"])

    %{
      "kind" => "landscape",
      "digest" => digest(entries),
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
  # document, and its relations to them. Its ids take the entry's place in the list in
  # front, which no id of a document can make ambiguous.
  defp part({{application, %{"kind" => "domain"} = document}, index})
       when is_binary(application) do
    at = &"#{index}/#{&1}"

    wire =
      for p <- nodes(document, "publication"),
          is_binary(p["name"]) and p["name"] != "",
          into: %{},
          do: {p["id"], "publication:" <> p["name"]}

    publishes =
      for r <- relations(document, "publishes"), Map.has_key?(wire, r["to"]), do: r

    subscribed =
      for r <- relations(document, "subscribed_by"), Map.has_key?(wire, r["from"]), do: r

    on_wire = MapSet.new(Enum.map(publishes, & &1["from"]) ++ Enum.map(subscribed, & &1["to"]))
    {contracts, others} = Enum.split_with(nodes(document, "contract"), &(&1["id"] in on_wire))
    name = text(document["name"])
    box = at.("domain:#{text(document["domain"])}")
    events = MapSet.new(publishes, & &1["event"])

    %{
      domain: %{
        "id" => box,
        "application" => application,
        "domain" => text(document["domain"]),
        "name" => name,
        "label" => "#{application} · #{name}",
        "others" => length(others)
      },
      contracts:
        for(
          c <- contracts,
          do: Map.merge(c, %{"id" => at.(c["id"]), "context" => nil, "in" => box})
        ),
      events:
        for e <- nodes(document, "event"), e["id"] in events do
          contract = if is_binary(e["contract"]), do: at.(e["contract"])
          Map.merge(e, %{"id" => at.(e["id"]), "contract" => contract})
        end,
      publications:
        for(
          p <- nodes(document, "publication"),
          Map.has_key?(wire, p["id"]),
          do: %{p | "id" => wire[p["id"]]}
        ),
      sends: MapSet.new(publishes, &wire[&1["to"]]),
      publishes:
        for r <- publishes do
          event = if is_binary(r["event"]), do: at.(r["event"])

          Map.merge(r, %{
            "id" => at.(r["id"]),
            "from" => at.(r["from"]),
            "to" => wire[r["to"]],
            "event" => event
          })
        end,
      subscribed:
        for r <- subscribed do
          Map.merge(r, %{
            "id" => at.(r["id"]),
            "from" => wire[r["from"]],
            "to" => at.(r["to"]),
            "as" => text(r["as"])
          })
        end
    }
  end

  defp part({{application, %{"kind" => "domain"}}, _index}) do
    raise ArgumentError,
          "a landscape names each application by a string, got #{inspect(application)}"
  end

  defp part({entry, _index}) do
    kind =
      case entry do
        {_application, %{} = document} -> inspect(document["kind"])
        other -> inspect(other, limit: 3)
      end

    raise ArgumentError,
          "a landscape joins {application, domain document} pairs, got #{kind}"
  end

  # Which documents the landscape is of, for a canvas to know it has seen it: each one's
  # digest where it has one.
  defp digest(entries) do
    of =
      for {application, document} <- entries,
          do: {application, document["digest"] || :erlang.phash2(document)}

    :crypto.hash(:sha256, :erlang.term_to_binary(of))
    |> Base.encode16(case: :lower)
    |> binary_part(0, 12)
  end

  # A group of a document as `graph.v1` gives it: a list of objects, each with a string id,
  # and a relation's ends strings too; anything else is left out. Its words are text or
  # nothing.
  defp nodes(document, kind) do
    for n <- group(document, "nodes", kind), is_map(n), is_binary(n["id"]) do
      Map.new(n, fn {k, v} -> {k, if(k in @words, do: text(v), else: v)} end)
    end
  end

  defp relations(document, type) do
    for r <- group(document, "relations", type),
        is_map(r),
        is_binary(r["id"]) and is_binary(r["from"]) and is_binary(r["to"]),
        do: r
  end

  defp group(document, section, key) do
    with %{} = groups <- document[section],
         list when is_list(list) <- groups[key],
         do: list,
         else: (_ -> [])
  end

  defp text(value) when is_binary(value), do: value
  defp text(_value), do: nil
end

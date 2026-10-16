defmodule EhOsContract.GraphRenderer.Audience do
  # Plan DD, stage L4 (#326), the user's decisions of 16 October: the owner reads the model
  # in the client's words, without the engineering around it — what
  # `mix eh_os_contract.pages --audience owner` leaves out of the pages (`EhOsContract.Pages`,
  # `site.audience`), the renderer leaves out of the cards and the panel.
  #
  # Two halves. **The document as the owner reads it** (`read/2`): the same `graph.v1`
  # document without the facts of the code, so that no part of the renderer can print one
  # — no module, stored type or schema version, no delivery, idempotency or correlation
  # keys, no grant EHOS gives, role or scope, no identity, no field without a label, no
  # name in code of a term, and nothing on the wire between applications. A contract, a
  # promise and an event received from another application have no label of their own, so
  # the owner's document gives them one from what they are: a contract its context's, a
  # promise its rule's, in its events' labels, and the event where it comes from.
  # **What the renderer writes itself** — a card's name in code under its label, a field
  # by its name and type, a scenario's data by field — asks `code?/1` where it is written.
  @moduledoc false

  @typedoc "Who reads the picture: the engineer, everything; the owner, the client's words."
  @type t :: :engineering | :owner

  # What a node of any kind says that only the code reads.
  @code ~w(module correlate delivery idempotency capability capabilities role scope identity
           generated schema_version)

  # The wire between applications, which the owner's pages leave out too.
  @wire_nodes ~w(publication)
  @wire_relations ~w(publishes subscribed_by published_as)

  # What a relation says that only the code reads: the inbox, the fields a boundary
  # consults by, a publication's repeat key.
  @code_relation ~w(via_inbox match idempotent_on capability)

  # The lists of fields a node may hold.
  @fields ~w(fields state params)

  @doc "The audience a host or a reader names, or an `ArgumentError` naming what it was given."
  @spec cast(term()) :: t()
  def cast(audience) when audience in [:engineering, :owner], do: audience

  def cast(audience) when audience in ["engineering", "owner"],
    do: String.to_existing_atom(audience)

  def cast(other),
    do: raise(ArgumentError, "audience is :engineering or :owner, got: #{inspect(other)}")

  @doc "Whether `audience` reads the code: names, types and the engineering facts."
  @spec code?(t()) :: boolean()
  def code?(:owner), do: false
  def code?(_engineering), do: true

  @doc "`document` as `audience` reads it: whole for the engineer, without the code for the owner."
  @spec read(map() | nil, t()) :: map() | nil
  def read(document, :engineering), do: document
  def read(nil, _audience), do: nil

  def read(document, :owner) do
    by_id =
      for {_kind, group} <- document["nodes"] || %{},
          node <- group,
          into: %{},
          do: {node["id"], node}

    relations =
      for {type, group} <- document["relations"] || %{},
          type not in @wire_relations,
          into: %{},
          do: {type, Enum.map(group, &relation/1)}

    nodes =
      for {kind, group} <- document["nodes"] || %{},
          kind not in @wire_nodes,
          into: %{},
          do: {kind, Enum.map(group, &node(kind, &1, document, by_id))}

    Map.merge(document, %{"nodes" => nodes, "relations" => relations})
  end

  defp node(kind, node, document, by_id) do
    node
    |> Map.drop(@code)
    |> Map.drop(if kind == "event", do: ["type"], else: [])
    |> labelled_fields()
    |> terms()
    |> titled(kind, document, by_id)
  end

  # A field without a label is the code's: the owner's view leaves it out.
  defp labelled_fields(node) do
    Enum.reduce(@fields, node, fn key, node ->
      case node[key] do
        fields when is_list(fields) ->
          Map.put(node, key, Enum.filter(fields, &is_binary(&1["label"])))

        _none ->
          node
      end
    end)
  end

  defp terms(%{"terms" => terms} = context) when is_list(terms),
    do: %{context | "terms" => Enum.map(terms, &Map.delete(&1, "code"))}

  defp terms(node), do: node

  # A contract has no label: the owner reads it by its context's, and where its context
  # has more than one contract, by the last word of its name after it.
  defp titled(%{"label" => nil} = contract, "contract", document, by_id) do
    context = by_id[contract["context"]]

    siblings =
      Enum.count(
        get_in(document, ["nodes", "contract"]) || [],
        &(&1["context"] == contract["context"])
      )

    label =
      cond do
        context == nil -> nil
        siblings > 1 -> "#{title(context)} · #{last_word(contract["name"])}"
        true -> title(context)
      end

    %{contract | "label" => label}
  end

  # Nor has a promise: the owner reads it by its rule, the events it waits for in their
  # labels, as the owner's pages write it.
  defp titled(%{"label" => nil} = promise, "promise", document, by_id) do
    events = fn type ->
      for(
        r <- get_in(document, ["relations", type]) || [],
        r["to"] == promise["id"],
        do: r["from"]
      )
      |> Enum.map_join(" or ", &title(by_id[&1] || %{"name" => &1}))
    end

    label =
      "After #{events.("opens")}, eventually #{events.("fulfils")}" <>
        if(promise["within"],
          do: " within #{EhOsContract.GraphRenderer.Words.duration(promise["within"])}",
          else: ""
        )

    %{promise | "label" => label}
  end

  # An event another application published has no label here, as the owner's pages say.
  defp titled(%{"label" => nil} = event, "event", _document, _by_id) do
    if Enum.all?(~w(unit declared_as declared_in contract), &(event[&1] == nil)),
      do: %{event | "label" => "An event from another application"},
      else: event
  end

  defp titled(node, _kind, _document, _by_id), do: node

  # The name an event is consumed as, and the units whose numbers a contract keeps, are
  # names in code too.
  defp relation(relation) do
    relation = Map.drop(relation, @code_relation ++ ["units"])

    case relation["events"] do
      events when is_list(events) ->
        %{relation | "events" => Enum.map(events, &Map.delete(&1, "as"))}

      _none ->
        relation
    end
  end

  defp title(node), do: node["label"] || node["name"]

  defp last_word(name) when is_binary(name),
    do: name |> String.split(".") |> List.last() |> String.replace("_", " ")

  defp last_word(_none), do: nil
end

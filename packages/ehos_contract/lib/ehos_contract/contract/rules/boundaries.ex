defmodule EhosContract.Contract.Rules.Boundaries do
  # Plan DD, ID1: a contract's id will prefix every event type it records and the keys
  # of its rows, so it is held well under what a key may be (plan #98).
  @id_bytes 100

  # The layer-L2 rules of D10 and D11 (v2 §16): who may read what, and what crosses
  # to another application. v2 §6 gives them no letter, so they carry the decision's.
  #
  # **D10, a query is a capability.**
  # - A query names `by:`; nobody could be granted one that does not.
  # - Its `scope` is a field of the read model it reads and a parameter of the query,
  #   of the same type.
  # - A command's `scope` (plan E9c) is one of its fields, its unit's identity or
  #   declared, and required; and the command names `by:`, since no grant to a
  #   reaction could carry it. A generated identity is no scope: a command that
  #   creates its aggregate arrives without it.
  # - A scope, a query's or a command's, is one value: not a list, whose elements
  #   would be compared with a grant as one string. A value made of fields is the
  #   domain's to see (L3).
  #
  # **D11, an event leaves only through `publish`.**
  # - `from:` is an event of this contract, and `fields:` are some of its fields,
  #   none of them personal: a copy on a broker cannot be crypto-shredded (v2 §14).
  # - `idempotent_on:` names fields among `fields:`.
  # - The library builds the published name (#697), `<namespace>.<publication>.v<n>`
  #   (`EhosContract.Contract.Published`), and a contract that still writes `as:` is
  #   refused with the line to write. The name is held to the form it always had, so a
  #   publication's name is snake_case, and two publications do not share one. The
  #   namespace is the application's, the domain's `name:`, and may also hold a dash, not
  #   at either end: EHOS names an application with a DNS label, so `my_shop`'s domain is
  #   `:"my-shop"` there (`"my-shop.entry_recorded.v1"`). The namespace keeps the
  #   underscore the pattern always allowed, so a domain named `:dispatch_rig` still
  #   publishes. The domain's `name:` is held to the same segment by the domain
  #   (`EhosContract.Domain.Rules`), so the namespace is never more than one.
  # - A contract has an `id:` (plan DD, ID1; required from ID3), the application's namespace, then one or more
  #   dotted snake_case segments, none of them a version — `"lending.circulation"` — of at
  #   most #{@id_bytes} bytes: it names the contract to readers outside the code, prefixes
  #   its event types (`"<id>.<event>"`), and will prefix its rows' keys, where neither `:`
  #   nor `|` may stand.
  # - `subscribe {namespace, publication, version}` names a published event by the parts
  #   its name is built from, gives it a local name with `as:`, and lists the fields it
  #   reads. A name written as a string is refused with the key to write (#697).
  #
  # **D12, another application's event is a policy's.** An event received through
  # `subscribe` arrives in an inbox and never enters this log
  # (`EhosContract.Inbox`), so only a policy takes it: a read model is rebuilt from the
  # log, an effect's job and a process manager read theirs from it, and none of them
  # would ever see it. One that reacts to such an event takes what a policy's command
  # records instead.
  #
  # Three checks of the same decisions need the domain, and a Mix compiler has it (L3):
  # that every actor in a scoped query's or command's `by:` declares its scope, and that a publication's
  # name and the contract's `id:` are under the application's own namespace.
  @moduledoc false

  alias EhosContract.DslRules
  alias EhosContract.Contract.Published
  alias EhosContract.Contract.Rules

  # A version segment, as `@versioned` ends a publication's name: no segment of a
  # contract's id is one, wherever it stands — the first included, since a domain may
  # be named `:v1`.
  @version ~r/^v[1-9][0-9]*\z/

  # What follows the namespace (`DslRules.namespace?/1`); `\z`, not `$`, which also
  # matches before a final newline.
  @versioned ~r/^(\.[a-z][a-z0-9_]*)+\.v[1-9][0-9]*\z/

  @doc false
  @spec check(map()) :: [DslRules.violation()]
  def check(declarations) do
    read_models = Map.new(declarations.read_models, &{&1.name, &1})
    events = Map.new(Rules.local_events(declarations), &{&1.name, &1})
    identity = Map.new(declarations.units, &{&1.name, &1.identity})

    unit_of =
      for unit <- declarations.units,
          event <- unit.events,
          into: %{},
          do: {event.name, unit.name}

    Enum.concat([
      Enum.flat_map(declarations.queries, &query(&1, read_models)),
      for(u <- declarations.units, c <- u.commands, v <- command(c, u), do: v),
      Enum.flat_map(declarations.publishes, &publish(&1, events, identity, unit_of)),
      shared_names(declarations.publishes),
      for(
        %{from: from, via: :subscribe} = c <- declarations.consumes,
        is_binary(from),
        v <- published(c),
        do: v
      ),
      received_beyond_policies(declarations)
    ])
  end

  defp received_beyond_policies(declarations) do
    received = Rules.received(declarations)

    takers =
      for(r <- declarations.read_models, e <- r.projects, do: {"read model", r, e, r}) ++
        for(e <- declarations.effects, h <- e.handles, do: {"effect", e, h, e}) ++
        for pm <- declarations.process_managers,
            d <- pm.starts_on ++ pm.on ++ pm.ends_on,
            do: {"process manager", pm, d.event, d}

    for {kind, taker, event, at} <- takers, MapSet.member?(received, event) do
      {"D12: #{kind} #{inspect(taker.name)} takes #{inspect(event)}, which arrives from " <>
         "another application into an inbox and never enters this log, so only a policy " <>
         "reacts to it; take the event its command records instead", at}
    end
  end

  defp query(query, read_models) do
    where = "D10: query #{inspect(query.name)}"

    by =
      if query.by == [],
        do: [{"#{where} names no by:, so nobody could be granted it", query}],
        else: []

    scope =
      case query.scope do
        nil ->
          []

        scope ->
          row = read_models |> Map.get(query.reads, %{fields: []}) |> Map.fetch!(:fields)
          row_field = Enum.find(row, &(&1.name == scope))
          param = Enum.find(query.params, &(&1.name == scope))

          cond do
            row_field == nil ->
              [
                {"#{where} is scoped by #{inspect(scope)}, which is not a field of read model " <>
                   "#{inspect(query.reads)}", query}
              ]

            param == nil ->
              [{"#{where} is scoped by #{inspect(scope)}, which is not one of its params", query}]

            row_field.type != param.type ->
              [
                {"#{where} is scoped by #{inspect(scope)}, a #{inspect(row_field.type)} in the read " <>
                   "model and a #{inspect(param.type)} param", query}
              ]

            match?({:list, _}, param.type) ->
              [{"#{where} is scoped by #{inspect(scope)}, #{list(param.type)}", query}]

            true ->
              []
          end
      end

    by ++ scope
  end

  defp command(%{scope: nil}, _unit), do: []

  defp command(command, unit) do
    where = "D10: command #{inspect(command.name)} is scoped by #{inspect(command.scope)}"
    declared = Enum.find(command.fields, &(&1.name == command.scope))

    cond do
      command.by == [] ->
        [{"#{where}, and names no by:, so no grant could carry its scope", command}]

      command.scope in List.wrap(unit.identity) and command.creates and unit.generated != nil ->
        [
          {"#{where}, the identity the library generates, which the command that creates the " <>
             "aggregate arrives without", command}
        ]

      command.scope in List.wrap(unit.identity) ->
        []

      declared == nil ->
        [{"#{where}, which is not one of its fields", command}]

      declared.optional ->
        [{"#{where}, which it declares optional; a grant cannot narrow a missing value", command}]

      match?({:list, _}, declared.type) ->
        [{"#{where}, #{list(declared.type)}", command}]

      true ->
        []
    end
  end

  defp list(type),
    do:
      "a #{inspect(type)}; a scope is one value, and a list's elements would be compared " <>
        "with the grant as one string"

  defp publish(publish, events, identity, unit_of) do
    where = "D11: publication #{inspect(publish.name)}"
    named = written(publish) ++ built_name(where, publish)

    case Map.fetch(events, publish.from) do
      :error ->
        [
          {"#{where} is built from #{inspect(publish.from)}, which is not an event of this contract",
           publish}
        ] ++ named

      {:ok, event} ->
        injected = Map.get(identity, Map.fetch!(unit_of, event.name), [])
        declared = Map.new(event.fields, &{&1.name, &1})
        available = MapSet.new(injected ++ Map.keys(declared))

        empty =
          if publish.fields == [],
            do: [{"#{where} carries no fields", publish}],
            else: []

        unknown =
          for field <- publish.fields, not MapSet.member?(available, field) do
            {"#{where} carries #{inspect(field)}, which event #{inspect(event.name)} does not have",
             publish}
          end

        personal =
          for field <- publish.fields,
              %{personal: p} = declared[field] || %{personal: nil},
              p != nil do
            {"#{where} carries #{inspect(field)}, which is personal; a copy on a broker cannot be " <>
               "erased", publish}
          end

        idempotent =
          for field <- publish.idempotent_on, field not in publish.fields do
            {"#{where} is idempotent on #{inspect(field)}, which it does not carry", publish}
          end

        empty ++ unknown ++ personal ++ idempotent ++ named
    end
  end

  # #697: the name is built, and `as:` is what a contract wrote before.
  defp written(%{as: nil}), do: []

  defp written(publish) do
    [
      {"D11: publish #{inspect(publish.name)} names itself with as: #{inspect(publish.as)}; the " <>
         "library builds the name from the domain's name:, the publication's name and its " <>
         "version: (#{inspect(publish.published_as)} now). Remove as:" <> rename(publish),
       publish}
    ]
  end

  defp rename(publish) do
    case parts(publish.as) do
      {namespace, publication, version} ->
        ", and write `publish #{inspect(String.to_atom(publication))}, version: #{version}` " <>
          "for the name nearest the one written, " <>
          "#{inspect("#{namespace}.#{publication}.v#{version}")}; its subscribers move to it" <>
          relay(publish.name, publication)

      nil ->
        ""
    end
  end

  # A relay is keyed by the declaration's name, so only a new one starts at the head.
  defp relay(name, publication) do
    if Atom.to_string(name) == publication,
      do: "",
      else:
        ". A renamed publication's relay starts at the head of the log, so let the old " <>
          "relay publish what it holds before you deploy the rename"
  end

  @doc false
  # A name written before #697, `<namespace>.<segments>.v<n>`, as the parts it is built
  # from today: the segments joined with underscores. `nil` for any other text.
  @spec parts(term()) :: {String.t(), String.t(), String.t()} | nil
  def parts(name) do
    with true <- versioned?(name),
         [namespace | rest] = String.split(name, "."),
         {segments, ["v" <> version]} <- Enum.split(rest, -1) do
      {namespace, Enum.join(segments, "_"), version}
    else
      _ -> nil
    end
  end

  defp built_name(_where, %{published_as: nil}), do: []
  defp built_name(where, publish), do: name(where, publish.published_as, publish)

  @doc false
  # Plan DD, ID1: D11 of the contract's `id:` (`Rules.contract_id/1`), which stands
  # beside the declarations rather than among them.
  @spec contract_id(%{value: String.t() | nil, at: term()}) :: [{String.t(), term()}]
  # Plan DD, ID3 (#173): the id labels every event the contract records, so there is no
  # contract without one.
  def contract_id(%{value: nil, at: at}) do
    [
      {"D11: the contract names no id:, which labels every event it records; add one, the " <>
         "application's namespace and the contract's name, like `id: \"my-shop.settlement\"`", at}
    ]
  end

  def contract_id(%{value: _, at: _} = id), do: id_form(id, "contract")

  @doc false
  # The form of an `id:` that names `what`, a contract or a process module (plan DD,
  # P2b, #205): the application's namespace, then dotted snake_case segments.
  @spec id_form(%{value: String.t(), at: term()}, String.t()) :: [{String.t(), term()}]
  def id_form(%{value: id, at: at}, what) do
    if is_binary(id) and byte_size(id) <= @id_bytes and contract_id?(id),
      do: [],
      else: [
        {"D11: the #{what}'s id: #{inspect(id)} is not a #{what}'s name: the application's " <>
           "namespace, then dotted snake_case segments, unversioned, at most #{@id_bytes} bytes, " <>
           "like \"my-shop.settlement\"", at}
      ]
  end

  defp contract_id?(id) do
    case String.split(id, ".") do
      [namespace | [_ | _] = rest] = segments ->
        DslRules.namespace?(namespace) and Enum.all?(rest, &DslRules.snake_case?/1) and
          not Enum.any?(segments, &(&1 =~ @version))

      _one ->
        false
    end
  end

  defp shared_names(publishes) do
    for p <- DslRules.duplicates(publishes, & &1.published_as), p.published_as != nil do
      {"D11: publication #{inspect(p.name)} is named #{inspect(p.published_as)}, like an " <>
         "earlier one", p}
    end
  end

  defp published(consumes) do
    where = "D11: subscribe #{inspect(consumes.key || consumes.from)}"

    as =
      if is_atom(consumes.as) and consumes.as != nil,
        do: [],
        else: [{"#{where} needs as: the name the event has in this contract", consumes}]

    fields =
      if consumes.fields == [],
        do: [{"#{where} lists no fields; declare the ones this contract reads", consumes}],
        else: []

    as ++ fields ++ key(where, consumes)
  end

  # #697: the parts a publisher's library builds the name from, each of the form it has
  # there; a string is what a contract wrote before.
  defp key(where, %{key: nil, from: from} = consumes) do
    written =
      case parts(from) do
        {namespace, publication, version} ->
          ": write `subscribe #{Published.key_source("#{namespace}.#{publication}.v#{version}")}`" <>
            ", which names #{inspect("#{namespace}.#{publication}.v#{version}")}"

        nil ->
          ""
      end

    [
      {"#{where} names the published event as a string; name it by its parts, " <>
         "{namespace, publication, version}, from which the library builds the name" <> written,
       consumes}
    ]
  end

  defp key(where, %{key: {namespace, publication, _version}} = consumes) do
    if namespace not in [nil, true, false] and DslRules.namespace?(Atom.to_string(namespace)) and
         DslRules.name?(publication),
       do: [],
       else: [
         {"#{where} is not a published event's key: the publisher's namespace, which may hold " <>
            "a dash but not at either end, its publication's snake_case name and a version, " <>
            "like {:\"my-shop\", :order_placed, 1}", consumes}
       ]
  end

  defp name(where, name, declaration) do
    if versioned?(name),
      do: [],
      else: [
        {"#{where}: #{inspect(name)} is not a versioned name: the application's namespace, " <>
           "which may hold a dash but not at either end, then dotted snake_case segments, ending " <>
           "in .v<n>, like \"my-shop.order_placed.v1\"", declaration}
      ]
  end

  defp versioned?(name) when is_binary(name) do
    case String.split(name, ".", parts: 2) do
      [namespace, rest] -> DslRules.namespace?(namespace) and "." <> rest =~ @versioned
      [_] -> false
    end
  end

  defp versioned?(_name), do: false
end

defmodule EhosContract.Auth.Manifest do
  # The manifest's format is EHOS's, and so is each thing it added over time: `sign_in`;
  # `needs.people` with `ehos.manifest/v3`; `needs.database.seed` and `needs.secrets` with
  # `ehos.manifest/v4`; a role's `may_grant` with `ehos.manifest/v5`; `needs.egress` with
  # `ehos.manifest/v6`; `needs.mail` with `ehos.manifest/v7`; `needs.compute` with
  # `ehos.manifest/v8`; `kind` and `needs.services` with `ehos.manifest/v9`, whose `kind: service`
  # is a utility service's, which this generator never writes; `offers.publishes` and
  # `needs.subscribes` with `ehos.manifest/v10` (#702); a capability naming its
  # declaration's kind; and `contracts` left out, so
  # that an edit to a contract does not change EHOS's authority digest. Scope values on a role
  # binding are a decision of EHOS it has not built: its grants carry none, and no credential it
  # issues has `scp` (#561).
  @moduledoc """
  Extends an application's `ehos.yaml` with what its contracts offer, into EHOS's
  `ehos.manifest/v10` for any `ehos.yaml` when the contracts publish or subscribe to an event,
  and otherwise `ehos.manifest/v9` for an `ehos.yaml/v8`, `ehos.manifest/v8` for an `ehos.yaml/v7`,
  `ehos.manifest/v7` for an `ehos.yaml/v6`,
  `ehos.manifest/v6` for an `ehos.yaml/v5`, `ehos.manifest/v5` for an older file when a role may
  grant another, and otherwise
  `ehos.manifest/v4` for an `ehos.yaml/v4`, `ehos.manifest/v3` for an `ehos.yaml/v3`, and
  `ehos.manifest/v2` for an older one. v3 is v2 whose `ehos_yaml` may be `ehos.yaml/v3`, v4 is v3
  whose `ehos_yaml` may be `ehos.yaml/v4`, v5 is v4 whose roles may carry `may_grant`, v6 is v5
  whose `ehos_yaml` may be `ehos.yaml/v5`, v7 is v6 whose `ehos_yaml` may be `ehos.yaml/v6`, v8
  is v7 whose `ehos_yaml` may be `ehos.yaml/v7`, v9 is v8 whose `ehos_yaml` may be `ehos.yaml/v8`
  and which may carry `kind`, v10 is v9 that may carry `offers.publishes` and
  `needs.subscribes`, and EHOS refuses a manifest that names a file newer than its own version.

  Every key of `ehos.yaml` but `schema` is in the manifest at the same path with the
  same value, and nothing is added to them: no default is filled in. `schema`
  becomes `ehos_yaml`, the version the file is written in. From `ehos.yaml/v2`, that
  includes `sign_in`, empty or not, whose `applications` must not name
  the application the generator finds below; from `ehos.yaml/v3`, `needs.people`, which
  asks that the workload read the company's people; from `ehos.yaml/v4`, `needs.database.seed`,
  the command EHOS runs to seed an ephemeral environment, and `needs.secrets`, the secrets the
  workload is given; from `ehos.yaml/v5`, `needs.egress`, the hosts outside the installation the
  workload reaches, a port left out included as left out. EHOS counts the hosts in the
  manifest's authority, which it computes itself. From `ehos.yaml/v6`, `needs.mail`, how far the
  workload asks to send mail through EHOS and the domains it reads the answers at. From
  `ehos.yaml/v7`, `needs.compute`, the CPU and memory the workload's containers ask for, `1Gi`
  kept as `1Gi`; EHOS holds it to the environment's quota at deploy, and it is no part of the
  manifest's authority. From `ehos.yaml/v8`, `kind`, only when the file gives it, and
  `needs.services`, the utility services the application calls, in the file's order, never the
  application itself; neither is part of the manifest's authority. A file with `kind: service`
  is a utility service's, which has no contract: its manifest is not this generator's to write,
  and it is refused. The generator adds:

    * `application`, the contracts' domain's `name:`. A project with one domain
      takes it from there; a domain without contracts is not counted. A project with
      several says which one the image is in `ehos.yaml`'s `application`, which must
      be one of their names, in EHOS's spelling.
    * `offers`, the capabilities of the commands, queries and recordings a human actor
      may make, and, as roles, the human actors that hold at least one of them, each with
      `may_grant`, the roles of the actors its actor's `may_grant:` names, when it names any. A
      capability names its declaration as `command`, `query` or `record`, which only
      an EHOS recent enough to know these kinds accepts; an earlier EHOS refuses a
      manifest that offers a query or a recording. Scopes are absent:
      EHOS's manifest has no field for them yet, so a scoped command or query is offered,
      and every call to it through EHOS is refused `:unscoped_grant` until a role binding
      in EHOS can carry scope values, which none does yet.
    * `offers.publishes`, only when a contract publishes: each `publish` of the domain's
      contracts, by the name the library builds, with the fields it carries, each with its
      type as the contract declares it, and its `idempotent_on:`, when it names any. EHOS
      compares and shows a type and does not read it: an atom is written as its name, such as
      `id`, and any other type as the Elixir term, such as `{:list, :id}`, a reference to an
      entity as `id` and an enum's members by name, sorted.
    * `needs.subscribes`, only when a contract subscribes: each published event of another
      application that a policy handles, by its name, with the inboxes that take it,
      `<contract id>:inbox:<name>`. A `subscribe` no policy handles has no inbox, so it is
      left out, as it is from the contract's capabilities.
    * `engine`, the `ehos_contract` version that wrote it.

  `contracts` is not written. EHOS counts it in the manifest's authority digest, and
  a contract's `version` moves with any edit, a label or a scenario included. Every
  such edit would then ask for `ehos.application.register` at deploy though no
  one's authority changed. `engine` is in the manifest digest
  only.
  """

  alias EhosContract.Model

  # What the generator writes. `ehos.yaml` holds none of these but `schema`, which becomes
  # `ehos_yaml`, and `application`, which the generator checks and keeps; a later version that
  # held another would be refused rather than overwritten, as agreed with EHOS.
  @generated ~w(ehos_yaml engine contracts offers)
  # EHOS's rule for an application's name, in v1 and v2: a DNS label that starts with a letter.
  @application ~r/\A[a-z]([-a-z0-9]*[a-z0-9])?\z/u
  @max_application 63

  @doc """
  Builds an `ehos.manifest/v2`, `v3`, `v4`, `v5`, `v6`, `v7`, `v8`, `v9` or `v10` document from an
  `ehos.yaml` already read by `EhosContract.Auth.EhosYaml.read/1`, the registered domains and the
  registered contracts.

  The map is taken as `read/1` returns it, already refused when EHOS would refuse
  it; a key `read/1` would refuse goes into the manifest. Only the contracts of the
  selected domain are read. Raises `ArgumentError`, with what to change, when the map is not a
  read `ehos.yaml`, when it says `kind: service`, a utility service's file, when
  `needs.services` names the application itself, when no domain or more than one fits, when the domain's name is not one EHOS takes for an application, when a
  command, query, recording or role's actor is past 63 characters or has an empty label,
  when no human holds any capability, when an actor's `may_grant:` names an actor that holds
  none and so is no role, when the events the contracts publish and subscribe to are past
  what EHOS takes or not under the application's name, or when a contract of another domain
  publishes or subscribes to one.
  """
  @spec build(map(), [module() | map()], [module() | map()]) :: map()
  def build(%{"schema" => ehos_yaml} = file, domains, contracts) do
    ensure_disjoint!(file)
    ensure_application!(file)

    domains = Enum.map(domains, &Model.fetch/1)
    contracts = Enum.map(contracts, &Model.fetch/1)
    domain = select_domain!(domains, contracts, file["application"])
    application = application!(domain)
    not_its_own!(file, application)
    not_a_service_of_its_own!(file, application)
    models = Enum.filter(contracts, &(&1.domain == domain.module))
    if models == [], do: raise(ArgumentError, "#{inspect(domain.module)} has no contracts")
    no_events_of_another_domain!(contracts, domain, application)

    offers = offers(application, domain, models)
    publishes = publications(models)
    subscribes = subscriptions(models)
    ensure_events!(application, publishes, subscribes)

    schema =
      if publishes == [] and subscribes == [],
        do: manifest_schema(ehos_yaml, offers),
        else: "ehos.manifest/v10"

    file
    |> Map.merge(%{
      "schema" => schema,
      "ehos_yaml" => ehos_yaml,
      "application" => application,
      "offers" => put_present(offers, "publishes", publishes),
      "engine" => %{"name" => "ehos_contract", "version" => EhosContract.version()}
    })
    |> put_subscribes(subscribes)
  end

  def build(_file, _domains, _contracts) do
    raise ArgumentError,
          "build/3 takes ehos.yaml as EhosContract.Auth.EhosYaml.read/1 returns it, with its schema"
  end

  @doc """
  The versions of EHOS's manifest `build/3` can write, oldest first: what this package
  produces, and what an EHOS has to accept for every manifest it writes to be deployed.

      iex> EhosContract.Auth.Manifest.schemas()
      ["ehos.manifest/v2", "ehos.manifest/v3", "ehos.manifest/v4", "ehos.manifest/v5", "ehos.manifest/v6", "ehos.manifest/v7", "ehos.manifest/v8", "ehos.manifest/v9", "ehos.manifest/v10"]

  `build/3` writes `ehos.manifest/v10` for any `ehos.yaml` when the contracts publish or
  subscribe to an event. Otherwise it writes `ehos.manifest/v9` for an `ehos.yaml/v8`,
  `ehos.manifest/v8` for an `ehos.yaml/v7`, `ehos.manifest/v7` for an `ehos.yaml/v6` and `ehos.manifest/v6` for an `ehos.yaml/v5`, whether or not a role may grant
  another; for an older file `ehos.manifest/v5` when a role may grant another, and otherwise
  `ehos.manifest/v4` for an `ehos.yaml/v4`, `ehos.manifest/v3` for an `ehos.yaml/v3` and
  `ehos.manifest/v2` for an older one.
  """
  @spec schemas() :: [String.t()]
  def schemas,
    do: [
      "ehos.manifest/v2",
      "ehos.manifest/v3",
      "ehos.manifest/v4",
      "ehos.manifest/v5",
      "ehos.manifest/v6",
      "ehos.manifest/v7",
      "ehos.manifest/v8",
      "ehos.manifest/v9",
      "ehos.manifest/v10"
    ]

  # EHOS's rule: a manifest keeps the meaning it had when EHOS accepted it, so the version that
  # can carry `needs.people` is a new one, and so is the one that can carry a seed or secrets,
  # and the one whose roles may grant others, which takes every
  # `ehos.yaml` v4 does, and the one that can carry the hosts outside the installation, which
  # takes a role that may grant too, and the one that can carry mail, and the one that can carry
  # compute, and the one that can carry a kind and utility services; an older file, and a domain
  # without a rule, keep their older manifest.
  defp manifest_schema("ehos.yaml/v8", _offers), do: "ehos.manifest/v9"
  defp manifest_schema("ehos.yaml/v7", _offers), do: "ehos.manifest/v8"
  defp manifest_schema("ehos.yaml/v6", _offers), do: "ehos.manifest/v7"
  defp manifest_schema("ehos.yaml/v5", _offers), do: "ehos.manifest/v6"

  defp manifest_schema(ehos_yaml, %{"roles" => roles}) do
    if Enum.any?(roles, &Map.has_key?(&1, "may_grant")),
      do: "ehos.manifest/v5",
      else: manifest_schema(ehos_yaml)
  end

  defp manifest_schema("ehos.yaml/v4"), do: "ehos.manifest/v4"
  defp manifest_schema("ehos.yaml/v3"), do: "ehos.manifest/v3"
  defp manifest_schema(_older), do: "ehos.manifest/v2"

  defp ensure_disjoint!(file) do
    case Enum.filter(@generated, &Map.has_key?(file, &1)) do
      [] ->
        :ok

      keys ->
        raise ArgumentError,
              "ehos.yaml holds #{Enum.join(keys, ", ")}, which the generator writes; it does not " <>
                "overwrite a key of ehos.yaml"
    end
  end

  # A utility service has no contract, and EHOS refuses its manifest when it offers a capability or a
  # role or names a contract, so a project with contracts never writes one: the file is the wrong
  # one, or the project is not a utility service.
  defp ensure_application!(%{"kind" => "service"}) do
    raise ArgumentError,
          "ehos.yaml says kind: service, a utility service, which has no contract; this project " <>
            "has contracts, so it is an application. Remove kind: service, or write kind: " <>
            "application. A utility service's manifest is written from its ehos.yaml alone, " <>
            "not by this task"
  end

  defp ensure_application!(_file), do: :ok

  defp select_domain!([], _contracts, _wanted),
    do: raise(ArgumentError, "no EhosContract.Domain is registered")

  # Without a name, only the domains with contracts are counted: a domain still without one is
  # not an image's.
  defp select_domain!(domains, contracts, nil) do
    case Enum.filter(domains, fn domain -> Enum.any?(contracts, &(&1.domain == domain.module)) end) do
      [domain] ->
        domain

      [] ->
        raise ArgumentError, "no registered domain has contracts. Registered: #{known(domains)}"

      many ->
        raise ArgumentError,
              "the project has #{length(many)} domains with contracts; say which one this image " <>
                "is in ehos.yaml, as application: <name>. Registered: #{known(many)}"
    end
  end

  # `ehos.yaml` spells the name as EHOS does, so a domain named with `_` is found under its dashed
  # spelling too, and told to take it.
  defp select_domain!(domains, _contracts, wanted) do
    exact = Enum.filter(domains, &(to_string(&1.name) == wanted))
    dashed = Enum.filter(domains, &(String.replace(to_string(&1.name), "_", "-") == wanted))

    case {exact, dashed} do
      {[domain], _dashed} ->
        domain

      {[], [domain]} ->
        domain

      {[], []} ->
        raise ArgumentError,
              "ehos.yaml names application: #{wanted}, and no registered domain has that " <>
                "name:. Registered: #{known(domains)}"

      {exact, dashed} ->
        many = if exact == [], do: dashed, else: exact
        modules = many |> Enum.map(&inspect(&1.module)) |> Enum.sort() |> Enum.join(", ")

        raise ArgumentError,
              "domain #{inspect(wanted)} is ambiguous; matching modules: #{modules}; give one of " <>
                "them another name:"
    end
  end

  defp known(domains) do
    domains
    |> Enum.map(&"#{&1.name} (#{inspect(&1.module)})")
    |> Enum.sort()
    |> Enum.join(", ")
  end

  # The domain's `name:` is the application's name in EHOS, and EHOS's rule for it is narrower than
  # the engine's (D11): no `_`, at most 63 characters, never `ehos`.
  defp application!(domain) do
    name = to_string(domain.name)

    if application?(name) do
      name
    else
      raise ArgumentError,
            "#{inspect(domain.module)}'s name: #{inspect(domain.name)} is not a name EHOS takes " <>
              "for an application: lowercase letters, digits and dashes, starting with a letter, " <>
              "not ending with a dash, at most #{@max_application} characters, and not ehos." <>
              suggestion(name)
    end
  end

  # EHOS's rule for `sign_in`: the list names the other applications; its own it always signs in
  # to. The reader checks it against an `application` the file names, and this against the one
  # found.
  defp not_its_own!(%{"sign_in" => %{"applications" => applications}}, application) do
    if application in applications do
      raise ArgumentError,
            "ehos.yaml's sign_in.applications names #{application}, the application this " <>
              "manifest is of; it signs people in to its own application without naming it"
    end
  end

  defp not_its_own!(_file, _application), do: :ok

  # EHOS's rule for `needs.services`: an application is not a utility service, so it never calls
  # itself as one. The schema cannot say it, since the application may be the domain's name.
  defp not_a_service_of_its_own!(%{"needs" => %{"services" => services}}, application) do
    if Enum.any?(services, &(&1["name"] == application)) do
      raise ArgumentError,
            "ehos.yaml's needs.services names #{application}, the application this manifest " <>
              "is of; an application is not a utility service, so it names only the services " <>
              "it calls"
    end
  end

  defp not_a_service_of_its_own!(_file, _application), do: :ok

  @doc false
  # Whether EHOS takes `name` for an application. `EhosContract.Auth.child_spec/1` holds the
  # application of the configured audience to it (#180).
  @spec application?(String.t()) :: boolean()
  def application?(name),
    do:
      Regex.match?(@application, name) and String.length(name) <= @max_application and
        name != "ehos"

  # A name to use only when there is one EHOS takes: `_` as `-`, within 63 characters, no dash last.
  defp suggestion(name) do
    candidate =
      name
      |> String.replace("_", "-")
      |> String.slice(0, @max_application)
      |> String.trim_trailing("-")

    if application?(candidate),
      do: " Rename the domain, such as name: :#{inspect(candidate)}",
      else: " Rename the domain"
  end

  defp offers(application, domain, models) do
    declared = declared_capabilities(application, domain, models)
    ensure_unique!(declared)

    capabilities = declared |> Enum.map(& &1.capability) |> Enum.sort_by(& &1["name"])
    roles = roles(application, domain, declared)

    ensure_ehos_takes!(domain, declared, roles)

    if capabilities == [] or roles == [] do
      raise ArgumentError,
            "#{inspect(domain.module)} has no capabilities a human holds, so it cannot offer " <>
              "the capabilities and roles an ehos.manifest/v2 requires"
    end

    %{"capabilities" => capabilities, "roles" => roles}
  end

  # EHOS's limits on what a manifest offers, which the engine's own names do not keep: a
  # declaration and the part of a role after the dot at most 63 characters. A label a
  # person reads before binding a role is never empty either; the DSLs refuse a blank one (N1,
  # D1), and this still does for a model handed over as a map. Each is named here, not at deploy.
  defp ensure_ehos_takes!(domain, declared, roles) do
    commands = Enum.map(declared, &{&1.kind, &1.declaration, &1.capability["label"]})

    actors =
      for role <- roles,
          actor = Enum.find(domain.actors, &("#{domain.name}.#{&1.name}" == role["name"])),
          do: {:actor, to_string(actor.name), actor.label}

    reasons =
      Enum.flat_map(Enum.uniq(commands ++ actors), fn {kind, name, label} ->
        too_long =
          if String.length(name) > @max_application,
            do: ["#{kind} :#{name} is #{String.length(name)} characters; EHOS takes at most 63"],
            else: []

        empty = if String.trim(label) == "", do: ["#{kind} :#{name} has an empty label"], else: []
        too_long ++ empty
      end)

    if reasons != [] do
      raise ArgumentError,
            "EHOS would refuse what the contracts offer:\n" <>
              Enum.map_join(reasons, "\n", &"  #{&1}")
    end
  end

  # A command, a query and a recording a human actor may make, each named by its declaration's
  # kind, as EHOS names it. A capability no human holds is not offered: no role would hold it.
  defp declared_capabilities(application, domain, models) do
    actors = Map.new(domain.actors, &{&1.name, &1})

    for model <- models,
        {name, access} <- Model.capabilities(model),
        access.kind in [:command, :query, :record] do
      declaration = declaration!(model, access)

      principals =
        access.roles
        |> Enum.map(&role_actor!(&1, application, actors))
        |> Enum.map(&to_string(&1.kind))
        |> Enum.uniq()
        |> Enum.sort()

      %{
        kind: access.kind,
        declaration: to_string(declaration.name),
        capability: %{
          Atom.to_string(access.kind) => to_string(declaration.name),
          "name" => name,
          "label" => declaration.label,
          "principals" => principals
        },
        roles: access.roles
      }
    end
  end

  defp declaration!(model, %{kind: kind, name: name}) do
    declarations =
      case kind do
        :command -> model.commands
        :query -> model.queries
        :record -> model.events
      end

    Enum.find(declarations, &(&1.name == name))
  end

  defp role_actor!(role, application, actors) do
    prefix = application <> "."

    with true <- String.starts_with?(role, prefix),
         name <- String.replace_prefix(role, prefix, ""),
         {:ok, actor} <- Enum.find_value(actors, :error, &actor_named(&1, name)) do
      actor
    else
      _ -> raise ArgumentError, "capability names unknown role #{inspect(role)}"
    end
  end

  defp actor_named({name, actor}, wanted) do
    if to_string(name) == wanted, do: {:ok, actor}, else: nil
  end

  defp ensure_unique!(declared) do
    duplicates =
      declared
      |> Enum.frequencies_by(& &1.capability["name"])
      |> Enum.filter(fn {_name, count} -> count > 1 end)
      |> Enum.map(&elem(&1, 0))
      |> Enum.sort()

    if duplicates != [] do
      raise ArgumentError,
            "capabilities are declared by more than one contract: #{Enum.join(duplicates, ", ")}"
    end
  end

  defp roles(application, domain, declared) do
    capabilities_by_role =
      for item <- declared,
          role <- item.roles,
          reduce: %{} do
        acc -> Map.update(acc, role, [item.capability["name"]], &[item.capability["name"] | &1])
      end

    for actor <- domain.actors,
        actor.kind == :human,
        name = "#{application}.#{actor.name}",
        capabilities = Map.get(capabilities_by_role, name, []),
        capabilities != [] do
      {actor,
       %{
         "name" => name,
         "label" => actor.label,
         "capabilities" => Enum.sort(capabilities)
       }}
    end
    |> grant_rules(application, domain)
    |> Enum.sort_by(& &1["name"])
  end

  # Each role's grant rule, as the roles of the actors its actor's `may_grant:` names. D4 holds a
  # compiled domain's rules to other person actors, each once; a domain given as a map has not
  # been through it, so what EHOS would refuse is refused here too, with what to change. A person
  # who holds no capability is no role: a rule naming one would name a role the manifest does not
  # declare, and a rule of one would go nowhere. A system grants nothing, and rules that lead back to
  # a role are refused here as D4 and EHOS refuse them.
  defp grant_rules(roles, application, domain) do
    held = MapSet.new(roles, fn {actor, _role} -> actor.name end)
    people = for %{kind: :human, name: name} <- domain.actors, into: MapSet.new(), do: name

    ruled_systems =
      for %{kind: kind, name: name} = actor <- domain.actors,
          kind != :human,
          Map.get(actor, :may_grant, []) != [],
          do: name

    if ruled_systems != [] do
      grant_error!(
        domain,
        ruled_systems,
        "is a system and cannot have may_grant; only a person brings people in"
      )
    end

    ruled_without_role =
      for %{kind: :human, name: name} = actor <- domain.actors,
          Map.get(actor, :may_grant, []) != [],
          not MapSet.member?(held, name),
          do: name

    if ruled_without_role != [] do
      grant_error!(
        domain,
        ruled_without_role,
        "has may_grant but holds no capability, so is no role and grants nothing; give it a " <>
          "capability, or take may_grant out"
      )
    end

    ruled =
      for {actor, role} <- roles do
        case Map.get(actor, :may_grant, []) do
          [] ->
            role

          granted ->
            Map.put(
              role,
              "may_grant",
              granted!(granted, actor, held, people, domain, application)
            )
        end
      end

    refuse_cycles!(roles, domain)
    ruled
  end

  # Every rule is valid by now: other roles, each once. A cycle among them is what is left.
  defp refuse_cycles!(roles, domain) do
    edges =
      for {actor, _role} <- roles,
          to <- Map.get(actor, :may_grant, []),
          uniq: true,
          do: {actor.name, to}

    graph = :digraph.new()

    cyclic =
      try do
        for {from, to} <- edges do
          :digraph.add_vertex(graph, from)
          :digraph.add_vertex(graph, to)
          :digraph.add_edge(graph, from, to)
        end

        :digraph_utils.cyclic_strong_components(graph)
      after
        :digraph.delete(graph)
      end

    case cyclic |> List.flatten() |> Enum.sort() do
      [] ->
        :ok

      on_cycles ->
        {named, rest} = Enum.split(on_cycles, 3)
        more = if rest == [], do: "", else: "and #{length(rest)} more "

        grant_error!(
          domain,
          named,
          more <>
            "have may_grant rules that lead back to them: a holder would grant their own role " <>
            "through another; take one rule of each cycle out"
        )
    end
  end

  defp granted!(granted, actor, held, people, domain, application) when is_list(granted) do
    where = "actor #{inspect(actor.name)}'s may_grant"

    reasons =
      [
        if(actor.name in granted, do: "names the actor itself"),
        case for({name, count} <- Enum.frequencies(granted), count > 1, do: name) do
          [] -> nil
          twice -> "names #{Enum.map_join(twice, ", ", &inspect/1)} twice"
        end,
        case Enum.reject(granted, &(&1 == actor.name or MapSet.member?(people, &1))) do
          [] ->
            nil

          others ->
            "names #{Enum.map_join(others, ", ", &inspect/1)}, no person actor of this domain"
        end,
        case Enum.filter(granted, &(MapSet.member?(people, &1) and not MapSet.member?(held, &1))) do
          [] ->
            nil

          roleless ->
            "names #{Enum.map_join(roleless, ", ", &inspect/1)}, which holds no capability and so " <>
              "is no role; give it a capability, or take it out of may_grant"
        end
      ]
      |> Enum.reject(&is_nil/1)

    if reasons != [], do: grant_error!(domain, [actor.name], Enum.join(reasons, "; "), where)

    granted |> Enum.map(&"#{application}.#{&1}") |> Enum.sort()
  end

  defp granted!(granted, actor, _held, _people, domain, _application),
    do:
      grant_error!(
        domain,
        [actor.name],
        "is #{inspect(granted)}, not a list of person actors",
        "actor #{inspect(actor.name)}'s may_grant"
      )

  defp grant_error!(domain, names, reason, where \\ nil) do
    where = where || "actor #{Enum.map_join(names, ", ", &inspect/1)}"
    raise ArgumentError, "#{inspect(domain.module)}: #{where} #{reason}"
  end

  # EHOS's limits on a manifest's events, which the engine's own do not keep.
  @max_events 100
  @max_fields 100
  @max_consumers 20
  @max_consumer 255
  @max_event_name 255
  @max_field_name 63
  @max_type 255
  @event_tail ~r/\A(\.[a-z][a-z0-9_]*)+\.v[1-9][0-9]*\z/
  # EHOS's rule for a type: printable ASCII, no space at either end. The engine takes any atom as an
  # enum's member, so a type can break it.
  @type_text ~r/\A[!-~](?:[ -~]*[!-~])?\z/

  # Each `publish` of the domain's contracts, by the name the library builds (#701), with the
  # fields of its source event it carries, as `ehos_contract.lock` reads them.
  defp publications(models) do
    for model <- models, publication <- model.publishes do
      event = Enum.find(model.events, &(&1.name == publication.from))

      fields =
        for field <- event.fields, field.name in publication.fields do
          %{"name" => to_string(field.name), "type" => type_text(declared(field.type))}
        end

      put_present(
        %{"name" => publication.as, "fields" => Enum.sort_by(fields, & &1["name"])},
        "idempotent_on",
        # D11 holds each to the fields, not to once; EHOS takes each once.
        publication.idempotent_on |> Enum.map(&to_string/1) |> Enum.uniq() |> Enum.sort()
      )
    end
    |> Enum.sort_by(& &1["name"])
  end

  # A type as a subscriber reads it, as the lock records it, but with a domain value by its name:
  # which entity an id refers to is the publisher's, and an enum's labels are words, not values.
  defp declared({:id, _referent}), do: :id
  defp declared({:list, inner}), do: {:list, declared(inner)}
  defp declared({:enum, members}), do: {:enum, members |> Enum.map(&member/1) |> Enum.sort()}
  defp declared(type), do: type

  defp member({name, _label}), do: name
  defp member(name), do: name

  defp type_text(type) when is_atom(type), do: Atom.to_string(type)
  # Written whole: `inspect/1` alone cuts a list past 50 entries short, so an enum's later members
  # would change no manifest.
  defp type_text(type), do: inspect(type, limit: :infinity, printable_limit: :infinity)

  # Each published event of another application a policy handles, with every inbox that takes it.
  # One no policy handles has no inbox (`EhosContract.Implementations`), and the contract no
  # subscribe grant for it.
  defp subscriptions(models) do
    for model <- models,
        %{kind: :published, from: from, as: as} <- model.consumes,
        Enum.any?(model.policies, &(as in &1.handles)) do
      {from, "#{model.id}:inbox:#{as}"}
    end
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.map(fn {name, consumers} ->
      %{"name" => name, "consumers" => consumers |> Enum.uniq() |> Enum.sort()}
    end)
    |> Enum.sort_by(& &1["name"])
  end

  # A relay and an inbox run for every contract the image configures, whatever its domain, and the
  # manifest names only the selected domain's events: another domain's would leave or arrive
  # under no name an approver saw, and EHOS takes no publication outside the application's name.
  defp no_events_of_another_domain!(contracts, domain, application) do
    others =
      for model <- contracts,
          model.domain != domain.module,
          model.publishes != [] or subscriptions([model]) != [],
          do: inspect(model.module)

    if others != [] do
      raise ArgumentError,
            "contracts of a domain other than #{application}, the application this manifest " <>
              "is of, publish or subscribe to an event: #{others |> Enum.sort() |> Enum.join(", ")}. " <>
              "The image runs their relays and inboxes too: build them into the image of their " <>
              "own application, or take their publish and subscribe out"
    end
  end

  # What EHOS would refuse of the events, each named here rather than at deploy.
  defp ensure_events!(application, publishes, subscribes) do
    reasons =
      too_many("publications", publishes, @max_events) ++
        too_many("subscriptions", subscribes, @max_events) ++
        published_twice(publishes) ++
        Enum.flat_map(publishes, &publication_reasons(&1, application)) ++
        Enum.flat_map(subscribes, &subscription_reasons(&1, application))

    if reasons != [] do
      raise ArgumentError,
            "EHOS would refuse the events the contracts publish and subscribe to:\n" <>
              Enum.map_join(reasons, "\n", &"  #{&1}")
    end
  end

  # X7 refuses a name two contracts publish, in a compiled project; a model given as a map has not
  # been through it, and EHOS takes each name once.
  defp published_twice(publishes) do
    for {name, count} <- Enum.frequencies_by(publishes, & &1["name"]),
        count > 1,
        do: "event #{name} is published #{count} times; EHOS takes each name once"
  end

  defp publication_reasons(%{"name" => name, "fields" => fields}, application) do
    # D11 builds a compiled publication's name under the domain's name; a model given as a map
    # has not been through it, and EHOS takes a publication under the application's name only.
    foreign =
      if published_name?(name, application),
        do: [],
        else: [
          "event #{name} is not #{application}.<name>.v<n>: EHOS takes a publication under " <>
            "its application's name, in lowercase segments, the last a version"
        ]

    foreign ++
      long_name(name) ++
      too_many("fields of #{name}", fields, @max_fields) ++
      Enum.flat_map(fields, fn %{"name" => field, "type" => type} ->
        too_long("field #{field} of #{name}", field, @max_field_name) ++
          too_long("the type of field #{field} of #{name}", type, @max_type) ++
          printable("the type of field #{field} of #{name}", type)
      end)
  end

  defp subscription_reasons(%{"name" => name, "consumers" => consumers}, application) do
    namespace = name |> String.split(".", parts: 2) |> hd()

    own =
      if namespace == application,
        do: ["subscription #{name} is to an event of #{application} itself; EHOS refuses it"],
        else: []

    platform =
      if namespace == "ehos",
        do: ["subscription #{name} is under ehos, which publishes no event"],
        else: []

    # The engine's namespace takes `_`; a publisher is an application, whose name EHOS's rule holds.
    publisher =
      if namespace == "ehos" or application?(namespace),
        do: [],
        else: [
          "subscription #{name} is under #{namespace}, which is not a name EHOS takes for an " <>
            "application"
        ]

    long_name(name) ++
      own ++
      platform ++
      publisher ++
      too_many("inboxes that take #{name}", consumers, @max_consumers) ++
      Enum.flat_map(consumers, &too_long("inbox #{&1}", &1, @max_consumer))
  end

  # EHOS's rule for a publication's name: the application, dotted snake_case segments, a version.
  defp published_name?(name, application) do
    case String.split(name, application <> ".", parts: 2) do
      ["", tail] -> "." <> tail =~ @event_tail
      _other -> false
    end
  end

  defp long_name(name), do: too_long("event #{name}", name, @max_event_name)

  defp too_long(what, text, max) do
    length = String.length(text)
    if length > max, do: ["#{what} is #{length} characters; EHOS takes at most #{max}"], else: []
  end

  defp printable(what, text) do
    if text =~ @type_text,
      do: [],
      else: ["#{what} is #{inspect(text)}; EHOS takes printable ASCII characters only"]
  end

  defp too_many(what, list, max) do
    count = length(list)
    if count > max, do: ["#{count} #{what}; EHOS takes at most #{max}"], else: []
  end

  defp put_present(map, _key, []), do: map
  defp put_present(map, key, list), do: Map.put(map, key, list)

  # `needs` is `ehos.yaml`'s, which has no `subscribes`: the generator adds it beside the file's.
  defp put_subscribes(manifest, []), do: manifest

  defp put_subscribes(manifest, subscribes),
    do:
      Map.update(
        manifest,
        "needs",
        %{"subscribes" => subscribes},
        &Map.put(&1, "subscribes", subscribes)
      )
end

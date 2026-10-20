defmodule EhOsContract.Auth.Manifest do
  # In `eh-os`: the manifest is D-52; `sign_in` D-69; `needs.people` and `ehos.manifest/v3`
  # D-81; `needs.database.seed`, `needs.secrets` and `ehos.manifest/v4` D-98 and D-99; a role's
  # `may_grant` and `ehos.manifest/v5` D-112 (eh-os issue #729); a
  # capability naming its declaration's kind D-73; scope values on a binding D-40; `contracts`
  # left out for the authority digest, issue #92.
  @moduledoc """
  Extends an application's `ehos.yaml` with what its contracts offer, into EHOS's
  `ehos.manifest/v5` when a role may grant another, and otherwise `ehos.manifest/v4` for an
  `ehos.yaml/v4`, `ehos.manifest/v3` for an `ehos.yaml/v3`, and `ehos.manifest/v2` for an older
  one. v3 is v2 whose `ehos_yaml` may be `ehos.yaml/v3`, v4 is v3 whose `ehos_yaml` may be
  `ehos.yaml/v4`, v5 is v4 whose roles may carry `may_grant`, and EHOS refuses a manifest that
  names a file newer than its own version.

  Every key of `ehos.yaml` but `schema` is in the manifest at the same path with the
  same value, and nothing is added to them: no default is filled in. `schema`
  becomes `ehos_yaml`, the version the file is written in. From `ehos.yaml/v2`, that
  includes `sign_in`, empty or not, whose `applications` must not name
  the application the generator finds below; from `ehos.yaml/v3`, `needs.people`, which
  asks that the workload read the company's people; from `ehos.yaml/v4`, `needs.database.seed`,
  the command EHOS runs to seed an ephemeral environment, and `needs.secrets`, the secrets the
  workload is given. The generator adds:

    * `application`, the contracts' domain's `name:`. A project with one domain
      takes it from there; a domain without contracts is not counted. A project with
      several says which one the image is in `ehos.yaml`'s `application`, which must
      be one of their names, in EHOS's spelling.
    * `offers`, the capabilities of the commands, queries and recordings a human actor
      may make, and, as roles, the human actors that hold at least one of them, each with
      `may_grant`, the roles of the actors its actor's `may_grant:` names, when it names any. A
      capability names its declaration as `command`, `query` or `record`, which only
      an EHOS recent enough to know these kinds accepts; an earlier EHOS refuses a
      manifest that offers a query or a recording. Scopes and publications are absent:
      EHOS's manifest has no field for them yet, so a scoped command or query is offered,
      and every call to it through EHOS is refused `:unscoped_grant` until a binding can
      carry scope values.
    * `engine`, the `eh_os_contract` version that wrote it.

  `contracts` is not written. EHOS counts it in the manifest's authority digest, and
  a contract's `version` moves with any edit, a label or a scenario included. Every
  such edit would then ask for `ehos.application.register` at deploy though no
  one's authority changed. `engine` is in the manifest digest
  only.
  """

  alias EhOsContract.Model

  # What the generator writes. `ehos.yaml` holds none of these but `schema`, which becomes
  # `ehos_yaml`, and `application`, which the generator checks and keeps; a later version that
  # held another would be refused rather than overwritten (`eh-os` issue #93).
  @generated ~w(ehos_yaml engine contracts offers)
  # EHOS's rule for an application's name, in v1 and v2: a DNS label that starts with a letter.
  @application ~r/\A[a-z]([-a-z0-9]*[a-z0-9])?\z/u
  @max_application 63

  @doc """
  Builds an `ehos.manifest/v2`, `v3`, `v4` or `v5` document from an `ehos.yaml` already read by
  `EhOsContract.Auth.EhosYaml.read/1`, the registered domains and the registered
  contracts.

  The map is taken as `read/1` returns it, already refused when EHOS would refuse
  it; a key `read/1` would refuse goes into the manifest. Only the contracts of the
  selected domain are read. Raises `ArgumentError`, with
  what to change, when the map is not a read `ehos.yaml`, when no domain or more than
  one fits, when the domain's name is not one EHOS takes for an application, when a
  command, query, recording or role's actor is past 63 characters or has an empty label,
  when no human holds any capability, or when an actor's `may_grant:` names an actor that holds
  none and so is no role.
  """
  @spec build(map(), [module() | map()], [module() | map()]) :: map()
  def build(%{"schema" => ehos_yaml} = file, domains, contracts) do
    ensure_disjoint!(file)

    domains = Enum.map(domains, &Model.fetch/1)
    contracts = Enum.map(contracts, &Model.fetch/1)
    domain = select_domain!(domains, contracts, file["application"])
    application = application!(domain)
    not_its_own!(file, application)
    models = Enum.filter(contracts, &(&1.domain == domain.module))
    if models == [], do: raise(ArgumentError, "#{inspect(domain.module)} has no contracts")

    offers = offers(application, domain, models)

    file
    |> Map.merge(%{
      "schema" => manifest_schema(ehos_yaml, offers),
      "ehos_yaml" => ehos_yaml,
      "application" => application,
      "offers" => offers,
      "engine" => %{"name" => "eh_os_contract", "version" => EhOsContract.version()}
    })
  end

  def build(_file, _domains, _contracts) do
    raise ArgumentError,
          "build/3 takes ehos.yaml as EhOsContract.Auth.EhosYaml.read/1 returns it, with its schema"
  end

  @doc """
  The versions of EHOS's manifest `build/3` can write, oldest first: what this package
  produces, and what an EHOS has to accept for every manifest it writes to be deployed.

      iex> EhOsContract.Auth.Manifest.schemas()
      ["ehos.manifest/v2", "ehos.manifest/v3", "ehos.manifest/v4", "ehos.manifest/v5"]

  `build/3` writes `ehos.manifest/v5` when a role may grant another, whatever the version of
  `ehos.yaml`, and otherwise `ehos.manifest/v4` for an `ehos.yaml/v4`, `ehos.manifest/v3` for an
  `ehos.yaml/v3` and `ehos.manifest/v2` for an older one.
  """
  @spec schemas() :: [String.t()]
  def schemas,
    do: ["ehos.manifest/v2", "ehos.manifest/v3", "ehos.manifest/v4", "ehos.manifest/v5"]

  # `eh-os` D-81: a manifest keeps the meaning it had when EHOS accepted it, so the version that
  # can carry `needs.people` is a new one, and so is the one that can carry a seed or secrets
  # (D-98, D-99), and the one whose roles may grant others (D-112), which takes every
  # `ehos.yaml` v4 does; an older file, and a domain without a rule, keep their older manifest.
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

  defp select_domain!([], _contracts, _wanted),
    do: raise(ArgumentError, "no EhOsContract.Domain is registered")

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

  # `eh-os` D-66, D-69: the list names the other applications; its own it always signs in to. The
  # reader checks it against an `application` the file names, and this against the one found.
  defp not_its_own!(%{"sign_in" => %{"applications" => applications}}, application) do
    if application in applications do
      raise ArgumentError,
            "ehos.yaml's sign_in.applications names #{application}, the application this " <>
              "manifest is of; it signs people in to its own application without naming it"
    end
  end

  defp not_its_own!(_file, _application), do: :ok

  @doc false
  # Whether EHOS takes `name` for an application. `EhOsContract.Auth.child_spec/1` holds the
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
  # declaration and the part of a role after the dot at most 63 characters (D-48). A label a
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
  # kind (D-73). A capability no human holds is not offered: no role would hold it.
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

  # D-112: each role's rule, as the roles of the actors its actor's `may_grant:` names. D4 holds a
  # compiled domain's rules to other person actors, each once; a domain given as a map has not
  # been through it, so what EHOS would refuse is refused here too, with what to change. A person
  # who holds no capability is no role: a rule naming one would name a role the manifest does not
  # declare, and a rule of one would go nowhere. Rules that lead back to a role are D4's and EHOS's.
  defp grant_rules(roles, application, domain) do
    held = MapSet.new(roles, fn {actor, _role} -> actor.name end)
    people = for %{kind: :human, name: name} <- domain.actors, into: MapSet.new(), do: name

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

    for {actor, role} <- roles do
      case Map.get(actor, :may_grant, []) do
        [] ->
          role

        granted ->
          Map.put(role, "may_grant", granted!(granted, actor, held, people, domain, application))
      end
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
end

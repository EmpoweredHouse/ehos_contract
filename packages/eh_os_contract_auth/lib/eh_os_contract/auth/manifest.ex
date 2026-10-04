defmodule EhOsContract.Auth.Manifest do
  @moduledoc """
  Extends an application's `ehos.yaml` with what its contracts offer, into EHOS's
  `ehos.manifest/v2` (`eh-os` D-52).

  Every key of `ehos.yaml` but `schema` is in the manifest at the same path with the
  same value, and nothing is added to them: no default is filled in. `schema`
  becomes `ehos_yaml`, the version the file is written in. From `ehos.yaml/v2`, that
  includes `sign_in`, empty or not (`eh-os` D-69), whose `applications` must not name
  the application the generator finds below. The generator adds:

    * `application`, the contracts' domain's `name:`. A project with one domain
      takes it from there; a domain without contracts is not counted. A project with
      several says which one the image is in `ehos.yaml`'s `application`, which must
      be one of their names, in EHOS's spelling.
    * `offers`, the capabilities of the commands, queries and recordings a human actor
      may make, and, as roles, the human actors that hold at least one of them. A
      capability names its declaration as `command`, `query` or `record` (`eh-os`
      D-73), which EHOS accepts from the release that decided it on; an earlier EHOS
      refuses a manifest that offers a query or a recording. Scopes and publications are
      absent: EHOS's manifest has no field for them yet.
    * `engine`, the `eh_os_contract` version that wrote it.

  `contracts` is not written. EHOS counts it in the manifest's authority digest, and
  a contract's `version` moves with any edit, a label or a scenario included. Every
  such edit would then ask for `ehos.application.register` at deploy though no
  one's authority changed (`eh-os` issue #92). `engine` is in the manifest digest
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
  Builds an `ehos.manifest/v2` document from an `ehos.yaml` already read by
  `EhOsContract.Auth.EhosYaml.read/1`, the registered domains and the registered
  contracts.

  The map is taken as `read/1` returns it, already refused when EHOS would refuse
  it; a key `read/1` would refuse goes into the manifest. Only the contracts of the
  selected domain are read. Raises `ArgumentError`, with
  what to change, when the map is not a read `ehos.yaml`, when no domain or more than
  one fits, when the domain's name is not one EHOS takes for an application, when a
  command or a role's actor is past 63 characters or has an empty label, or when the
  domain offers no human command.
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

    file
    |> Map.merge(%{
      "schema" => "ehos.manifest/v2",
      "ehos_yaml" => ehos_yaml,
      "application" => application,
      "offers" => offers(application, domain, models),
      "engine" => %{"name" => "eh_os_contract", "version" => EhOsContract.version()}
    })
  end

  def build(_file, _domains, _contracts) do
    raise ArgumentError,
          "build/3 takes ehos.yaml as EhOsContract.Auth.EhosYaml.read/1 returns it, with its schema"
  end

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

  defp application?(name),
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

  # EHOS's limits on what a manifest offers, which the engine's own names and labels do not keep:
  # a declaration and the part of a role after the dot at most 63 characters (D-48), and a label a
  # person reads before binding a role, so never empty. Each is named here, not at deploy.
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
          "process" => to_string(model.process.name),
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
      %{
        "name" => name,
        "label" => actor.label,
        "capabilities" => Enum.sort(capabilities)
      }
    end
    |> Enum.sort_by(& &1["name"])
  end
end

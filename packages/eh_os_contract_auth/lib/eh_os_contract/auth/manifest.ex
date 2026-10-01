defmodule EhOsContract.Auth.Manifest do
  @moduledoc """
  Extends an application's `ehos.yaml` with what its contracts offer, into EHOS's
  `ehos.manifest/v2` (`eh-os` D-52).

  Every key of `ehos.yaml` but `schema` is in the manifest at the same path with the
  same value, and nothing is added to them: no default is filled in. `schema`
  becomes `ehos_yaml`, the version the file is written in. The generator adds:

    * `application`, the contracts' domain's `name:`. A project with one domain
      takes it from there. A project with several says which one the image is in
      `ehos.yaml`'s `application`, which must be one of their names.
    * `offers`, the human command capabilities and, as roles, the human actors that
      hold at least one of them. Queries, recordings, scopes and publications are
      absent: EHOS's manifest has no field for them yet, and adding one would make
      it refuse the document.
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

  Only the contracts of the selected domain are read. Raises `ArgumentError`, with
  what to change, when no domain or more than one fits, when the domain's name is
  not one EHOS takes for an application, or when the domain offers no human command.
  """
  @spec build(map(), [module() | map()], [module() | map()]) :: map()
  def build(%{"schema" => ehos_yaml} = file, domains, contracts) do
    ensure_disjoint!(file)

    domain = select_domain!(Enum.map(domains, &Model.fetch/1), file["application"])
    application = application!(domain)
    models = contracts |> Enum.map(&Model.fetch/1) |> Enum.filter(&(&1.domain == domain.module))
    if models == [], do: raise(ArgumentError, "#{inspect(domain.module)} has no contracts")

    file
    |> Map.delete("schema")
    |> Map.merge(%{
      "schema" => "ehos.manifest/v2",
      "ehos_yaml" => ehos_yaml,
      "application" => application,
      "offers" => offers(application, domain, models),
      "engine" => %{"name" => "eh_os_contract", "version" => EhOsContract.version()}
    })
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

  defp select_domain!([], _wanted),
    do: raise(ArgumentError, "no EhOsContract.Domain is registered")

  defp select_domain!([domain], nil), do: domain

  defp select_domain!(domains, nil) do
    raise ArgumentError,
          "the project has #{length(domains)} domains; say which one this image is in " <>
            "ehos.yaml, as application: <name>. Registered: #{known(domains)}"
  end

  defp select_domain!(domains, wanted) do
    case Enum.filter(domains, &(to_string(&1.name) == wanted)) do
      [domain] ->
        domain

      [] ->
        raise ArgumentError,
              "ehos.yaml names application: #{wanted}, and no registered domain has that " <>
                "name:. Registered: #{known(domains)}"

      many ->
        modules = many |> Enum.map(&inspect(&1.module)) |> Enum.sort() |> Enum.join(", ")

        raise ArgumentError,
              "domain #{inspect(wanted)} is ambiguous; matching modules: #{modules}"
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

    if Regex.match?(@application, name) and String.length(name) <= @max_application and
         name != "ehos" do
      name
    else
      raise ArgumentError,
            "#{inspect(domain.module)}'s name: #{inspect(domain.name)} is not a name EHOS takes " <>
              "for an application: lowercase letters, digits and dashes, starting with a letter, " <>
              "not ending with a dash, at most #{@max_application} characters, and not ehos. " <>
              "Rename the domain, such as name: :#{inspect(String.replace(name, "_", "-"))}"
    end
  end

  defp offers(application, domain, models) do
    declared = command_capabilities(application, domain, models)
    ensure_unique!(declared)

    capabilities = declared |> Enum.map(& &1.capability) |> Enum.sort_by(& &1["name"])
    roles = roles(application, domain, declared)

    if capabilities == [] or roles == [] do
      raise ArgumentError,
            "#{inspect(domain.module)} has no human command capabilities, so it cannot offer " <>
              "the capabilities and roles an ehos.manifest/v2 requires"
    end

    %{"capabilities" => capabilities, "roles" => roles}
  end

  defp command_capabilities(application, domain, models) do
    actors = Map.new(domain.actors, &{&1.name, &1})

    for model <- models,
        {name, access} <- Model.capabilities(model),
        access.kind == :command do
      command = Enum.find(model.commands, &(&1.name == access.name))

      principals =
        access.roles
        |> Enum.map(&role_actor!(&1, application, actors))
        |> Enum.map(&to_string(&1.kind))
        |> Enum.uniq()
        |> Enum.sort()

      %{
        capability: %{
          "name" => name,
          "command" => to_string(command.name),
          "label" => command.label,
          "process" => to_string(model.process.name),
          "principals" => principals
        },
        roles: access.roles
      }
    end
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

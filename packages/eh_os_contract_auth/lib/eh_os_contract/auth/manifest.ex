defmodule EhOsContract.Auth.Manifest do
  @moduledoc """
  Projects a v2 domain and its contracts onto EHOS's strict `ehos.manifest/v1`.

  Manifest v1 can represent commands and roles only. Accordingly, a capability is
  emitted for every human command capability, and each human actor that owns at
  least one of those capabilities becomes a role. System actors, actors with no
  command capability, queries and recorded events are absent: adding any of them
  under private fields would make EHOS reject the document. They require the later
  EHOS manifest schema rather than an extension invented here.

  Optional `engine` and `contracts` fields are deliberately omitted. The manifest
  is the smallest complete authority document accepted by v1, and contains no
  metadata that could move its EHOS-computed digest without changing authority.
  """

  alias EhOsContract.Model

  @doc "Builds an `ehos.manifest/v1` document from one domain and its contracts."
  @spec build(module() | map(), [module() | map()]) :: map()
  def build(domain, contracts) do
    domain = Model.fetch(domain)
    models = Enum.map(contracts, &Model.fetch/1)
    ensure_contracts!(domain, models)

    application = to_string(domain.name)
    declared = command_capabilities(application, domain, models)
    ensure_unique!(declared)

    capabilities = declared |> Enum.map(& &1.capability) |> Enum.sort_by(& &1["name"])
    roles = roles(application, domain, declared)

    if capabilities == [] or roles == [] do
      raise ArgumentError,
            "#{inspect(domain.module)} has no human command capabilities, so it cannot produce " <>
              "an ehos.manifest/v1 with the required non-empty capabilities and roles"
    end

    %{
      "schema" => "ehos.manifest/v1",
      "application" => application,
      "capabilities" => capabilities,
      "roles" => roles
    }
  end

  defp ensure_contracts!(domain, []) do
    raise ArgumentError, "#{inspect(domain.module)} has no contracts"
  end

  defp ensure_contracts!(domain, models) do
    case Enum.find(models, &(&1.domain != domain.module)) do
      nil ->
        :ok

      model ->
        raise ArgumentError,
              "#{inspect(model.module)} belongs to #{inspect(model.domain)}, not " <>
                inspect(domain.module)
    end
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

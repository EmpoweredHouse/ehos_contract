defmodule EhOsContract.Contract.Links do
  # The rules between modules: v2 §6, layer L3.
  #
  # A contract names its domain and the sibling contracts it consumes without a
  # compile dependency (v2 §8), so no rule inside one contract (L2) can look them up,
  # and an incremental compile does not revisit a contract when its domain or a
  # sibling changes. These rules therefore run over every compiled module at once, on
  # every compile, from the Mix compiler `compile.eh_os_contract`, which hands
  # `check/1` the project's modules.
  #
  # The rules come in groups, one module each, as L2's do:
  #
  # - `Links.Domain` — X1–X4 and the parts of D10 and D11 that need the domain.
  # - `Links.Siblings` — X5, X6 and X10, what a contract consumes from a sibling contract.
  # - `Links.System` — X7, X8 and D14's names, unique across the application.
  # - `Links.Scenarios` — X9, scenario values of domain types and of siblings' events.
  # - `Links.Processes` — X1, X2, X5, X6 and D11 for a process module (plan DD, P2c,
  #   #210): its domain, its accountable actor, and the contracts' events it includes.
  # - `Links.ContextMap` — X11–X13, the context map holding the contracts to it (plan DD,
  #   M1, #316).
  #
  # A violation points at the declaration at fault. L3 reads the declarations Spark
  # kept in each compiled contract (`spark_dsl_config/0`), the same ones L2 read,
  # with the file and line they were written at; the model (v2 §9) carries no
  # locations, so they reach neither the version nor any digest. What names a whole
  # contract — its domain, its context — points at the contract's `use` line.
  @moduledoc false

  alias EhOsContract.Contract.{Links, Rules}

  @typedoc "A broken rule, and where it was written: `nil` when nothing says where."
  @type violation :: {String.t(), :erl_anno.anno() | nil}

  @typedoc """
  One v2 contract as the rules read it: its model, its declarations with their
  locations, the location of its `use`, and its domain's model — `nil` when
  `domain:` names no compiled domain.
  """
  @type contract :: %{
          module: module(),
          model: map(),
          declarations: map(),
          id: %{value: String.t(), at: :erl_anno.anno() | nil} | nil,
          at: :erl_anno.anno() | nil,
          domain: map() | nil
        }

  @typedoc """
  One process module (`EhOsContract.Process`) as the rules read it: its model, its
  declarations with their locations, the location of its `use`, and its domain's
  model — `nil` when `domain:` names no compiled domain.
  """
  @type process :: %{
          module: module(),
          model: map(),
          declarations: map(),
          at: :erl_anno.anno() | nil,
          domain: map() | nil
        }

  @groups [
    Links.Domain,
    Links.Siblings,
    Links.System,
    Links.Scenarios,
    Links.Processes,
    Links.ContextMap
  ]

  @doc """
  Every violation of an L3 rule among `modules`, the modules of one application.
  Modules that are neither a v2 contract, a process module nor an implementation of
  one are ignored, so the whole compile path can be passed as it is.
  """
  @spec check([module()]) :: [violation()]
  def check(modules) do
    system = system(modules)
    Enum.flat_map(@groups, & &1.check(system))
  end

  @doc false
  @spec system([module()]) :: %{
          contracts: [contract()],
          by_module: %{module() => contract()},
          processes: [process()],
          implementations: [map()]
        }
  def system(modules) do
    modules = Enum.sort_by(modules, &inspect/1)
    contracts = modules |> Enum.map(&contract/1) |> Enum.reject(&is_nil/1)
    processes = modules |> Enum.map(&process/1) |> Enum.reject(&is_nil/1)

    # What `EhOsContract.Implementation` says about each, with the module it is.
    implementations =
      for module <- modules,
          Code.ensure_loaded?(module),
          function_exported?(module, :__eh_os_implementation__, 0),
          do: Map.put(module.__eh_os_implementation__(), :module, module)

    %{
      contracts: contracts,
      by_module: Map.new(contracts, &{&1.module, &1}),
      processes: processes,
      implementations: implementations
    }
  end

  @doc """
  The v2 contract `module` as the rules read it: the one `system/1` built, or, for
  one outside the modules checked, built now. `nil` when it is not one.
  """
  @spec contract(map(), module()) :: contract() | nil
  def contract(system, module), do: Map.get(system.by_module, module) || contract(module)

  @doc "A contract as the rules read it, or `nil` when `module` is not one."
  @spec contract(module()) :: contract() | nil
  def contract(module) do
    with %{kind: :contract, units: _} = model <- compiled(module) do
      dsl = module.spark_dsl_config()

      %{
        module: module,
        model: model,
        declarations: Rules.declarations(dsl),
        id: Rules.contract_id(dsl),
        at: use_at(dsl.persist),
        domain: domain(model.domain)
      }
    else
      _ -> nil
    end
  end

  @doc "A process module as the rules read it, or `nil` when `module` is not one."
  @spec process(module()) :: process() | nil
  def process(module) do
    with %{kind: :process} = model <- compiled(module) do
      declarations = EhOsContract.Process.Rules.declarations(module.spark_dsl_config())

      %{
        module: module,
        model: model,
        declarations: declarations,
        at: declarations.at,
        domain: domain(model.domain)
      }
    else
      _ -> nil
    end
  end

  @doc "The model of a compiled domain, or `nil` when `module` is not one."
  @spec domain(module()) :: map() | nil
  def domain(module) do
    case compiled(module) do
      %{kind: :domain} = model -> model
      _ -> nil
    end
  end

  defp compiled(module) do
    if is_atom(module) and Code.ensure_loaded?(module) and
         function_exported?(module, :__eh_os_contract_model__, 0),
       do: module.__eh_os_contract_model__()
  end

  defp use_at(%{file: file, eh_os_contract_line: line}),
    do: [file: String.to_charlist(file), location: line]

  defp use_at(_persisted), do: nil

  @doc "Where a declaration was written."
  @spec at(struct()) :: :erl_anno.anno() | nil
  def at(declaration), do: Spark.Dsl.Entity.anno(declaration)

  @doc """
  `file:line` of a location, relative to the working directory, for a message that
  names the other side of a violation.
  """
  @spec place(:erl_anno.anno() | nil) :: String.t()
  def place(nil), do: "an unknown place"

  def place(anno) do
    file = anno |> :erl_anno.file() |> to_string() |> Path.relative_to_cwd()
    "#{file}:#{:erl_anno.line(anno)}"
  end
end

defmodule EhOsContract.Check do
  # **Static** checks: the contract against the binary, without a single query
  # against the log.
  #
  # The product plan separates the two halves of verification, and that separation
  # has a consequence for the code: this half belongs to CI, is cheap and immediate,
  # and **needs no interface**. The other half, the behavioural one, lives in
  # `EhOsContract.Conformance` and reads the log.
  #
  # The logic lives here rather than in the mix task, where it would be a private
  # function — that is, **logic with no test**. A check nobody checks quietly stops
  # working.
  @moduledoc false

  alias EhOsContract.Check.Finding
  alias EhOsContract.Contract.Links
  alias EhOsContract.Model

  @doc """
  What `mix eh_os_contract.check` says about contracts (plan E7c-2), each finding
  at the declaration it is about (plan EL1).

  Much of what a whole-program check could look for a contract cannot compile
  without — a name declared twice, a promise naming an event nobody declares, a rule
  function that does not exist are L2 and L3 rules of the DSL. What is left is what
  a contract may legally say and a reader should still hear about: a process with
  no `accountable`; a declaration or a `promise` the process owner has not
  confirmed; a promise with no `within`, which has no failing case; a `deadline` with no event that ends a run; and whether the
  contract is implemented — not at all is legal and noted (D3), in part is a
  command or a consumer dispatch will refuse, and a warning.
  """
  @spec findings([module()] | nil) :: [Finding.t()]
  def findings(contracts \\ nil) do
    for contract <- contracts || EhOsContract.Registry.contracts(),
        %{} = linked <- [Links.contract(contract)],
        finding <- process_findings(linked) ++ implemented_findings(linked) do
      finding
    end
  end

  defp process_findings(%{model: model} = linked) do
    case Model.process(model) do
      nil -> []
      process -> process_findings(linked, process)
    end
  end

  @doc """
  What `mix eh_os_contract.check` says about process modules, `use EhOsContract.Process`
  (plan DD, P2d, #213): the rules about a contract's process, at the module's `use` and
  its promises. A process with no `accountable`, a `deadline` or a promise not
  confirmed, a promise with no `within`. Not a `deadline` with no event that ends a
  run: a process module cannot declare one without `ends_on` (R6).
  """
  @spec process_module_findings([module()] | nil) :: [Finding.t()]
  def process_module_findings(processes \\ nil) do
    for module <- processes || EhOsContract.Registry.processes(),
        %{model: model, declarations: declarations, at: at} <- [Links.process(module)],
        finding <-
          process_rules(
            Model.process(model),
            inspect(module),
            at,
            fn promise -> located(declarations.promises, promise.name) || at end
          ) do
      finding
    end
  end

  defp process_findings(%{model: model, declarations: declarations}, process) do
    name = inspect(model.module)
    declared = Enum.find(declarations.processes, &(&1.name == process.name))
    at = declared && Links.at(declared)
    promise_at = fn promise -> located(declared && declared.promises, promise.name) || at end

    ends? = Enum.any?(Model.process_events(model), & &1.terminal)

    unobservable =
      if process.deadline && not ends?,
        do: [
          Finding.new(
            "deadline-without-terminal-event",
            "process #{inspect(process.name)} declares `deadline` = " <>
              "#{inspect({process.deadline.amount, process.deadline.unit})} and no event of it is " <>
              "`terminal: true`, so no run can be observed to end and the duration cannot be " <>
              "measured (#{name})",
            at
          )
        ],
        else: []

    process_rules(process, name, at, promise_at) ++ unobservable
  end

  # The rules about a process, a contract's or a module's: `name` is the module's, as a
  # message names it.
  defp process_rules(process, name, at, promise_at) do
    accountable =
      if process.accountable == nil,
        do: [
          Finding.new(
            "process-without-accountable",
            "process #{inspect(process.name)} names no `accountable` role, so a finding about it " <>
              "has no addressee (#{name})",
            at
          )
        ],
        else: []

    unverified =
      for %{unverified: true} = value <- [process.deadline] do
        Finding.new(
          "unverified-declaration",
          "process #{inspect(process.name)}: `deadline` = #{inspect({value.amount, value.unit})} " <>
            "is not confirmed by the process owner — it does not count towards the evidence report " <>
            "(#{name})",
          at
        )
      end ++
        for %{unverified: true} = promise <- process.promises do
          Finding.new(
            "unverified-declaration",
            "process #{inspect(process.name)}: promise #{inspect(promise.name)} is not confirmed by " <>
              "the process owner — it is still evaluated, but it does not count towards the " <>
              "evidence report's aggregate (#{name})",
            promise_at.(promise)
          )
        end

    unfalsifiable =
      for %{within: nil} = promise <- process.promises do
        Finding.new(
          "promise-without-within",
          "promise #{inspect(promise.name)} has no `within`, so it has no failing case: any " <>
            "#{inspect(promise.eventually)} after #{inspect(promise.from)} satisfies it and a run " <>
            "with none stays pending for ever (#{name})",
          promise_at.(promise)
        )
      end

    accountable ++ unverified ++ unfalsifiable
  end

  defp located(nil, _name), do: nil

  defp located(declarations, name) do
    case Enum.find(declarations, &(&1.name == name)) do
      nil -> nil
      declaration -> Links.at(declaration)
    end
  end

  # What dispatch looks an implementation up for: every unit, every consumer, and
  # every query, which `EhOsContract.Dispatcher.query/3` answers through its module;
  # and every domain service, which a decision calls through the contract.
  defp implemented_findings(%{model: model, at: at}) do
    wanted =
      for(u <- model.units, Enum.any?(model.commands, &(&1.unit == u.name)), do: {u.kind, u.name}) ++
        for(p <- model.policies, do: {:policy, p.name}) ++
        for(e <- model.effects, do: {:effect, e.name}) ++
        for(pm <- model.process_managers, do: {:process_manager, pm.name}) ++
        for(r <- model.read_models, do: {:read_model, r.name}) ++
        for(q <- model.queries, do: {:query, q.name}) ++
        for s <- model.domain_services, do: {:domain_service, s.name}

    declarations = EhOsContract.Implementations.index(model.module).declarations

    missing =
      for {kind, name} <- wanted,
          not Map.has_key?(declarations, {model.module, kind, name}),
          do: "#{kind} #{name}"

    cond do
      wanted == [] or missing == [] ->
        []

      length(missing) == length(wanted) ->
        [
          Finding.new(
            "contract-without-implementation",
            "#{inspect(model.module)} has no implementation, which a contract may: nothing " <>
              "of it can be dispatched, and its report is of a process nobody runs",
            at
          )
        ]

      true ->
        [
          Finding.new(
            "declaration-without-implementation",
            "#{inspect(model.module)} implements some declarations and not " <>
              "#{Enum.join(missing, ", ")}, which dispatch will refuse to run",
            at
          )
        ]
    end
  end

  @doc """
  The rules between modules, L3, repeated as errors for a project that does not run
  them on every compile (v2 §6, L5; plan EL1): one whose `compilers` has no
  `:eh_os_contract`. `modules` gives the project's compiled modules, and is called
  only for such a project: one that registers the compiler gets nothing here, since
  its build already failed on each, and reads no `.beam` for it.
  """
  @spec compiler_findings([atom()], (-> [module()])) :: [Finding.t()]
  def compiler_findings(compilers, modules) do
    if :eh_os_contract in compilers,
      do: [],
      else: modules.() |> Links.check() |> Enum.map(&Finding.compiler/1)
  end

  @doc """
  Whether there is nothing at all to check.

  **A report of `0 errors, 0 warnings, 0 notices` is what a healthy repository looks
  like, and it is also what an engine scanning the wrong application looks like.** The
  two are indistinguishable, and the second one happened here the first time the
  engine compiled as its own package: it defaulted to its own name, scanned itself,
  found no contracts and said everything was fine.

  Configuration fixed the default; it did not fix the silence. `EhOsContract.Registry.load!/1`
  raises for an application that is not loaded — a typo — but an application that is
  loaded and simply holds no contracts is not a typo and cannot be distinguished from
  one that does, so the scan returns nothing and every check downstream iterates over
  an empty list and finds nothing wrong.

  A warning rather than an error, because it is the true state of a repository on the
  day before its first contract, and a check that fails a build for being new gets
  removed before it ever catches the real case.
  """
  @spec no_contracts?([module()] | nil) :: boolean()
  def no_contracts?(contracts \\ nil),
    do: (contracts || EhOsContract.Registry.contracts()) == []
end

defmodule Mix.Tasks.EhOsContract.Check do
  @shortdoc "Whole-program checks over the contracts and their implementations"

  @moduledoc """
  Everything that requires seeing **every** module at once.

  The split is forced by the compilation model rather than chosen: a macro sees
  one file, so it checks what one file can show. That a contract is implemented,
  that a reaction does not point back up its process, and that the declarations
  agree with reality — all of that belongs here. A project that does not register
  the compiler `:eh_os_contract` gets its rules (L3) here too, as errors.

  Every finding names its rule (`EhOsContract.Check.Catalog`, documented in
  `docs/rules.md`) and, where it can, the file and line of the declaration it is
  about. Nothing silences a rule; a finding goes when the model changes.

      mix eh_os_contract.check                         # errors fail the task
      mix eh_os_contract.check --warnings-as-errors    # so do warnings
      mix eh_os_contract.check --format json           # one JSON array, see render/2

  `--format json` prints the array and nothing else, but the compile this task runs
  first prints what it prints: compile beforehand when the output is read by a
  program. `--warnings-as-errors` changes the exit status and nothing it prints.
  """

  use Boundary, classify_to: EhOsContract
  use Mix.Task

  alias EhOsContract.Check.{Catalog, Finding}

  @impl Mix.Task
  def run(args) do
    {opts, _rest} =
      OptionParser.parse!(args, strict: [format: :string, warnings_as_errors: :boolean])

    unless opts[:format] in [nil, "human", "json"],
      do: Mix.raise("--format is human or json, got #{inspect(opts[:format])}")

    # Erlang keeps stdout in latin1 when the output is not a terminal, so
    # `mix eh_os_contract.check > report.txt` truncates every codepoint to a byte. Event
    # labels come from the contract and are written in the client's language.
    :io.setopts(:standard_io, encoding: :unicode)

    Mix.Task.run("compile")
    Application.load(:eh_os_contract)
    EhOsContract.Registry.load!()

    findings = check_something_to_check([])

    # The task's own check says which rule it found and what; the rule's level is the
    # catalog's.
    findings = for {rule, message} <- findings, do: Finding.new(rule, message)
    contracts = EhOsContract.Registry.contracts()
    processes = EhOsContract.Registry.processes()

    # An umbrella's root compiles no module of its own, and has no compile path to read.
    compiler =
      EhOsContract.Check.compiler_findings(
        Mix.Project.config()[:compilers] || Mix.compilers(),
        fn ->
          if Mix.Project.umbrella?(),
            do: [],
            else: Mix.Tasks.Compile.EhOsContract.modules(Mix.Project.compile_path())
        end
      )

    report(
      compiler ++
        EhOsContract.Check.findings(contracts) ++
        EhOsContract.Check.process_module_findings(processes) ++
        EhOsContract.Check.Completeness.findings(contracts, processes) ++
        EhOsContract.Check.Contracts.findings(contracts) ++ findings,
      opts
    )
  end

  # **Nothing found is not the same as nothing wrong, and the report cannot tell
  # them apart.** `0 errors, 0 warnings, 0 notices` is what a healthy repository
  # prints and also what an engine pointed at the wrong application prints — which
  # is what this engine did on the day it first compiled as a package, scanning
  # itself and reporting a perfectly healthy empty graph.
  #
  # The applications are named in the finding because that is where the mistake
  # actually is: the contracts exist, the configuration points elsewhere.
  defp check_something_to_check(findings) do
    if EhOsContract.Check.no_contracts?() do
      configured = EhOsContract.Config.get(:applications) || []

      [
        {"no-contracts",
         "no contracts found in #{inspect(configured)}, so every check below has an empty list " <>
           "to work on and will report nothing. A clean report and a misconfigured scan look " <>
           "identical — set `config :eh_os_contract, applications: [...]` to the applications that hold " <>
           "your contracts"}
        | findings
      ]
    else
      findings
    end
  end

  @doc """
  The findings in the order they are printed: errors, then warnings, then notices,
  each group sorted by its text.

  A fixed order rather than the order the checks produced them. Some checks group
  by module into a map, and on OTP 26 and later a small map keyed by atoms iterates
  in the order the atoms were created, not alphabetically. A new module anywhere in
  the build could therefore swap two lines of this report between runs of the same
  code (v2 plan, E1). The plan compares this output commit to commit, so it has to
  come out the same for the same findings.
  """
  @spec ordered([Finding.t()]) :: [Finding.t()]
  def ordered(findings) do
    rank = %{error: 0, warn: 1, info: 2}
    Enum.sort_by(findings, &{Map.fetch!(rank, &1.level), &1.message, &1.rule})
  end

  @doc """
  What the task prints for `findings`, as `format` says: `:human`, two lines a
  finding and a count; `:json`, one array and nothing else (plan EL1).

  A finding's second line says where the declaration it is about was written, when
  anything does, and where its rule is documented; a finding with neither has none. In JSON a finding is `rule`,
  `level` (`"error"`, `"warning"` or `"notice"`), `message`, `file` and `line` (`null`
  when nothing says where) and `documentation` (`null` for a repeated compiler rule,
  which the catalog does not document).
  """
  @spec render([Finding.t()], :human | :json) :: String.t()
  def render(findings, :human) do
    lines =
      for finding <- ordered(findings) do
        prefix =
          case finding.level do
            :error -> "ERROR"
            :warn -> "WARN "
            :info -> "info "
          end

        where =
          case Finding.place(finding) do
            nil -> []
            {file, line} -> ["#{file}:#{line}"]
          end

        first = "#{prefix} #{finding.rule}: #{finding.message}\n"

        case where ++ List.wrap(documentation(finding)) do
          [] -> first
          second -> first <> "      " <> Enum.join(second, " · ") <> "\n"
        end
      end

    counts = Enum.frequencies_by(findings, & &1.level)

    Enum.join(lines) <>
      "\neh_os_contract.check: #{Map.get(counts, :error, 0)} errors, " <>
      "#{Map.get(counts, :warn, 0)} warnings, #{Map.get(counts, :info, 0)} notices"
  end

  def render(findings, :json) do
    findings
    |> ordered()
    |> Enum.map(fn finding ->
      {file, line} = Finding.place(finding) || {nil, nil}

      Jason.OrderedObject.new(
        rule: finding.rule,
        level: Catalog.level_word(finding.level),
        message: finding.message,
        file: file,
        line: line,
        documentation: documentation(finding)
      )
    end)
    |> Jason.encode!(pretty: true)
  end

  defp documentation(%Finding{rule: rule}) do
    if Catalog.known?(rule), do: Catalog.url(rule)
  end

  @doc """
  Whether `findings` fail the task: any error does, and a warning does when
  `warnings_as_errors` is set. Notices never do. The output is the same either way.
  """
  @spec failed?([Finding.t()], boolean()) :: boolean()
  def failed?(findings, warnings_as_errors) do
    Enum.any?(findings, &(&1.level == :error or (warnings_as_errors and &1.level == :warn)))
  end

  defp report(findings, opts) do
    format = if opts[:format] == "json", do: :json, else: :human
    Mix.shell().info(render(findings, format))
    if failed?(findings, opts[:warnings_as_errors] || false), do: exit({:shutdown, 1})
  end
end

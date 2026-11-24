defmodule Mix.Tasks.EhosContract.Check do
  @shortdoc "Checks the contracts and their implementations as one program"

  @moduledoc """
  Reports what a contract can legally say and a reader must still know about. Each
  finding is an error, a warning or a notice.

  A compile refuses a contract that cannot be right. This task reports the rest.
  Examples:

  - a contract that no module implements;
  - a reaction that points back up its own process;
  - a deadline with no event that ends the run;
  - a free-text field that is not marked personal.

      mix ehos_contract.check                         # an error fails the task
      mix ehos_contract.check --warnings-as-errors    # a warning fails it too
      mix ehos_contract.check --format json           # one JSON array

  The task reads each contract, domain and implementation of the applications that
  `config :ehos_contract, applications:` names. It leaves out the modules that
  `exclude:` names. If the project does not add the `:ehos_contract` compiler, the
  task also reports the violations of that compiler, as errors.

  If these applications hold no contract, the task reports the error `no-contracts`.
  An empty report then does not mean a model with no problems.

  ## What does a finding hold?

  Each finding names its rule. If the task knows the declaration, the finding also
  names its file and line. [The rules](rules.md) (`docs/rules.md` in the package)
  tell what each rule means and how to clear it. A compiler violation that the task
  repeats keeps the code of the compiler.

  Nothing silences a rule. A finding goes away only when the model changes.

  The task prints the errors first, then the warnings, then the notices. It sorts
  each group by its text. So the same findings give the same output on each run.

  | Format | A finding |
  | --- | --- |
  | `human`, the default | A line with the level, the rule and the message. A second line with where the declaration was written and where the rule is documented, if the task knows either. A count ends the report. |
  | `json` | `rule`, `level` (`"error"`, `"warning"` or `"notice"`), `message`, `file`, `line` (`null` if the task does not know the place) and `documentation` (`null` for a repeated compiler rule, which the catalogue does not document) |

  - `--format json` prints only the array. But the task compiles the project first,
    and the compile prints its own output. If a program reads the output, compile
    before you run the task.
  - `--warnings-as-errors` changes the exit status. It does not change the output.
  - `--format` other than `human` or `json` stops the task with an error.
  """

  use Boundary, classify_to: EhosContract
  use Mix.Task

  alias EhosContract.Check.{Catalog, Finding}

  @impl Mix.Task
  def run(args) do
    {opts, _rest} =
      OptionParser.parse!(args, strict: [format: :string, warnings_as_errors: :boolean])

    unless opts[:format] in [nil, "human", "json"],
      do: Mix.raise("--format is human or json, got #{inspect(opts[:format])}")

    # Erlang keeps stdout in latin1 when the output is not a terminal, so
    # `mix ehos_contract.check > report.txt` truncates every codepoint to a byte. Event
    # labels come from the contract and are written in the client's language.
    :io.setopts(:standard_io, encoding: :unicode)

    Mix.Task.run("compile")
    Application.load(:ehos_contract)
    EhosContract.Registry.load!()

    findings = check_something_to_check([])

    # The task's own check says which rule it found and what; the rule's level is the
    # catalog's.
    findings = for {rule, message} <- findings, do: Finding.new(rule, message)
    contracts = EhosContract.Registry.contracts()
    processes = EhosContract.Registry.processes()

    # An umbrella's root compiles no module of its own, and has no compile path to read.
    compiler =
      EhosContract.Check.compiler_findings(
        Mix.Project.config()[:compilers] || Mix.compilers(),
        fn ->
          if Mix.Project.umbrella?(),
            do: [],
            else: Mix.Tasks.Compile.EhosContract.modules(Mix.Project.compile_path())
        end
      )

    report(
      compiler ++
        EhosContract.Check.findings(contracts) ++
        EhosContract.Check.process_module_findings(processes) ++
        EhosContract.Check.Completeness.findings(contracts, processes) ++
        EhosContract.Check.Contracts.findings(contracts, nil, processes) ++ findings,
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
    if EhosContract.Check.no_contracts?() do
      configured = EhosContract.Config.get(:applications) || []

      [
        {"no-contracts",
         "no contracts found in #{inspect(configured)}, so every check below has an empty list " <>
           "to work on and will report nothing. A clean report and a misconfigured scan look " <>
           "identical — set `config :ehos_contract, applications: [...]` to the applications that hold " <>
           "your contracts"}
        | findings
      ]
    else
      findings
    end
  end

  # The findings in the order they are printed: errors, then warnings, then notices,
  # each group sorted by its text.
  #
  # A fixed order rather than the order the checks produced them. Some checks group
  # by module into a map, and on OTP 26 and later a small map keyed by atoms iterates
  # in the order the atoms were created, not alphabetically. A new module anywhere in
  # the build could therefore swap two lines of this report between runs of the same
  # code (v2 plan, E1). The plan compares this output commit to commit, so it has to
  # come out the same for the same findings.
  # Called by this task and its tests.
  @doc false
  @spec ordered([Finding.t()]) :: [Finding.t()]
  def ordered(findings) do
    rank = %{error: 0, warn: 1, info: 2}
    Enum.sort_by(findings, &{Map.fetch!(rank, &1.level), &1.message, &1.rule})
  end

  # What the task prints for `findings`, as `format` says (plan EL1); the format, as a
  # program reads it, is in the task's moduledoc, so change it there with this.
  # Called by this task and its tests.
  @doc false
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
      "\nehos_contract.check: #{Map.get(counts, :error, 0)} errors, " <>
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

  # Whether `findings` fail the task: any error does, and a warning does when
  # `warnings_as_errors` is set. Notices never do. The output is the same either way.
  # Called by this task.
  @doc false
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

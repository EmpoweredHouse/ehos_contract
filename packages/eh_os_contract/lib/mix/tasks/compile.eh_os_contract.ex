defmodule Mix.Tasks.Compile.EhOsContract do
  @shortdoc "Checks that the contracts agree with their domain and with each other"

  @moduledoc """
  Checks the rules that a contract cannot hold alone, on each compile. These rules
  need the domain of the contract, the contracts that it consumes, or the rest of
  the application.

  Add the compiler to the project, after the compilers of Elixir:

      def project do
        [compilers: Mix.compilers() ++ [:eh_os_contract], ...]
      end

  ## What it checks

  - The domain of a contract declares the contexts, terms, values and actors that the
    contract uses.
  - A sibling contract declares each event and field that this contract consumes.
  - A policy or a read model that takes an event of another context says how the
    engine delivers it.
  - A published event holds no personal data.
  - A reference from one context into another follows the relation that the domain
    declares between them. It takes no more than the pattern of that relation lets
    through.
  - No declaration has two implementations.
  - The `id:` of each contract and of each process module is unique in the
    application.
  - The name of each command, query and recorded event is unique in its domain.
  - A process module agrees with the contracts whose events it includes.

  These rules leave two things open. `mix eh_os_contract.check` reports them, but it
  does not refuse them:

  - a declaration with no implementation;
  - a reaction to an event of another context with `delivery: :in_transaction`.

  ## A violation

  A violation is an error at the file and the line of the declaration at fault. It
  fails the compile. In a project without this compiler, `mix eh_os_contract.check`
  reports the same violations as errors.

  ## Which modules it reads

  A contract names its domain and its siblings with no compile-time dependency on
  them. So a change to a domain recompiles none of the contracts that name it. For
  this reason, the compiler runs on each compile and over the whole project, not only
  when a contract changes.

  - It reads the exports of each `.beam` file in the compile path of the project. No
    configuration names the modules.
  - It loads only the modules that hold a model (a contract, a domain or a process
    module) or an implementation.
  - It finds a domain or a sibling contract in a dependency by its name.
  """

  use Boundary, classify_to: EhOsContract
  use Mix.Task.Compiler

  alias EhOsContract.Contract.Links
  alias Mix.Task.Compiler.Diagnostic

  @markers [__eh_os_contract_model__: 0, __eh_os_implementation__: 0]

  @impl Mix.Task.Compiler
  def run(_args) do
    diagnostics =
      Mix.Project.compile_path()
      |> modules()
      |> Links.check()
      |> Enum.map(&diagnostic/1)

    Enum.each(diagnostics, &print/1)

    if diagnostics == [], do: {:noop, []}, else: {:error, diagnostics}
  end

  @doc false
  @spec modules(Path.t()) :: [module()]
  def modules(path) do
    for beam <- path |> Path.join("*.beam") |> Path.wildcard(),
        {:ok, {module, [exports: exports]}} <-
          [:beam_lib.chunks(String.to_charlist(beam), [:exports])],
        Enum.any?(@markers, &(&1 in exports)),
        do: module
  end

  defp diagnostic({message, anno}) do
    %Diagnostic{
      compiler_name: "eh_os_contract",
      file: anno && anno |> :erl_anno.file() |> to_string(),
      position: (anno && :erl_anno.line(anno)) || 0,
      message: message,
      severity: :error
    }
  end

  defp print(%Diagnostic{} = d) do
    Code.print_diagnostic(%{
      file: d.file,
      position: d.position,
      message: d.message,
      severity: d.severity,
      stacktrace: [],
      span: nil
    })
  end
end

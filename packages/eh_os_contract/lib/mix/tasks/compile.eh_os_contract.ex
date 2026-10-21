defmodule Mix.Tasks.Compile.EhOsContract do
  @shortdoc "Checks that contracts agree with their domain and with each other"

  @moduledoc """
  Checks, on every compile, the rules a contract cannot hold on its own: those that
  need its domain, the contracts it consumes, or the rest of the application.

  Among them: a contract's domain declares the contexts, terms, values and actors it
  uses; a sibling contract declares every event and field this one consumes; a
  policy or read model that takes another context's event says how it is delivered;
  personal data stays out of what is published; a reference from one context into
  another follows the relation the domain declares between them, and takes no more
  than its pattern lets through; no declaration has two implementations; names are unique across the application; and a process module
  agrees with the contracts whose events it includes.

  Some of what these rules leave open is reported by `mix eh_os_contract.check`
  instead of refused: a declaration with no implementation at all, and a reaction to
  another context's event declared `delivery: :in_transaction`.

  Add it to the project's compilers, after Elixir's:

      def project do
        [compilers: Mix.compilers() ++ [:eh_os_contract], ...]
      end

  A contract names its domain and its siblings without depending on them at compile
  time, so changing a domain recompiles none of the contracts that name it. That is
  why this runs on every compile and over the whole project, not only when a
  contract changed. It reads each `.beam` file's exports, and loads only the modules
  that carry a model (a contract, a domain, a process) or an implementation.

  A violation is an error at the file and line of the declaration at fault, and
  fails the compile. In a project without this compiler, `mix eh_os_contract.check`
  reports the same violations, as errors.

  The modules checked are the project's own, the `.beam` files in its compile path;
  no configuration names them. A domain or a sibling contract in a dependency is
  found by its name.
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

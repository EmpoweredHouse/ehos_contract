defmodule Mix.Tasks.Compile.EhOsContract do
  @shortdoc "Checks v2 contracts against their domain and each other (L3)"

  @moduledoc """
  The rules between modules, layer L3 of v2 §6, as a Mix compiler. It runs on every
  `mix compile`, after the Elixir compiler, over every module the project compiled:

      def project do
        [compilers: Mix.compilers() ++ [:eh_os_contract], ...]
      end

  A contract names its domain and the sibling contracts it consumes without a
  compile dependency (v2 §8), so an incremental compile that changes a domain or a
  sibling recompiles none of the contracts that name it. That is why this runs every
  time and over the whole project, not only when a contract changed. What it costs
  is reading each `.beam`'s table of exports; only the modules that carry a v2 model,
  or implement a v2 contract, are loaded.

  A violation is an error diagnostic at the file and line of the declaration at
  fault, and it fails the compile (`EhOsContract.Next.Contract.Links`).

  The modules are the project's own, the `.beam` files in its compile path, and no
  configuration names them. A domain or a sibling that a contract names is looked
  up by name, so one in a dependency is found too.
  """

  use Boundary, classify_to: EhOsContract
  use Mix.Task.Compiler

  alias EhOsContract.Next.Contract.Links
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

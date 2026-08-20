defmodule Mix.Tasks.Pns.Brief do
  @shortdoc "One process as a document to validate with a person, before anything is built"

  @moduledoc """
  Assembles `PNS.Brief` for one process: the flow, the events in the client's own
  words with what each one is for, the promises as sentences, and the outside
  dependencies.

      mix pns.graph --mermaid --process clinical_visit --output schemat.mmd
      mmdc -i schemat.mmd -o schemat.svg
      mix pns.brief --process clinical_visit --diagram schemat.svg --output wizyta.html

  **HTML is the deliverable, not a step towards a PDF.** An earlier version printed
  the result through headless Chrome and that was ceremony: these sessions happen on
  a shared screen, where HTML reflows, is searchable and can be copied out of — and
  if somebody wants paper, every browser prints. The stylesheet carries `@page`
  rules so that printing gives A4 without anything else being installed.

  The file is self-contained: the diagram is inlined as SVG, nothing is fetched, and
  it opens with no network. The alternative — shipping the mermaid source and a
  script to render it — would make a document handed to a client silently depend on
  the internet to show its own picture.

  Nothing here shells out to a renderer from inside Elixir, which would make a
  browser a hidden dependency of the engine. `mmdc` is still needed for the middle
  step and wants the same `chrome-headless-shell` as everything else; see
  `README.md` for the version mismatch it hits.

  `--diagram` is optional. Without it the document is complete except the picture
  and says so, which is the right behaviour for a quick read on screen.
  """

  use Boundary, classify_to: PNS
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    # Every line of this document is in the client's language, and Erlang keeps
    # stdout in latin1 when the output is not a terminal.
    :io.setopts(:standard_io, encoding: :unicode)

    {opts, _} =
      OptionParser.parse!(args, strict: [process: :string, diagram: :string, output: :string])

    process = opts[:process] || Mix.raise("--process is required; see `mix pns.graph` for the names")

    Mix.Task.run("compile")
    Application.load(:pns)
    PNS.Registry.load!()

    name = String.to_atom(process)

    contract =
      Enum.find(PNS.Registry.contracts(), fn c -> Enum.any?(c.processes(), &(&1.name == name)) end) ||
        Mix.raise("no process #{inspect(name)}. Declared: #{known_processes()}")

    diagram = opts[:diagram] && File.read!(opts[:diagram])
    html = PNS.Brief.render(contract, name, diagram: diagram)

    case opts[:output] do
      nil ->
        Mix.shell().info(html)

      path ->
        # `File.write!` always writes UTF-8; a shell redirect does not.
        File.write!(path, html)
        Mix.shell().info("written: #{path}")
    end
  end

  defp known_processes do
    PNS.Registry.contracts()
    |> Enum.flat_map(fn c -> Enum.map(c.processes(), & &1.name) end)
    |> Enum.sort()
    |> Enum.join(", ")
  end
end

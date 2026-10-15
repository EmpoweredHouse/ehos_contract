# Writes data.js beside this file: the graph.v1 documents of the test set for drawing (GraphLab), with what the
# log says over each, and AppUnite's computers contract to try a large unit on. Run from sandbox/, against the
# development database the test set's traffic filled:
#
#     cd sandbox && mix ecto.reset && mix graph_lab.traffic && mix run ../graph-explorer-mockup/export.exs
alias EhOsContract.Graph.{Document, Overlay}

EhOsContract.Registry.load!()

period = [since: nil]
modules = EhOsContract.Registry.contracts() ++ EhOsContract.Registry.processes()
domain = EhOsContract.Tools.domain!(EhOsContract.Registry.domains(), "graph-lab")
id = &EhOsContract.Model.fetch(&1).id
in_set? = &String.starts_with?(id.(&1), "graph-lab.")

contracts =
  for c <- EhOsContract.Registry.contracts(), in_set?.(c), into: %{} do
    {"contract:" <> id.(c), %{"doc" => Document.contract(c), "overlay" => Overlay.contract(c, period)}}
  end

processes =
  for p <- EhOsContract.Registry.processes(), in_set?.(p), into: %{} do
    {"process:" <> id.(p), %{"doc" => Document.process(p), "overlay" => Overlay.process(p, period)}}
  end

data = %{
  "domain" => Document.domain(domain, modules),
  "domainOverlay" => Overlay.domain(domain, modules, period),
  "contracts" => contracts,
  "processes" => processes,
  "scale" => Document.contract(EhOsContract.Registry.contract("appunite_equipment.computers"))
}

File.write!(Path.join(__DIR__, "data.js"), "window.DATA = " <> Document.encode(data) <> ";\n")
IO.puts(:stderr, "wrote data.js")

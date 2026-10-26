defmodule EhOsContractHost.BundleTaskTest do
  # eh-os D-146 (EmpoweredHouse/eh-os-contract#456): a project with contracts gets the bundle
  # EHOS takes, its manifest and every graph document named in bundle.json with their size and
  # SHA-256, each the bytes the two commands it runs write alone.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  @moduletag :tmp_dir

  defp sha256(path), do: :crypto.hash(:sha256, File.read!(path)) |> Base.encode16(case: :lower)

  defp described(dir, path),
    do: %{
      "path" => path,
      "bytes" => File.stat!(Path.join(dir, path)).size,
      "sha256" => sha256(Path.join(dir, path))
    }

  test "the bundle holds the manifest and each graph document, by size and digest", %{
    tmp_dir: dir
  } do
    out = Path.join(dir, "bundle")
    output = capture_io(fn -> Mix.Tasks.EhOsContract.Bundle.run(["--output-dir", out]) end)

    graph = out |> Path.join("graph") |> File.ls!() |> Enum.sort()
    assert "domain.Billing.Domain.json" in graph
    assert "contract.billing.subscriptions.json" in graph
    assert output =~ "written: a bundle of #{length(graph)} graph documents in #{out}"

    index = Jason.decode!(File.read!(Path.join(out, "bundle.json")))

    assert index == %{
             "schema" => "ehos.bundle/v1",
             "manifest" => described(out, "ehos.manifest.json"),
             "graph" => Enum.map(graph, &described(out, "graph/#{&1}"))
           }

    assert %{"application" => "billing"} =
             Jason.decode!(File.read!(Path.join(out, "ehos.manifest.json")))

    # Each file is what the command that writes that part alone writes.
    alone = Path.join(dir, "alone.json")
    Mix.Task.reenable("eh_os_contract.manifest")
    capture_io(fn -> Mix.Tasks.EhOsContract.Manifest.run(["--output", alone]) end)
    assert File.read!(alone) == File.read!(Path.join(out, "ehos.manifest.json"))

    # The index's keys are in the order docs/bundle.md gives them.
    assert File.read!(Path.join(out, "bundle.json")) =~
             ~r/\A\{\n  "schema": "ehos.bundle\/v1",\n  "manifest": \{\n    "path": "ehos.manifest.json",\n    "bytes": \d+,\n    "sha256": "[0-9a-f]{64}"\n  \},\n  "graph": \[/
  end
end

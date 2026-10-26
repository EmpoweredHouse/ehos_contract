defmodule EhOsContract.Auth.BundleTaskTest do
  @moduledoc """
  #456: `mix eh_os_contract.bundle` writes the manifest, the graph documents and
  `bundle.json`, which names each with its size and SHA-256, and writes nothing EHOS would refuse.
  This package's own application holds no contracts, so here a bundle is refused as its manifest
  is; the sandbox's test writes one. Not async: it runs Mix tasks.
  """

  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias EhOsContract.Auth.Bundle
  alias Mix.Tasks.EhOsContract.Bundle, as: Task

  @moduletag :tmp_dir

  @ehos_yaml """
  schema: ehos.yaml/v1
  serves:
    - name: web
      port: 4000
  health:
    port: 4001
    ready: /health/ready
    live: /health/live
  """

  defp ehos_yaml(dir) do
    path = Path.join(dir, "ehos.yaml")
    File.write!(path, @ehos_yaml)
    path
  end

  defp refused(args) do
    error = assert_raise Mix.Error, fn -> capture_io(fn -> Task.run(args) end) end
    error.message
  end

  # A manifest offers what the contracts declare, so a project with none has no manifest to send.
  test "a project with no contracts is refused, as its manifest is, and leaves nothing", %{
    tmp_dir: dir
  } do
    out = Path.join(dir, "bundle")

    assert refused(["--output-dir", out, "--ehos-yaml", ehos_yaml(dir)]) ==
             "no EhOsContract.Domain is registered"

    refute File.exists?(out)

    File.mkdir_p!(out)
    assert refused(["--output-dir", out, "--ehos-yaml", ehos_yaml(dir)]) =~ "no EhOsContract"
    assert File.ls!(out) == []
  end

  test "a directory that holds anything is refused, and left as it was", %{tmp_dir: dir} do
    out = Path.join(dir, "bundle")
    File.mkdir_p!(out)
    File.write!(Path.join(out, "old.json"), "{}")

    assert refused(["--output-dir", out, "--ehos-yaml", ehos_yaml(dir)]) ==
             "#{out} holds files already; --output-dir writes into an empty one"

    assert File.ls!(out) == ["old.json"]
  end

  test "an ehos.yaml EHOS refuses writes no bundle, and leaves no directory", %{tmp_dir: dir} do
    bad = Path.join(dir, "ehos.yaml")
    File.write!(bad, "schema: ehos.yaml/v1\n")
    out = Path.join(dir, "bundle")

    assert refused(["--output-dir", out, "--ehos-yaml", bad]) =~
             "is refused, as EHOS would refuse it"

    refute File.exists?(out)
  end

  test "its arguments are said as the manifest's are", %{tmp_dir: dir} do
    assert refused([]) == "say where the bundle goes: --output-dir <dir>"
    assert refused(["--output-dir"]) == "--output-dir needs a value"
    assert refused(["--output-dir", dir, "--output", "x"]) == "unknown options: --output"
    assert refused(["--output-dir", dir, "extra"]) == "unexpected arguments: extra"
  end

  describe "the index" do
    test "is refused as EHOS refuses it: a name the schema does not take", %{tmp_dir: dir} do
      File.write!(Path.join(dir, "ehos.manifest.json"), "{}")
      File.mkdir_p!(Path.join(dir, "graph"))
      File.write!(Path.join(dir, "graph/.hidden.json"), "{}")

      assert {:error, [reason]} = Bundle.index(dir, "ehos.manifest.json", ["graph/.hidden.json"])
      assert reason =~ "bundle.json at /graph/0/path"
    end

    test "names a path once, without regard to case", %{tmp_dir: dir} do
      File.write!(Path.join(dir, "ehos.manifest.json"), "{}")
      File.mkdir_p!(Path.join(dir, "graph"))
      # Two files where case counts, one where it is ignored: the names are refused either way.
      File.write!(Path.join(dir, "graph/a.json"), "{}")
      File.write!(Path.join(dir, "graph/A.json"), "{}")

      assert {:error, [reason]} =
               Bundle.index(dir, "ehos.manifest.json", ["graph/a.json", "graph/A.json"])

      assert reason =~ "name one file where case is ignored"
    end

    test "keeps the graph documents to 32 MiB in all", %{tmp_dir: dir} do
      File.write!(Path.join(dir, "ehos.manifest.json"), "{}")
      File.mkdir_p!(Path.join(dir, "graph"))
      full = String.duplicate(" ", 1_048_576)
      paths = for n <- 1..33, do: "graph/c#{n}.json"
      for path <- paths, do: File.write!(Path.join(dir, path), full)

      assert Bundle.index(dir, "ehos.manifest.json", paths) ==
               {:error, ["the graph documents hold 34603008 bytes; EHOS takes at most 33554432"]}

      assert {:ok, _index} = Bundle.index(dir, "ehos.manifest.json", Enum.take(paths, 32))
    end

    test "keeps 512 documents at most, and 1 MiB each, refused before any file is read", %{
      tmp_dir: dir
    } do
      File.write!(Path.join(dir, "ehos.manifest.json"), "{}")
      File.mkdir_p!(Path.join(dir, "graph"))
      File.write!(Path.join(dir, "graph/big.json"), String.duplicate(" ", 1_048_577))

      assert Bundle.index(dir, "ehos.manifest.json", ["graph/big.json"]) ==
               {:error, ["graph/big.json is larger than the 1048576 bytes EHOS reads"]}

      # None of these is there: their number alone refuses them.
      many = for n <- 1..513, do: "graph/c#{n}.json"

      assert Bundle.index(dir, "ehos.manifest.json", many) ==
               {:error, ["the bundle holds 513 graph documents; EHOS takes at most 512"]}
    end
  end

  describe "the schema" do
    test "is EHOS's ehos.bundle/v1, byte for byte" do
      # EHOS's `priv/schemas/ehos.bundle/v1.json`, as read on 26 October 2026, in no release
      # yet. A new hash here is a new copy of EHOS's file, never an
      # edit of this one.
      document = File.read!(Bundle.schema_file())

      assert :crypto.hash(:sha256, document) |> Base.encode16(case: :lower) ==
               "fa5e6770cbe09b19c5135174866c9153ee20b9fbf848d7c0e6188ef166095473"

      assert Jason.decode!(document)["title"] == "ehos.bundle/v1"
    end
  end
end

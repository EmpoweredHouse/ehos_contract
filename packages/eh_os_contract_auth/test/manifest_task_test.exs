defmodule EhOsContract.Auth.ManifestTaskTest do
  @moduledoc """
  EH3: what `mix eh_os_contract.manifest` refuses before it reads a contract — its
  arguments and the file it reads — each with what to do instead. Not async: it runs
  a Mix task.
  """

  use ExUnit.Case, async: false

  alias Mix.Tasks.EhOsContract.Manifest, as: Task

  @moduletag :tmp_dir

  defp run!(args) do
    Mix.Task.reenable("eh_os_contract.manifest")
    error = assert_raise Mix.Error, fn -> Task.run(args) end
    error.message
  end

  test "an option given without its value is said to need one, not to be unknown", %{tmp_dir: dir} do
    assert run!(["--output"]) == "--output needs a value"

    assert run!(["--output", Path.join(dir, "m.json"), "--ehos-yaml"]) ==
             "--ehos-yaml needs a value"
  end

  test "an unknown option is named", %{tmp_dir: dir} do
    assert run!(["--output", Path.join(dir, "m.json"), "--schema", "v1"]) ==
             "unknown options: --schema"
  end

  test "the manifest is never written over the ehos.yaml it is made from", %{tmp_dir: dir} do
    ehos_yaml = Path.join(dir, "ehos.yaml")
    File.write!(ehos_yaml, "schema: ehos.yaml/v1\n")

    assert run!(["--ehos-yaml", ehos_yaml, "--output", Path.join([dir, ".", "ehos.yaml"])]) =~
             "--output names the ehos.yaml it is made from"

    assert File.read!(ehos_yaml) == "schema: ehos.yaml/v1\n"
  end

  test "a missing ehos.yaml named by --ehos-yaml is said to be missing", %{tmp_dir: dir} do
    missing = Path.join(dir, "deploy.yaml")

    assert run!(["--ehos-yaml", missing, "--output", Path.join(dir, "m.json")]) ==
             "cannot read #{missing}: no such file or directory"
  end

  # A FIFO with no writer, or a device, would hold the task for ever, or fill its memory.
  @tag timeout: 5_000
  test "what is not a regular file is refused before it is read", %{tmp_dir: dir} do
    fifo = Path.join(dir, "ehos.yaml")
    {_, 0} = System.cmd("mkfifo", [fifo])

    assert run!(["--ehos-yaml", fifo, "--output", Path.join(dir, "m.json")]) ==
             "#{fifo} is not a regular file"
  end

  test "a file larger than EHOS reads is refused before it is read", %{tmp_dir: dir} do
    large = Path.join(dir, "ehos.yaml")
    File.write!(large, String.duplicate("#\n", 40_000))

    assert run!(["--ehos-yaml", large, "--output", Path.join(dir, "m.json")]) ==
             "#{large} is 80000 bytes; EHOS reads at most 65536"
  end
end

defmodule EhosContract.ReportTaskTest do
  @moduledoc """
  `mix ehos_contract.report` (plan E7c-2): one section for every contract the
  registry finds.
  """

  use EhosContract.DataCase, async: false

  alias ProcessShapes.Seed

  @tag :tmp_dir
  test "reports every contract the registry finds, one section each", %{tmp_dir: dir} do
    Seed.deploy()
    Seed.request("r-1", :request_approved)
    path = Path.join(dir, "report.txt")

    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    Mix.Tasks.EhosContract.Report.run(["--output", path])

    text = File.read!(path)

    # Each process in a section of its own, with its own steps, and once.
    assert text =~ "· Decide a request → Request refused"
    assert text =~ "PROCESS: Batch run"
    assert length(String.split(text, "PROCESS: Request handling")) == 2
  end
end

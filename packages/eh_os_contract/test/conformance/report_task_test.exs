defmodule EhOsContract.ReportTaskTest do
  @moduledoc """
  `mix eh_os_contract.report` (plan E7c-2): one section for every contract the
  registry finds, v2 contracts too.
  """

  use EhOsContract.DataCase, async: false

  alias ProcessShapes.Seed

  @tag :tmp_dir
  test "reports a v2 contract beside the v1 ones", %{tmp_dir: dir} do
    Seed.deploy(:v2)
    Seed.request(:v2, "r-1", :request_approved)
    path = Path.join(dir, "report.txt")

    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    Mix.Tasks.EhOsContract.Report.run(["--output", path])

    text = File.read!(path)

    # The v2 port and its v1 original, each with its own section and its own steps.
    assert text =~ "· Decide a request → Request refused"
    assert text =~ "PROCESS: Batch run"
    assert length(String.split(text, "PROCESS: Request handling")) == 3
  end
end

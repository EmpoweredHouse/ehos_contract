defmodule EhOsContract.Auth.DevelopmentReleaseTest do
  # A real release that carries Mix, with the development mode's switch set: `bin/<release>
  # start` refuses to start the mode. There Mix is started and its environment is `:dev` when
  # `MIX_ENV` is not set; no Mix project is loaded, and the release's variables are set.
  #
  # The fixture in `test/fixtures/development_release` is built in a temporary directory beside a
  # copy of this build's compiled applications, so only the fixture and the packages compile.
  use ExUnit.Case, async: true

  @moduletag :tmp_dir
  @moduletag timeout: 180_000

  @fixture Path.expand("fixtures/development_release", __DIR__)
  @package Path.expand("..", __DIR__)

  test "a release with Mix added and the switch set refuses to start the mode", %{tmp_dir: dir} do
    # The copied build and the release are a few hundred megabytes; nothing reads them after.
    on_exit(fn -> File.rm_rf!(dir) end)
    File.cp_r!(@fixture, dir)
    File.cp!(Path.join(@package, "mix.lock"), Path.join(dir, "mix.lock"))
    build = Path.join(dir, "_build/test")
    File.mkdir_p!(build)
    {_, 0} = System.cmd("cp", ["-Rp", Path.join(Mix.Project.build_path(), "lib"), build])

    {output, status} =
      System.cmd("mix", ["release", "--overwrite"],
        cd: dir,
        stderr_to_stdout: true,
        env: [
          {"MIX_ENV", "test"},
          {"DEVELOPMENT_RELEASE_DEPS", Path.join(@package, "deps")},
          {"DEVELOPMENT_RELEASE_AUTH", @package}
        ]
      )

    assert status == 0, output

    {output, status} = start(Path.join(build, "rel/development_release/bin/development_release"))

    assert status != 0
    assert output =~ "the development mode refuses to start here"
    assert output =~ "RELEASE_NAME is set"
    assert output =~ "RELEASE_ROOT is set"
    assert output =~ "no Mix project is loaded"
    # Mix is started in this release, as the case needs.
    refute output =~ "the :mix application is not started"
  end

  # The release's own `start`, which runs until the node stops; one that has not stopped in a
  # minute started the mode, and is stopped.
  defp start(bin) do
    port =
      Port.open({:spawn_executable, bin}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        args: ["start"],
        env: [
          {~c"MIX_ENV", false},
          {~c"EHOS_ISSUER", false},
          {~c"EHOS_AUDIENCE", false},
          {~c"ERL_CRASH_DUMP_SECONDS", ~c"0"}
        ]
      ])

    collect(port, bin, "")
  end

  defp collect(port, bin, output) do
    receive do
      {^port, {:data, data}} -> collect(port, bin, output <> data)
      {^port, {:exit_status, status}} -> {output, status}
    after
      60_000 ->
        System.cmd(bin, ["stop"], stderr_to_stdout: true)
        flunk("the release did not stop, so it started the development mode:\n" <> output)
    end
  end
end

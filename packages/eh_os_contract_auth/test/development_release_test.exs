defmodule EhOsContract.Auth.DevelopmentReleaseTest do
  # A real release that carries Mix: with the development mode's switch set, `bin/<release>
  # start` refuses to start the mode, and with `pin_keys: true` and `MIX_ENV=test` it refuses the
  # test's trust (#620). There Mix is started, and its environment is `MIX_ENV`'s, or `:dev`
  # when it is not set; no Mix project is loaded, and the release's variables are set.
  #
  # The fixture in `test/fixtures/development_release` is built once, in a temporary directory
  # beside a copy of this build's compiled applications, so only the fixture and the packages
  # compile.
  use ExUnit.Case, async: true

  @moduletag timeout: 180_000

  @fixture Path.expand("fixtures/development_release", __DIR__)
  @package Path.expand("..", __DIR__)

  setup_all do
    # In this checkout, as `@tag :tmp_dir` would put it: worktrees share the system's directory.
    dir = Path.expand("../tmp/#{inspect(__MODULE__)}", __DIR__)
    File.rm_rf!(dir)
    File.mkdir_p!(Path.dirname(dir))

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
    %{bin: Path.join(build, "rel/development_release/bin/development_release")}
  end

  test "a release with Mix added and the switch set refuses to start the mode", %{bin: bin} do
    {output, status} = start(bin, [])

    assert status != 0
    assert output =~ "the development mode refuses to start here"
    assert output =~ "RELEASE_NAME is set"
    assert output =~ "RELEASE_ROOT is set"
    assert output =~ "no Mix project is loaded"
    # Mix is started in this release, as the case needs.
    refute output =~ "the :mix application is not started"
  end

  test "a release with Mix added, MIX_ENV=test and pin_keys: true refuses the test's trust",
       %{bin: bin} do
    {output, status} = start(bin, [{~c"MIX_ENV", ~c"test"}, {~c"RELEASE_CASE", ~c"pin_keys"}])

    assert status != 0
    assert output =~ "pin_keys: true is set where no test runs"
    assert output =~ "Build no release with MIX_ENV=test"
    assert output =~ "RELEASE_NAME is set"
    assert output =~ "RELEASE_ROOT is set"
    # Mix is started, with the environment a test has: the release's variables refuse it alone.
    refute output =~ "Mix's environment is"
  end

  # The release's own `start`, which runs until the node stops; one that has not stopped in a
  # minute started what it should have refused, and is stopped.
  defp start(bin, env) do
    unset =
      for variable <- ~w(MIX_ENV RELEASE_CASE EHOS_ISSUER EHOS_AUDIENCE)c, do: {variable, false}

    env = Enum.reduce(env, unset, &List.keystore(&2, elem(&1, 0), 0, &1))

    port =
      Port.open({:spawn_executable, bin}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        args: ["start"],
        env: [{~c"ERL_CRASH_DUMP_SECONDS", ~c"0"} | env]
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
        flunk("the release did not stop, so it started what it should refuse:\n" <> output)
    end
  end
end

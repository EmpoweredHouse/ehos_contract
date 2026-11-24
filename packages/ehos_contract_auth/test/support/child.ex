defmodule EhosContract.Auth.Child do
  @moduledoc """
  Runs Elixir in a child process of its own, for what a `mix test` process cannot show: it
  always has Mix started, a project loaded and the `:test` environment, which the development
  mode's refusal reads (`EhosContract.Auth.Development`).

  The child runs `elixir -e` with this build's applications on its path, and no Mix started.
  `mix:` sets up what the case needs:

    * `:none`, Mix's code on the path and the application not started;
    * `:started`, the application started and no project;
    * `:project`, the application started and the fixture project in
      `test/fixtures/development` loaded, as `mix phx.server` loads an application's.

  `env:` sets the child's environment variables; `MIX_ENV`, the release's and EHOS's are unset
  unless it names them. `MIX_BUILD_PATH` is a new directory of each run, removed after it,
  unless `env:` names it: the mode writes its address file there, and children run at
  once. `config:` goes over the configuration every child gets: the package's
  issuer and audience, the switch `development: true`, a key set at a closed loopback port, and
  the test repo. `contracts: true` compiles the fixture's domain and contract and loads them as
  the fixture's application, the one the engine reads. `body` is the code to run; its last
  expression's value is what `run/2` answers.
  """

  import ExUnit.Assertions

  @fixture Path.expand("../fixtures/development", __DIR__)
  @cleared ~w(MIX_ENV RELEASE_NAME RELEASE_ROOT RELEASE_NODE EHOS_ISSUER EHOS_AUDIENCE MIX_EXS)

  @doc "Runs `body` in a child process, as the moduledoc says, and answers its value."
  def run(body, opts \\ []) do
    opts = Keyword.validate!(opts, mix: :project, env: [], config: [], contracts: false)

    build =
      Path.join(
        System.tmp_dir!(),
        "ehos_contract_auth_child_#{System.unique_integer([:positive])}"
      )

    env = Enum.map(@cleared, &{&1, nil}) ++ [{"MIX_BUILD_PATH", build}] ++ opts[:env]
    lib = Path.join(Mix.Project.build_path(), "lib")

    script = """
    #{prelude(opts)}
    result = (
    #{body}
    )
    IO.puts("\\nRESULT:" <> Base.encode64(:erlang.term_to_binary(result)))
    """

    {output, status} =
      try do
        System.cmd("elixir", ["-e", script],
          env: [{"ERL_LIBS", lib} | env],
          stderr_to_stdout: true
        )
      after
        File.rm_rf(build)
      end

    case Regex.run(~r/^RESULT:(\S+)$/m, output) do
      [_, encoded] -> encoded |> Base.decode64!() |> :erlang.binary_to_term()
      nil -> flunk("the child process ended without a result (status #{status}):\n" <> output)
    end
  end

  defp prelude(opts) do
    config = encode(config(opts[:config], opts[:contracts]))

    mix =
      case opts[:mix] do
        :none ->
          ""

        :started ->
          "{:ok, _} = Application.ensure_all_started(:mix)"

        :project ->
          """
          {:ok, _} = Application.ensure_all_started(:mix)
          Code.compile_file(#{inspect(Path.join(@fixture, "mix.exs"))})
          """
      end

    contracts =
      if opts[:contracts] do
        """
        modules = for {module, _} <- Code.compile_file(#{inspect(Path.join(@fixture, "lib/clinic.ex"))}), do: module
        :ok = :application.load({:application, :development_fixture, [description: ~c"fixture", vsn: ~c"0.1.0", modules: modules, applications: [:kernel, :stdlib]]})
        """
      else
        ""
      end

    """
    for app <- [:logger, :ehos_contract, :ehos_contract_auth], do: Application.load(app)
    Application.put_all_env(:erlang.binary_to_term(Base.decode64!(#{inspect(config)})))
    Logger.configure(level: :error)
    #{mix}
    #{contracts}
    {:ok, _} = Application.ensure_all_started(:ehos_contract_auth)
    """
  end

  # Each application's keys merged over the base; a key given `:unset` is left out.
  defp config(overrides, contracts?) do
    repo = Application.fetch_env!(:ehos_contract_auth, EhosContract.Auth.TestRepo)
    applications = if contracts?, do: [:development_fixture], else: []

    base = [
      ehos_contract: [
        repo: EhosContract.Auth.TestRepo,
        applications: [:ehos_contract_auth] ++ applications
      ],
      ehos_contract_auth: [
        {:issuer, "https://ehos.test"},
        {:audience, "clinic/test"},
        {:jwks_url, "http://127.0.0.1:9/jwks"},
        {:development, true},
        {EhosContract.Auth.TestRepo, repo}
      ]
    ]

    Keyword.merge(base, overrides, fn _app, base, over ->
      base |> Keyword.merge(over) |> Enum.reject(fn {_key, value} -> value == :unset end)
    end)
  end

  defp encode(term), do: Base.encode64(:erlang.term_to_binary(term))
end

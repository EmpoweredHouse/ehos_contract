defmodule EhOsContract.CompilerTest do
  @moduledoc """
  v2 plan, E5b, acceptance: **L3 breaks a plain `mix compile`** (v2 §6, §8).

  Each test writes a small project into a temporary directory and runs the real
  `mix compile` on it, in its own VM, with `compile.eh_os_contract` registered as a
  consumer registers it. The project has no dependencies: the libraries come from
  this build through `ERL_LIBS`, and `--no-prune-code-paths` keeps Mix from dropping
  what its own `deps` do not list. Each compile takes about a second.

  The rules themselves, one by one, are tested as functions over modules compiled
  in the test (`contract_links_*_test.exs`); this is the check that the compiler
  runs them, fails the compile and says where.
  """

  use ExUnit.Case, async: true

  @moduletag :tmp_dir

  @domain """
  defmodule Fx.Domain do
    use EhOsContract.Domain, name: :fx, language: :pl

    context :settlement, "Rozliczenia", subdomain: :core
    actor :reception, :human, "Recepcja"
  end
  """

  # Line 7 is the command.
  @visit """
  defmodule Fx.Visit do
    use EhOsContract.Next.Contract, domain: Fx.Domain, context: :settlement

    aggregate :visit, "Wizyta" do
      identity :visit_id

      command :close_visit, "Zamknięcie wizyty", by: :reception, emits: :visit_closed
      event :visit_closed, "Wizyta zamknięta", terminal: true
    end

    process :visit, "Wizyta" do
      correlate :visit_id
    end
  end
  """

  test "a typo in by: fails the compile, pointing at the contract", %{tmp_dir: dir} do
    project(dir, %{"lib/domain.ex" => @domain, "lib/visit.ex" => @visit})
    assert {_, 0} = compile(dir)

    write(dir, "lib/visit.ex", String.replace(@visit, "by: :reception", "by: :recepion"))
    {output, status} = compile(dir)

    assert status != 0

    assert output =~
             "X2: command :close_visit: by: :recepion is not an actor of Fx.Domain; did you mean :reception?"

    assert output =~ "lib/visit.ex:7"
    # Printed once: Mix does not print a compiler's diagnostics a second time.
    assert length(String.split(output, "X2:")) == 2
  end

  test "a change to the domain alone fails the compile of a contract nobody recompiled",
       %{tmp_dir: dir} do
    project(dir, %{"lib/domain.ex" => @domain, "lib/visit.ex" => @visit})
    assert {_, 0} = compile(dir)

    write(
      dir,
      "lib/domain.ex",
      String.replace(
        @domain,
        ~s|actor :reception, :human, "Recepcja"|,
        ~s|actor :cashier, :human, "Kasjer"|
      )
    )

    {output, status} = compile(dir)

    # The contract records no compile dependency on its domain (v2 §8), so only the
    # domain is recompiled, and L3 finds the contract's by: out of date anyway.
    assert output =~ "Compiling 1 file (.ex)"
    assert status != 0
    assert output =~ "X2: command :close_visit: by: :reception is not an actor of Fx.Domain"
    assert output =~ "lib/visit.ex:7"
  end

  defp project(dir, files) do
    write(dir, "mix.exs", """
    defmodule Fx.MixProject do
      use Mix.Project

      def project do
        [app: :fx, version: "0.1.0", compilers: Mix.compilers() ++ [:eh_os_contract], deps: []]
      end
    end
    """)

    Enum.each(files, fn {path, source} -> write(dir, path, source) end)
  end

  defp write(dir, path, source) do
    path = Path.join(dir, path)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, source)
  end

  defp compile(dir) do
    System.cmd("mix", ["compile", "--no-prune-code-paths"],
      cd: dir,
      env: [
        {"ERL_LIBS", Path.join(Mix.Project.build_path(), "lib")},
        {"MIX_ENV", "dev"},
        {"MIX_BUILD_PATH", nil}
      ],
      stderr_to_stdout: true
    )
  end
end

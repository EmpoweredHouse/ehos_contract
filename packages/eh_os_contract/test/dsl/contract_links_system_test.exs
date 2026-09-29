defmodule EhOsContract.ContractLinksSystemTest do
  @moduledoc """
  v2 plan, E5b: **X7, X8 and D14's names** (v2 §6, §16) — what has to be unique
  across one application. Of two that collide, the one in the module sorting later
  is refused, naming the other with its file and line; each has a control that
  passes.
  """

  use EhOsContract.DslCase, async: false

  @fixtures EhOsContract.Fixtures
  @domain EhOsContract.Fixtures.SystemClinic

  setup_all do
    compile(
      """
      defmodule #{inspect(@domain)} do
        use EhOsContract.Domain, name: :clinic, language: :pl

        context :settlement, "Rozliczenia", subdomain: :core
        actor :reception, :human, "Recepcja"

        subdomain :core, "Core", type: :core
      end
      """,
      "system_clinic.ex"
    )

    # X8's contract, implemented by the modules its tests compile.
    {file, source} = unit_contract("SysImplemented", process: :implemented, command: :close)
    compile(source, file)

    :ok
  end

  # A contract with one aggregate: the command at line 6, the process at line 10.
  defp unit_contract(name, opts) do
    process = Keyword.fetch!(opts, :process)
    command = Keyword.fetch!(opts, :command)

    source = """
    defmodule #{inspect(Module.concat(@fixtures, name))} do
      use EhOsContract.Contract, domain: #{inspect(@domain)}, context: :settlement

      aggregate #{inspect(process)}, "Jednostka" do
        identity :case_id
        command #{inspect(command)}, "Komenda", by: :reception, emits: :done
        event :done, "Zrobione"
      end

      process #{inspect(process)}, "Proces" do
        correlate :case_id
      end
    #{Keyword.get(opts, :extra, "")}
    end
    """

    {"#{Macro.underscore(name)}.ex", source}
  end

  describe "X7: a process name is the application's" do
    test "two contracts declaring one process" do
      violations =
        links([
          unit_contract("SysProcessA", process: :visit, command: :open_a),
          unit_contract("SysProcessB", process: :visit, command: :open_b)
        ])

      assert assert_linked(violations, "X7:", "sys_process_b.ex", 10) =~
               "process :visit of #{inspect(@fixtures)}.SysProcessB is also declared by " <>
                 "#{inspect(@fixtures)}.SysProcessA (sys_process_a.ex:10); a process's name " <>
                 "prefixes its event types, so it is unique in the application"

      assert length(violations) == 1
    end
  end

  describe "D14: a command, query or recorded event name is the domain's" do
    test "a command of one name in two contracts, and a query named like a command" do
      query = """
        read_model :cases, "Sprawy", projects: :done do
          field :case_id, :id
        end

        query :open_a, "Sprawy", reads: :cases, by: :reception
      """

      violations =
        links([
          unit_contract("SysNameA", process: :first, command: :open_a),
          unit_contract("SysNameB", process: :second, command: :open_a),
          unit_contract("SysNameC", process: :third, command: :open_c, extra: query)
        ])

      assert assert_linked(
               violations,
               "D14: command :open_a of #{inspect(@fixtures)}.SysNameB",
               "sys_name_b.ex",
               6
             ) =~
               ~s|has the capability "clinic.open_a", which command :open_a of | <>
                 "#{inspect(@fixtures)}.SysNameA (sys_name_a.ex:6) has already"

      assert_linked(
        violations,
        "D14: query :open_a of #{inspect(@fixtures)}.SysNameC",
        "sys_name_c.ex",
        17
      )

      assert length(violations) == 2
    end

    test "a recorded event named like another contract's command (plan E9a)" do
      # A person's recording has the capability `<domain>.<event>`, so it collides
      # with a command of that name. The event is at line 8.
      recorded = """
      defmodule #{inspect(@fixtures)}.SysNameD do
        use EhOsContract.Contract, domain: #{inspect(@domain)}, context: :settlement

        aggregate :fourth, "Jednostka" do
          identity :case_id
          command :open_d, "Komenda", by: :reception, emits: :done
          event :done, "Zrobione"
          event :open_a, "Otwarte", recorded_by: :reception
        end

        process :fourth, "Proces" do
          correlate :case_id
        end
      end
      """

      violations =
        links([
          unit_contract("SysNameCmd", process: :first_rec, command: :open_a),
          {"sys_name_d.ex", recorded}
        ])

      assert assert_linked(
               violations,
               "D14: record :open_a of #{inspect(@fixtures)}.SysNameD",
               "sys_name_d.ex",
               8
             ) =~ ~s|has the capability "clinic.open_a", which command :open_a of |

      assert length(violations) == 1
    end

    test "control: distinct names pass" do
      assert links([
               unit_contract("SysDistinctA", process: :one, command: :open_one),
               unit_contract("SysDistinctB", process: :two, command: :open_two)
             ]) == []
    end
  end

  describe "X8: one implementation per declaration" do
    # An implementation of the aggregate; its `use` is at line 2.
    defp implementation(name) do
      {"#{Macro.underscore(name)}.ex",
       """
       defmodule EhOsContract.Fixtures.Implementations.#{name} do
         use #{inspect(@fixtures)}.SysImplemented, aggregate: :implemented

         @impl true
         def close(%Close{case_id: id}, _state), do: emit(%Done{case_id: id})
       end
       """}
    end

    test "two modules implementing one aggregate" do
      violations = links([implementation("SysFirst"), implementation("SysSecond")])

      assert assert_linked(violations, "X8:", "sys_second.ex", 2) =~
               "EhOsContract.Fixtures.Implementations.SysSecond implements aggregate :implemented of " <>
                 "#{inspect(@fixtures)}.SysImplemented, which " <>
                 "EhOsContract.Fixtures.Implementations.SysFirst (sys_first.ex:2) implements already"

      assert length(violations) == 1
    end

    test "an implementation compiled before it said where it is is still refused, without a place" do
      # A beam from before `__eh_os_implementation__/0` carried `file:` and `line:`, as
      # a consumer's build may hold one after upgrading the library.
      stale =
        for name <- [SysStaleFirst, SysStaleSecond] do
          module = Module.concat(EhOsContract.Fixtures.Implementations, name)

          {:module, ^module, _, _} =
            Module.create(
              module,
              quote do
                def __eh_os_implementation__,
                  do: %{
                    contract: EhOsContract.Fixtures.SysImplemented,
                    kind: :aggregate,
                    name: :implemented,
                    emitted: %{}
                  }
              end,
              Macro.Env.location(__ENV__)
            )

          module
        end

      assert [{"X8: EhOsContract.Fixtures.Implementations.SysStaleSecond implements" <> _, nil}] =
               EhOsContract.Contract.Links.check(stale)
    end

    test "control: one implementation passes" do
      assert links([implementation("SysOnly")]) == []
    end
  end
end

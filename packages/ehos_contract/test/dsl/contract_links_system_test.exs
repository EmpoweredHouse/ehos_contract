defmodule EhosContract.ContractLinksSystemTest do
  @moduledoc """
  v2 plan, E5b: **X7, X8 and D14's names** (v2 §6, §16) — what has to be unique
  across one application. Of two that collide, the one in the module sorting later
  is refused, naming the other with its file and line; each has a control that
  passes.
  """

  use EhosContract.DslCase, async: false

  @fixtures EhosContract.Fixtures
  @domain EhosContract.Fixtures.SystemClinic

  setup_all do
    compile(
      """
      defmodule #{inspect(@domain)} do
        use EhosContract.Domain, name: :clinic, language: :en

        context :settlement, "Settlement", subdomain: :core
        actor :reception, :human, "Reception"

        subdomain :core, "Core", type: :core
      end
      """,
      "system_clinic.ex"
    )

    # X8's contract, implemented by the modules its tests compile.
    {file, source} = unit_contract("SysImplemented", unit: :implemented, command: :close)
    compile(source, file)

    :ok
  end

  # A contract with one aggregate: the command at line 6, and what `extra:` adds from
  # line 9. A process module's id among the system's processes (X7) is
  # `ProcessLinksTest`'s.
  defp unit_contract(name, opts) do
    unit = Keyword.fetch!(opts, :unit)
    command = Keyword.fetch!(opts, :command)

    source = """
    defmodule #{inspect(Module.concat(@fixtures, name))} do
      use EhosContract.Contract, domain: #{inspect(@domain)}, context: :settlement, id: "clinic.#{contract_name(name)}"

      aggregate #{inspect(unit)}, "Unit" do
        identity :case_id
        command #{inspect(command)}, "Command", by: :reception, emits: :done
        event :done, "Done"
      end
    #{Keyword.get(opts, :extra, "")}
    end
    """

    {"#{Macro.underscore(name)}.ex", source}
  end

  # #697: a published name is built from the namespace and the publication's name.
  describe "X7: a publication's name is the application's" do
    test "two contracts publishing one name, at any version" do
      publish = fn version ->
        "  publish :case_done, version: #{version}, from: :done, fields: [:case_id]"
      end

      violations =
        links([
          unit_contract("SysPubA", unit: :pub_a, command: :close_a, extra: publish.(1)),
          unit_contract("SysPubB", unit: :pub_b, command: :close_b, extra: publish.(2))
        ])

      assert assert_linked(
               violations,
               "X7: publication :case_done of #{inspect(@fixtures)}.SysPubB",
               "sys_pub_b.ex",
               9
             ) =~
               "is also published by #{inspect(@fixtures)}.SysPubA (sys_pub_a.ex:9), as " <>
                 ~s|"clinic.case_done.v1"; a published name is built from the namespace and the | <>
                 ~s|publication's name, "clinic.case_done", so it is unique in the application|

      assert length(violations) == 1
    end

    test "control: two publications of two names" do
      assert links([
               unit_contract("SysPubC",
                 unit: :pub_c,
                 command: :close_c,
                 extra: "  publish :case_closed, from: :done, fields: [:case_id]"
               ),
               unit_contract("SysPubD",
                 unit: :pub_d,
                 command: :close_d,
                 extra: "  publish :case_done, from: :done, fields: [:case_id]"
               )
             ]) == []
    end
  end

  describe "D14: a command, query or recorded event name is the domain's" do
    test "a command of one name in two contracts, and a query named like a command" do
      query = """
        read_model :cases, "Cases", projects: :done do
          field :case_id, :id
        end

        query :open_a, "Cases", reads: :cases, by: :reception
      """

      violations =
        links([
          unit_contract("SysNameA", unit: :first, command: :open_a),
          unit_contract("SysNameB", unit: :second, command: :open_a),
          unit_contract("SysNameC", unit: :third, command: :open_c, extra: query)
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
        13
      )

      assert length(violations) == 2
    end

    test "a recorded event named like another contract's command (plan E9a)" do
      # A person's recording has the capability `<domain>.<event>`, so it collides
      # with a command of that name. The event is at line 8.
      recorded = """
      defmodule #{inspect(@fixtures)}.SysNameD do
        use EhosContract.Contract, domain: #{inspect(@domain)}, context: :settlement, id: "clinic.sys_name_d"

        aggregate :fourth, "Unit" do
          identity :case_id
          command :open_d, "Command", by: :reception, emits: :done
          event :done, "Done"
          event :open_a, "Opened", recorded_by: :reception
        end
      end
      """

      violations =
        links([
          unit_contract("SysNameCmd", unit: :first_rec, command: :open_a),
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
               unit_contract("SysDistinctA", unit: :one, command: :open_one),
               unit_contract("SysDistinctB", unit: :two, command: :open_two)
             ]) == []
    end
  end

  describe "X8: one implementation per declaration" do
    # An implementation of the aggregate; its `use` is at line 2.
    defp implementation(name) do
      {"#{Macro.underscore(name)}.ex",
       """
       defmodule EhosContract.Fixtures.Implementations.#{name} do
         use #{inspect(@fixtures)}.SysImplemented, aggregate: :implemented

         @impl true
         def close(%Close{case_id: id}, _state), do: emit(%Done{case_id: id})
       end
       """}
    end

    test "two modules implementing one aggregate" do
      violations = links([implementation("SysFirst"), implementation("SysSecond")])

      assert assert_linked(violations, "X8:", "sys_second.ex", 2) =~
               "EhosContract.Fixtures.Implementations.SysSecond implements aggregate :implemented of " <>
                 "#{inspect(@fixtures)}.SysImplemented, which " <>
                 "EhosContract.Fixtures.Implementations.SysFirst (sys_first.ex:2) implements already"

      assert length(violations) == 1
    end

    test "an implementation compiled before it said where it is is still refused, without a place" do
      # A beam from before `__ehos_implementation__/0` carried `file:` and `line:`, as
      # a consumer's build may hold one after upgrading the library.
      stale =
        for name <- [SysStaleFirst, SysStaleSecond] do
          module = Module.concat(EhosContract.Fixtures.Implementations, name)

          {:module, ^module, _, _} =
            Module.create(
              module,
              quote do
                def __ehos_implementation__,
                  do: %{
                    contract: EhosContract.Fixtures.SysImplemented,
                    kind: :aggregate,
                    name: :implemented,
                    emitted: %{}
                  }
              end,
              Macro.Env.location(__ENV__)
            )

          module
        end

      assert [{"X8: EhosContract.Fixtures.Implementations.SysStaleSecond implements" <> _, nil}] =
               EhosContract.Contract.Links.check(stale)
    end

    test "control: one implementation passes" do
      assert links([implementation("SysOnly")]) == []
    end
  end
end

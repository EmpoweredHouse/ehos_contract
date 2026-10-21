defmodule EhOsContract.CheckCompilerTest do
  @moduledoc """
  Plan EL1, v2 §6 L5: **`check` repeats the rules between modules (L3) for a project
  that does not run the compiler `:eh_os_contract`**, as errors under the codes the
  compiler prints; a project that runs it hears nothing twice.
  """

  use EhOsContract.DslCase, async: false

  alias EhOsContract.Check
  alias EhOsContract.Check.Finding

  @broken EhOsContract.Fixtures.CheckCompilerBroken

  setup_all do
    # A contract naming a domain nobody compiled: X1.
    compile(
      contract("CheckCompilerBroken", """
        aggregate :visit, "Visit" do
          identity :visit_id
          command :book, "Book", by: :reception, emits: :booked
          event :booked, "Booked"
        end
      """),
      "check_compiler_broken.ex"
    )

    :ok
  end

  test "without the compiler, its violations are errors of check, under their codes" do
    assert [%Finding{rule: "X1", level: :error, message: message} = finding] =
             Check.compiler_findings([:elixir, :app], fn -> [@broken] end)

    assert message ==
             "#{inspect(@broken)} names domain Clinic, which is not a compiled EhOsContract.Domain"

    assert Finding.place(finding) == {"check_compiler_broken.ex", 2}
  end

  test "control: with the compiler, nothing is repeated, and nothing is scanned for it" do
    assert Check.compiler_findings([:elixir, :eh_os_contract], fn -> flunk("scanned") end) == []
  end

  test "a message naming no code is still an error, of the compiler's layer" do
    assert %Finding{rule: "L3", level: :error, message: "a row of read models"} =
             Finding.compiler({"a row of read models", nil})
  end
end

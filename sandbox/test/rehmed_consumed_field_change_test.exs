defmodule Rehmed.ConsumedFieldChangeTest do
  @moduledoc """
  E9's acceptance, v2 §7: **a change to the structure of an event another contract
  consumes breaks the subscriber's contract and its implementation, and each
  refusal names the other side**; a change the subscriber does not use touches
  neither.

  The pair is the sandbox's own: documentation publishes `visit_closed_clinically`,
  statutory reporting consumes it, and its policy `ReportOnClinicalClose` reads
  `p1_reported` to decide whether the visit owes P1 a report. The test compiles
  copies of the three real files under a namespace of their own — the publisher
  changed as its author would change it, the rest as they are — so what breaks is
  what would break in the real tree, and the real modules stay as they are.

  The subscriber's contract breaks through its scenario, which feeds the policy a
  `visit_closed_clinically` with `p1_reported:`; the contract has no compile
  dependency on its sibling (v2 §8), so the refusal is the rules between modules
  (L3, `EhOsContract.Contract.Links`), which the project's compiler runs.
  """

  use ExUnit.Case, async: false

  @publisher "lib/rehmed/contracts/clinical_documentation.ex"
  @subscriber "lib/rehmed/contracts/statutory_reporting.ex"
  @policy "lib/rehmed/statutory_reporting/report_on_clinical_close.ex"

  # The real sources, renamed into `namespace`: every module of the three files, and
  # every reference to them. Scheduling, the domain and the library stay the real
  # ones, as they would in the tree.
  defp copy(file, namespace, change \\ & &1) do
    file
    |> File.read!()
    |> change.()
    |> String.replace(
      "Rehmed.Contracts.ClinicalDocumentation",
      "#{namespace}.ClinicalDocumentation"
    )
    |> String.replace("Rehmed.Contracts.StatutoryReporting", "#{namespace}.StatutoryReporting")
    |> String.replace(
      "Rehmed.StatutoryReporting.ReportOnClinicalClose",
      "#{namespace}.ReportOnClinicalClose"
    )
  end

  # Spark records a declaration's file and line only with `:debug_info` on, which
  # `mix compile` sets and a string compiled in a test does not.
  defp compile(source, file) do
    previous = Code.get_compiler_option(:debug_info)
    Code.put_compiler_option(:debug_info, true)

    try do
      for {module, _binary} <- Code.compile_string(source, file), do: module
    after
      Code.put_compiler_option(:debug_info, previous)
    end
  end

  # The two contracts compiled and checked against each other, as the project's
  # compiler does; the violations with their file and line. The real scheduling contract
  # is checked beside them, as in the tree: both identities are its visit's number
  # (plan DD, L3 (#286)).
  defp contracts(namespace, change) do
    modules =
      compile(copy(@publisher, namespace, change), @publisher) ++
        compile(copy(@subscriber, namespace), @subscriber) ++ [Rehmed.Contracts.Scheduling]

    for {message, anno} <- EhOsContract.Contract.Links.check(modules),
        do: {message, anno && to_string(:erl_anno.file(anno)), anno && :erl_anno.line(anno)}
  end

  # The subscriber's implementation compiled against the changed publisher; the
  # compiler's first error, or `:compiled`.
  defp policy(namespace) do
    {result, diagnostics} =
      Code.with_diagnostics(fn ->
        try do
          compile(copy(@policy, namespace), @policy)
          :compiled
        rescue
          CompileError -> :refused
        end
      end)

    case Enum.filter(diagnostics, &(&1.severity == :error)) do
      [] -> result
      [first | _] -> {first.message, first.file, first.position}
    end
  end

  defp namespace(name), do: "E9FieldChange.#{name}"

  test "control: the three files as they are link with nothing to say" do
    ns = namespace("Unchanged")
    assert contracts(ns, & &1) == []
    assert policy(ns) == :compiled
  end

  test "renaming a field the subscriber reads breaks its contract and its implementation" do
    ns = namespace("Renamed")

    # The publisher's author renames the flag on their event and in their scenarios of
    # it, and leaves alone what is not theirs: scheduling's `visit_booked`, whose flag
    # the documentation reads into its state (plan DD, A2 (#249)). Their contract
    # compiles.
    rename = fn source ->
      source
      |> String.replace(
        ~r/(event :visit_closed_clinically[^\n]*\n(?:      [^\n]*\n)*?      field :)p1_reported/u,
        "\\1reported_to_p1"
      )
      |> String.split("\n")
      |> Enum.map_join("\n", fn line ->
        if line =~ "visit_closed_clinically",
          do: String.replace(line, "p1_reported", "reported_to_p1"),
          else: line
      end)
    end

    violations = contracts(ns, rename)

    # The subscriber's contract, at each scenario that feeds the policy the event:
    # the field it gives is gone, the one it lacks is required, and each names the
    # publisher's event with the file and line it is declared at.
    lines = File.read!(@subscriber) |> String.split("\n")

    assert length(violations) == 4

    for {message, file, line} <- violations do
      assert file == @subscriber
      assert Enum.at(lines, line - 1) =~ "on :visit_closed_clinically"

      assert message =~
               "event :visit_closed_clinically of #{ns}.ClinicalDocumentation (#{@publisher}:"
    end

    # At each of the two scenarios, both halves of the rename: the old field is gone,
    # and the new one is required.
    assert Enum.count(violations, fn {m, _, _} -> m =~ "no field :p1_reported" end) == 2
    assert Enum.count(violations, fn {m, _, _} -> m =~ "needs :reported_to_p1" end) == 2

    # The subscriber's implementation, at the pattern that reads the field.
    assert {refusal, file, {policy_line, _column}} = policy(ns)
    assert refusal =~ "unknown key :p1_reported"
    assert Path.relative_to_cwd(file) == @policy

    assert File.read!(@policy) |> String.split("\n") |> Enum.at(policy_line - 1) =~
             "p1_reported: true"
  end

  test "control: a field the subscriber does not read touches neither side" do
    # An optional field added to the consumed event: nothing the subscriber
    # declares or matches names it.
    ns = namespace("Added")

    add =
      &String.replace(
        &1,
        "      field :p1_reported, :boolean\n    end\n  end",
        "      field :p1_reported, :boolean\n      field :note, :string, optional: true\n    end\n  end"
      )

    assert File.read!(@publisher) != add.(File.read!(@publisher))
    assert contracts(ns, add) == []
    assert policy(ns) == :compiled
  end

  test "control: a field of an event nobody consumes touches neither side" do
    ns = namespace("Unconsumed")

    rename =
      &String.replace(
        &1,
        ~s|event :diagnosis_coded, "Wybrano ICD10 / ICD9", source: "E-44" do\n      field :patient_id, :id, subject: :patient\n      field :icd10|,
        ~s|event :diagnosis_coded, "Wybrano ICD10 / ICD9", source: "E-44" do\n      field :patient_id, :id, subject: :patient\n      field :icd10_code|
      )

    assert File.read!(@publisher) != rename.(File.read!(@publisher))

    # The publisher's own scenario names `icd10` on this event, so its author renames
    # it there too.
    rename_all = fn source ->
      source
      |> rename.()
      |> String.replace(
        ~s|expect :diagnosis_coded, %{icd10: "M54.5", icd9: "93.39"}|,
        ~s|expect :diagnosis_coded, %{icd10_code: "M54.5", icd9: "93.39"}|
      )
    end

    assert contracts(ns, rename_all) == []
    assert policy(ns) == :compiled
  end
end

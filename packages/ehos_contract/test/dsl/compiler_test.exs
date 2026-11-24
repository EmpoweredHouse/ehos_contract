defmodule EhosContract.CompilerTest do
  @moduledoc """
  v2 plan, E5b, acceptance: **L3 breaks a plain `mix compile`** (v2 §6, §8).

  Each test writes a small project into a temporary directory and runs the real
  `mix compile` on it, in its own VM, with `compile.ehos_contract` registered as a
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
    use EhosContract.Domain, name: :fx, language: :en

    context :settlement, "Settlement", subdomain: :core
    actor :reception, :human, "Reception"

    subdomain :core, "Core", type: :core
  end
  """

  # Line 7 is the command.
  @visit """
  defmodule Fx.Visit do
    use EhosContract.Contract, domain: Fx.Domain, context: :settlement, id: "fx.visit"

    aggregate :visit, "Visit" do
      identity :visit_id

      command :close_visit, "Closing a visit", by: :reception, emits: :visit_closed
      event :visit_closed, "Visit closed"
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
        ~s|actor :reception, :human, "Reception"|,
        ~s|actor :cashier, :human, "Cashier"|
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

  # Line 9 is the event, line 10 the field the subscriber correlates on.
  @booking """
  defmodule Fx.Booking do
    use EhosContract.Contract, domain: Fx.Domain, context: :settlement, id: "fx.booking"

    aggregate :booking, "Booking" do
      identity :booking_id

      command :book_visit, "Booking a visit", by: :reception, emits: :visit_booked

      event :visit_booked, "Visit booked" do
        field :visit_id, :id
        field :room, :string
      end
    end
  end
  """

  # Line 14 starts a run of the process manager on the publisher's event.
  @billing """
  defmodule Fx.Billing do
    use EhosContract.Contract, domain: Fx.Domain, context: :settlement, id: "fx.billing"

    consumes Fx.Booking, :visit_booked

    aggregate :billing, "Billing" do
      identity :visit_id
      command :bill_visit, "Billing a visit", by: :reception, emits: :visit_billed
      event :visit_billed, "Visit billed"
    end

    process_manager :chase, "Chase" do
      correlate :visit_id
      starts_on :visit_booked
      ends_on :visit_billed
    end
  end
  """

  test "a change to a consumed event fails the compile of its subscriber, naming both sides",
       %{tmp_dir: dir} do
    project(dir, %{
      "lib/domain.ex" => @domain,
      "lib/booking.ex" => @booking,
      "lib/billing.ex" => @billing
    })

    assert {_, 0} = compile(dir)

    # Controls: an optional field added, and a field the subscriber does not use
    # retyped, compile.
    edit(dir, "lib/booking.ex", @booking, [
      {"field :room, :string",
       "field :room, :integer\n      field :note, :string, optional: true"}
    ])

    assert {_, 0} = compile(dir)

    # The field the subscriber correlates on, retyped. Only the publisher is
    # recompiled: the subscriber records no compile dependency on it (v2 §8).
    edit(dir, "lib/booking.ex", @booking, [{"field :visit_id, :id", "field :visit_id, :string"}])
    {output, status} = compile(dir)

    assert status != 0
    assert output =~ "Compiling 1 file (.ex)"

    assert output =~
             "X6: process manager :chase handles :visit_booked and correlates on :visit_id, which " <>
               "event :visit_booked of Fx.Booking (lib/booking.ex:9) has as :string, not :id"

    assert output =~ "lib/billing.ex:14"

    # And removed.
    edit(dir, "lib/booking.ex", @booking, [{"field :visit_id, :id\n", ""}])
    {output, status} = compile(dir)

    assert status != 0
    assert output =~ "event :visit_booked of Fx.Booking (lib/booking.ex:9) does not have"
    assert output =~ "lib/billing.ex:14"
  end

  # Plan DD, P2b (#205): a process module names its contracts as `consumes` does.
  @clinical_visit """
  defmodule Fx.ClinicalVisit do
    use EhosContract.Process, id: "fx.clinical_visit", domain: Fx.Domain, label: "Visit"

    correlate :visit_id
    stage :closing, include: [{Fx.Visit, :visit_closed}]
    ends_on :visit_closed
  end
  """

  test "a change to a contract recompiles no process module that includes its events",
       %{tmp_dir: dir} do
    project(dir, %{
      "lib/domain.ex" => @domain,
      "lib/visit.ex" => @visit,
      "lib/clinical_visit.ex" => @clinical_visit
    })

    assert {_, 0} = compile(dir)

    edit(dir, "lib/visit.ex", @visit, [
      {~s|event :visit_closed, "Visit closed"|,
       ~s|event :visit_closed, "Visit closed" do\n        field :note, :string, optional: true\n      end|}
    ])

    {output, status} = compile(dir)

    assert status == 0, output
    assert output =~ "Compiling 1 file (.ex)"
  end

  defp edit(dir, path, source, replacements) do
    edited =
      Enum.reduce(replacements, source, fn {from, to}, acc ->
        true = acc =~ from
        String.replace(acc, from, to)
      end)

    write(dir, path, edited)
  end

  defp project(dir, files) do
    write(dir, "mix.exs", """
    defmodule Fx.MixProject do
      use Mix.Project

      def project do
        [app: :fx, version: "0.1.0", compilers: Mix.compilers() ++ [:ehos_contract], deps: []]
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

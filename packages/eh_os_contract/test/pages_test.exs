defmodule EhOsContract.PagesTest do
  @moduledoc """
  Plan EL3: **a domain and its contracts as Markdown pages, one per element, linked**
  (ESDM's `documentation`), and `mix eh_os_contract.pages --output`, which writes
  them, deletes what it wrote before and no longer has, and with `--check` says
  whether a directory is current.
  """

  use ExUnit.Case, async: false

  alias EhOsContract.{Pages, Registry}

  defp pages(domain), do: Pages.render(domain, Registry.v2_contracts())

  # Every relative Markdown link on a page, resolved against the page's directory.
  defp links(path, text) do
    for [_, target] <- Regex.scan(~r/\]\(([^)#]+)\)/, text),
        not String.contains?(target, "://") do
      path |> Path.dirname() |> Path.join(target) |> Path.expand("/") |> Path.relative_to("/")
    end
  end

  test "every link on every page of every fixture domain leads to a page there" do
    for domain <- Registry.domains() do
      pages = pages(domain)

      for {path, text} <- pages, target <- links(path, text) do
        assert Map.has_key?(pages, target),
               "#{inspect(domain)}: #{path} links to #{target}, which is not a page"
      end

      for {path, text} <- pages, do: assert(String.starts_with?(text, Pages.marker()), path)
    end
  end

  describe "the pages of ValueRig" do
    setup do
      %{pages: pages(ValueRig.Domain)}
    end

    test "one per element: the domain, each value and context, the contract and each declaration",
         %{pages: pages} do
      assert Enum.sort(Map.keys(pages)) == [
               "index.md",
               "till/index.md",
               "till/till/aggregates/till.md",
               "till/till/commands/pay_in.md",
               "till/till/commands/short_change.md",
               "till/till/domain_services/splitting.md",
               "till/till/events/counted.md",
               "till/till/events/paid_in.md",
               "till/till/index.md",
               "till/till/queries/payments_above.md",
               "till/till/read_models/payments.md",
               "values/amount.md",
               "values/fee.md",
               "values/payment.md",
               "values/window.md"
             ]
    end

    test "a value shows its invariants with their examples, and who uses it", %{pages: pages} do
      amount = pages["values/amount.md"]

      assert amount =~ "# Value `amount`"
      assert amount =~ "### `positive`\n\nAn amount is more than nothing"
      assert amount =~ "Broken by: `0`, `-5`"
      assert amount =~ "Kept by: `1`, `250`"
      assert amount =~ "- value [`fee`](fee.md)"
      assert amount =~ "- command [`pay_in`](../till/till/commands/pay_in.md) of ValueRig.Till"

      assert pages["values/window.md"] =~ ~s|Broken by: `%{from: "2026-02-01", to: "2026-01-31"}`|
    end

    test "a command links its unit, its events and its fields' values", %{pages: pages} do
      pay_in = pages["till/till/commands/pay_in.md"]

      assert pay_in =~ "Aggregate [`till`](../aggregates/till.md)"
      assert pay_in =~ "Issued by: `cashier`."
      assert pay_in =~ "Emits: [`paid_in`](../events/paid_in.md)"
      assert pay_in =~ "| `fees` | list of [`fee`](../../../values/fee.md) |  | optional |"
    end

    test "an event says who emits it, who records it and who reads it", %{pages: pages} do
      assert pages["till/till/events/paid_in.md"] =~
               "Emitted by: [`pay_in`](../commands/pay_in.md), [`short_change`](../commands/short_change.md)"

      counted = pages["till/till/events/counted.md"]
      assert counted =~ "Recorded by: `counter`."
      assert counted =~ "- read model [`payments`](../read_models/payments.md)"
    end

    test "a domain service shows each rule with its examples as calls", %{pages: pages} do
      splitting = pages["till/till/domain_services/splitting.md"]

      assert splitting =~ "## `half` — Half of an amount, rounded down"
      assert splitting =~ "Returns [`amount`](../../../values/amount.md), or nothing"
      assert splitting =~ "- **`rounded_down`** — An odd amount loses its last grosz"
      assert splitting =~ "  - `half(5)` returns `2`"
      assert splitting =~ "  - `half(1)` returns `nil`"
    end

    test "the domain lists its contexts and values and prints its tree", %{pages: pages} do
      index = pages["index.md"]

      assert index =~ "- [`till`](till/index.md) — Till · core subdomain `core`"
      assert index =~ "- [`amount`](values/amount.md)"
      assert index =~ "```\ndomain value_rig  1 context · 1 contract"
    end
  end

  test "a process manager's reactions say what they issue and which timers they set" do
    chase = pages(DispatchRig.Domain)["ledger/ledger/process_managers/first_deposit_chase.md"]

    assert chase =~
             "- [`account_opened`](../events/account_opened.md) → sets timer `first_deposit_due`"

    assert chase =~
             "- [`deposited`](../events/deposited.md) → sets timer `review`, cancels timer `first_deposit_due`"

    assert chase =~ "- `first_deposit_due` → [`flag_account`](../commands/flag_account.md)"
  end

  test "two contracts of one context that would share a directory are refused" do
    till = EhOsContract.Model.fetch(ValueRig.Till)
    twin = %{till | module: Module.concat([Other, Till])}

    assert_raise ArgumentError,
                 ~r/ValueRig.Till and Other.Till would share the directory till\/till/,
                 fn ->
                   Pages.render(ValueRig.Domain, [till, twin])
                 end
  end

  describe "mix eh_os_contract.pages" do
    setup do
      Mix.shell(Mix.Shell.Process)
      on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    end

    defp run(args), do: Mix.Tasks.EhOsContract.Pages.run(args ++ ["--domain", "value_rig"])

    @tag :tmp_dir
    test "writes the pages, and --check says the directory is current", %{tmp_dir: dir} do
      run(["--output", dir])
      assert_received {:mix_shell, :info, [written]}
      assert written == "#{dir}: 15 pages written"

      assert File.read!(Path.join(dir, "values/amount.md")) ==
               pages(ValueRig.Domain)["values/amount.md"]

      run(["--output", dir, "--check"])
      assert_received {:mix_shell, :info, [current]}
      assert current == "#{dir}: current"
    end

    @tag :tmp_dir
    test "--check names a page that differs, one missing and one left over", %{tmp_dir: dir} do
      run(["--output", dir])
      File.write!(Path.join(dir, "values/amount.md"), "edited by hand")
      File.rm!(Path.join(dir, "values/fee.md"))

      File.write!(
        Path.join(dir, "values/tip.md"),
        Pages.marker() <> "\n\nA value since removed.\n"
      )

      error = assert_raise Mix.Error, fn -> run(["--output", dir, "--check"]) end

      assert error.message =~
               "#{dir} is not current; run `mix eh_os_contract.pages --output #{dir}`"

      assert error.message =~ "values/amount.md differs"
      assert error.message =~ "values/fee.md is missing"
      assert error.message =~ "values/tip.md is left over"
    end

    @tag :tmp_dir
    test "deletes a page it wrote and no longer has, and nothing else", %{tmp_dir: dir} do
      File.mkdir_p!(Path.join(dir, "values"))

      File.write!(
        Path.join(dir, "values/tip.md"),
        Pages.marker() <> "\n\nA value since removed.\n"
      )

      File.write!(Path.join(dir, "README.md"), "# Written by a person\n")

      run(["--output", dir])
      assert_received {:mix_shell, :info, [written]}
      assert written == "#{dir}: 15 pages written, 1 left over deleted"

      refute File.exists?(Path.join(dir, "values/tip.md"))
      assert File.read!(Path.join(dir, "README.md")) == "# Written by a person\n"
    end

    test "asks where the pages go" do
      assert_raise Mix.Error, ~r/--output <directory>/, fn -> run([]) end
    end
  end
end

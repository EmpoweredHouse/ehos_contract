defmodule EhosContract.GraphTaskTest do
  @moduledoc """
  `mix ehos_contract.graph`: a contract's or a domain's `graph.v1` document, or what
  the log says over it, as the bytes the API serves.
  """

  use EhosContract.DataCase, async: false

  alias EhosContract.Graph.Document

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
  end

  defp task(args) do
    Mix.Task.reenable("ehos_contract.graph")
    Mix.Tasks.EhosContract.Graph.run(args)
  end

  @tag :tmp_dir
  test "gives a contract's or a domain's document, and its overlay", %{tmp_dir: dir} do
    path = Path.join(dir, "graph.json")

    task(~w(--contract dispatch_rig.ledger --output #{path}))

    assert File.read!(path) ==
             Document.encode(Document.contract(DispatchRig.Ledger), pretty: true) <> "\n"

    task(~w(--domain dispatch_rig --output #{path}))
    assert Jason.decode!(File.read!(path))["domain"] == "DispatchRig.Domain"

    task(
      ~w(--contract dispatch_rig.ledger --overlay --since 2026-01-01T00:00:00Z --output #{path})
    )

    assert %{"schema" => "ehos_contract.graph_overlay.v1", "since" => "2026-01-01T00:00:00Z"} =
             Jason.decode!(File.read!(path))

    task(~w(--domain dispatch_rig --overlay --output #{path}))

    assert %{"schema" => "ehos_contract.graph_overlay.v1", "kind" => "domain"} =
             Jason.decode!(File.read!(path))
  end

  @tag :tmp_dir
  test "gives a process module's document and overlay, and its node in the domain's", %{
    tmp_dir: dir
  } do
    path = Path.join(dir, "graph.json")

    task(~w(--process dispatch_rig.account_review --output #{path}))

    assert File.read!(path) ==
             Document.encode(Document.process(DispatchRig.AccountReview), pretty: true) <> "\n"

    task(~w(--process dispatch_rig.account_review --overlay --output #{path}))

    assert %{
             "kind" => "process",
             "process" => "dispatch_rig.account_review",
             "nodes" => %{"process:dispatch_rig.account_review" => %{"runs" => 0}}
           } = Jason.decode!(File.read!(path))

    task(~w(--domain dispatch_rig --output #{path}))

    assert Enum.any?(
             Jason.decode!(File.read!(path))["nodes"]["process"],
             &(&1["name"] == "dispatch_rig.account_review")
           )
  end

  @tag :tmp_dir
  test "--output-dir writes every domain's, contract's and process module's document at once",
       %{tmp_dir: dir} do
    out = Path.join(dir, "graph")
    task(~w(--output-dir #{out}))

    one = Path.join(dir, "one.json")
    model = &EhosContract.Model.fetch/1

    # The file each document is in, and the options that write it alone.
    expected =
      Enum.map(
        EhosContract.Registry.domains(),
        &{"domain.#{inspect(&1)}.json", ["--domain", "#{model.(&1).name}"]}
      ) ++
        Enum.map(
          EhosContract.Registry.contracts(),
          &{"contract.#{model.(&1).id}.json", ["--contract", model.(&1).id]}
        ) ++
        Enum.map(
          EhosContract.Registry.processes(),
          &{"process.#{model.(&1).id}.json", ["--process", model.(&1).id]}
        )

    assert_received {:mix_shell, :info, ["written: " <> summary]}
    assert summary == "#{length(expected)} documents in #{out}"
    assert Enum.sort(File.ls!(out)) == Enum.sort(Enum.map(expected, &elem(&1, 0)))

    # Each file holds the bytes the task writes for that document alone.
    for {file, options} <- expected do
      task(options ++ ["--output", one])
      assert File.read!(Path.join(out, file)) == File.read!(one), file
    end

    assert "domain.DispatchRig.Domain.json" in File.ls!(out)
    assert "process.dispatch_rig.account_review.json" in File.ls!(out)
  end

  @tag :tmp_dir
  test "--output-dir refuses a directory that holds anything, and goes alone", %{tmp_dir: dir} do
    File.write!(Path.join(dir, "contract.removed.json"), "{}")

    assert_raise Mix.Error, ~r/holds files already/, fn -> task(~w(--output-dir #{dir})) end
    assert File.ls!(dir) == ["contract.removed.json"]

    for other <- [
          ~w(--contract dispatch_rig.ledger),
          ~w(--overlay),
          ~w(--since 2026-01-01T00:00:00Z),
          ~w(--output x.json)
        ] do
      assert_raise Mix.Error, ~r/pass it alone/, fn ->
        task(~w(--output-dir #{Path.join(dir, "new")}) ++ other)
      end
    end
  end

  test "refuses two documents at once, a period without the log, and what names nothing" do
    assert_raise Mix.Error, ~r/pass one of them/, fn ->
      task(~w(--contract dispatch_rig.ledger --domain dispatch_rig))
    end

    assert_raise Mix.Error, ~r/--since applies to --overlay/, fn ->
      task(~w(--contract dispatch_rig.ledger --since 2026-01-01T00:00:00Z))
    end

    assert_raise Mix.Error, ~r/pass one of them/, fn ->
      task(~w(--contract dispatch_rig.ledger --process dispatch_rig.account_review))
    end

    assert_raise Mix.Error, ~r/no contract nonesuch\. Registered: .*dispatch_rig\.ledger/, fn ->
      task(~w(--contract nonesuch))
    end

    # A process module is not a contract, and the other way round.
    assert_raise Mix.Error,
                 ~r/no process module dispatch_rig\.ledger\. Registered: .*dispatch_rig\.account_review/,
                 fn -> task(~w(--process dispatch_rig.ledger)) end

    assert_raise Mix.Error, ~r/no contract dispatch_rig\.account_review/, fn ->
      task(~w(--contract dispatch_rig.account_review))
    end

    assert_raise Mix.Error, ~r/no domain "nonesuch"; the domains are .*dispatch_rig/, fn ->
      task(~w(--domain nonesuch))
    end

    # The test registry holds several domains, so one has to be named.
    assert_raise Mix.Error, ~r/domains; name one with --domain/, fn -> task([]) end

    # The pictures the task drew are gone (plan E13b), and so are the flags that chose them.
    assert_raise OptionParser.ParseError, ~r/--lifecycle/, fn ->
      task(~w(--contract lifecycle_rig.visits --lifecycle visit))
    end
  end

  @tag :tmp_dir
  test "--since keeps the offset it is given, and reads a time without one as UTC", %{
    tmp_dir: dir
  } do
    path = Path.join(dir, "since.json")
    before = DateTime.utc_now()

    reception = EhosContract.Actor.credential("u-reception", ["lifecycle_rig.book_visit"])

    {:ok, _} =
      EhosContract.dispatch(
        LifecycleRig.Visits,
        %LifecycleRig.Visits.Commands.BookVisit{visit_id: "v-1"},
        actor: reception
      )

    # One hour after `before` on the clock of a zone two hours ahead: an hour before
    # it in UTC, so the booking is in the period. Read without its offset, it would
    # be an hour after, and the booking would not.
    digits =
      before |> DateTime.add(1, :hour) |> DateTime.to_naive() |> NaiveDateTime.to_iso8601()

    booked = fn since ->
      task(~w(--contract lifecycle_rig.visits --overlay --output #{path} --since #{since}))
      Jason.decode!(File.read!(path))["nodes"]["event:lifecycle_rig.visits:booked"]
    end

    assert booked.(digits <> "+02:00") == %{"occurrences" => 1}
    # The same digits without an offset are UTC: an hour after the booking.
    assert booked.(digits) == nil

    assert_raise Mix.Error, ~r/--since needs an ISO8601 time/, fn -> booked.("yesterday") end
  end

  test "without --output it writes the document alone to stdout, and what is logged to stderr" do
    require Logger

    # The document goes where a person running the task reads it: the shell's stdout.
    Mix.shell(Mix.Shell.IO)

    stdout =
      ExUnit.CaptureIO.capture_io(fn ->
        task(~w(--contract dispatch_rig.ledger --overlay))
      end)

    assert %{"schema" => "ehos_contract.graph_overlay.v1"} = Jason.decode!(stdout)

    # A host's application logs as it starts (a relay with no bus): during the task that
    # goes to stderr — also from the handler `app.start` adds when it restarts Logger,
    # which reads `:default_handler` — and both are back as they were after it.
    env = Application.fetch_env(:logger, :default_handler)

    stderr =
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        Mix.Tasks.EhosContract.Graph.logs_to_stderr(fn ->
          # What `app.start` does to Logger before it starts the host's applications.
          :ok = Application.stop(:logger)
          :ok = Application.start(:logger)
          assert {:ok, %{config: %{type: :standard_error}}} = :logger.get_handler_config(:default)

          Logger.warning("no bus is configured")
        end)
      end)

    assert stderr =~ "no bus is configured"
    assert {:ok, %{config: %{type: :standard_io}}} = :logger.get_handler_config(:default)
    assert Application.fetch_env(:logger, :default_handler) == env
  end
end

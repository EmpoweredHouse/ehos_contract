defmodule EhOsContract.Auth.ManifestTest do
  @moduledoc """
  EH3: an application's `ehos.yaml` extended with what its contracts offer, into
  EHOS's `ehos.manifest/v2` (`eh-os` D-52), without fields the receiver would reject.

  `test/fixtures/manifests/ledger.v2.json` is EHOS's hand-written manifest of
  `ehos-ledger`, unchanged: `eh-os` `test/support/fixtures/manifests/ledger.v2.json`,
  last changed in `ff1388e`, read at `f7b2330`. EHOS deploys ledger with it (step 6c)
  until this generator writes it.
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias EhOsContract.Auth.{EhosYaml, Manifest}

  @fixtures Path.expand("fixtures", __DIR__)

  defmodule Domain do
    @moduledoc false
    use EhOsContract.Domain, name: :"manifest-rig", language: :en

    subdomain(:core, "Core", type: :core)
    context(:work, "Work", subdomain: :core)

    actor(:clerk, :human, "Clerk", scope: [:branch_id])
    actor(:observer, :human, "Observer")
    actor(:scheduler, :system, "Scheduler")
  end

  defmodule DuplicateDomain do
    @moduledoc false
    use EhOsContract.Domain, name: :"manifest-rig", language: :en

    subdomain(:other, "Other", type: :supporting)
    context(:other, "Other", subdomain: :other)
  end

  defmodule Work do
    @moduledoc false
    use EhOsContract.Contract, domain: Domain, context: :work

    aggregate :job, "Job" do
      identity(:job_id)

      command :start_job, "Start a job",
        by: [:clerk, :scheduler],
        scope: :branch_id,
        emits: :job_started do
        field(:branch_id, :id)
      end

      command(:finish_job, "Finish a job", emits: :job_finished)

      event :job_started, "Job started" do
        field(:branch_id, :id)
      end

      event(:job_finished, "Job finished", terminal: true)
      event(:job_noted, "Job noted", recorded_by: :clerk)
    end

    read_model :jobs, "Jobs", projects: :job_started do
      field(:job_id, :id)
      field(:branch_id, :id)
    end

    query :jobs_in_branch, "Jobs in a branch",
      reads: :jobs,
      by: :clerk,
      scope: :branch_id do
      param(:branch_id, :id)
    end

    policy(:finish_started, "Finish a started job", handles: :job_started, issues: :finish_job)

    process :work, "Work" do
      correlate(:job_id)
    end
  end

  # A domain whose name the engine takes (D11) and EHOS does not.
  defmodule SnakeDomain do
    @moduledoc false
    use EhOsContract.Domain, name: :manifest_rig, language: :en

    subdomain(:core, "Core", type: :core)
    context(:work, "Work", subdomain: :core)
    actor(:clerk, :human, "Clerk")
  end

  defmodule SnakeWork do
    @moduledoc false
    use EhOsContract.Contract, domain: SnakeDomain, context: :work

    aggregate :job, "Job" do
      identity(:job_id)
      command(:start_job, "Start a job", by: :clerk, emits: :job_started)
      event(:job_started, "Job started", terminal: true)
    end

    process :work, "Work" do
      correlate(:job_id)
    end
  end

  # Made up in the shape of `ehos-ledger`'s offers: a clerk records an entry, an auditor flags one.
  defmodule Ledger do
    @moduledoc false
    use EhOsContract.Domain, name: :ledger, language: :en

    subdomain(:books, "Books", type: :core)
    context(:entries, "Entries", subdomain: :books)

    actor(:clerk, :human, "Clerk")
    actor(:auditor, :human, "Auditor")
  end

  defmodule Entries do
    @moduledoc false
    use EhOsContract.Contract, domain: Ledger, context: :entries

    aggregate :entry, "Entry" do
      identity(:entry_id)
      command(:record_entry, "Record an entry", by: :clerk, emits: :recorded)
      command(:flag_entry, "Flag an entry", by: :auditor, emits: :flagged)
      event(:recorded, "Entry recorded")
      event(:flagged, "Entry flagged", terminal: true)
    end

    process :entries, "Entries" do
      correlate(:entry_id)
    end
  end

  @health %{"port" => 4001, "ready" => "/health/ready", "live" => "/health/live"}
  @file_v1 %{"schema" => "ehos.yaml/v1", "health" => @health}
  @engine %{"name" => "eh_os_contract", "version" => EhOsContract.version()}

  defp ehos_yaml!(path) do
    {:ok, file} = EhosYaml.read(File.read!(Path.join(@fixtures, path)))
    file
  end

  describe "ledger" do
    test "its ehos.yaml and offers give EHOS's own ledger.v2.json, with the engine beside" do
      expected =
        @fixtures |> Path.join("manifests/ledger.v2.json") |> File.read!() |> Jason.decode!()

      manifest = Manifest.build(ehos_yaml!("ehos_yaml/accepted/ledger.yaml"), [Ledger], [Entries])

      assert manifest == Map.put(expected, "engine", @engine)
    end

    test "a change of serves alone moves neither offers nor application" do
      file = ehos_yaml!("ehos_yaml/accepted/ledger.yaml")
      moved = %{file | "serves" => [%{"name" => "web", "port" => 4400}]}

      before = Manifest.build(file, [Ledger], [Entries])
      later = Manifest.build(moved, [Ledger], [Entries])

      assert later["serves"] == [%{"name" => "web", "port" => 4400}]
      assert Map.drop(later, ["serves"]) == Map.drop(before, ["serves"])
    end
  end

  test "offers exactly the human command capabilities and the roles that hold them" do
    assert Manifest.build(@file_v1, [Domain], [Work]) == %{
             "schema" => "ehos.manifest/v2",
             "ehos_yaml" => "ehos.yaml/v1",
             "application" => "manifest-rig",
             "engine" => @engine,
             "health" => @health,
             "offers" => %{
               "capabilities" => [
                 %{
                   "name" => "manifest-rig.start_job",
                   "command" => "start_job",
                   "label" => "Start a job",
                   "process" => "work",
                   "principals" => ["human"]
                 }
               ],
               "roles" => [
                 %{
                   "name" => "manifest-rig.clerk",
                   "label" => "Clerk",
                   "capabilities" => ["manifest-rig.start_job"]
                 }
               ]
             }
           }
  end

  test "invents no fields for queries, recordings, scope or system actors, nor contracts" do
    document = Manifest.build(@file_v1, [Domain], [Work])
    encoded = Jason.encode!(document)

    refute encoded =~ "jobs_in_branch"
    refute encoded =~ "job_noted"
    refute encoded =~ "branch_id"
    refute encoded =~ "scheduler"
    refute encoded =~ "observer"
    refute Map.has_key?(document, "contracts")
  end

  describe "the application" do
    test "is the only domain's name, among the contracts of every domain" do
      assert %{"application" => "ledger"} =
               Manifest.build(@file_v1, [Ledger], [Work, Entries])
    end

    test "is the domain ehos.yaml names, when there are several" do
      file = Map.put(@file_v1, "application", "ledger")

      assert %{"application" => "ledger", "offers" => %{"roles" => roles}} =
               Manifest.build(file, [Domain, Ledger], [Work, Entries])

      assert Enum.map(roles, & &1["name"]) == ["ledger.auditor", "ledger.clerk"]
    end

    test "must be named in ehos.yaml when there are several domains" do
      assert_raise ArgumentError,
                   ~r/2 domains; say which one this image is in ehos.yaml, as application: <name>.*ledger \(.*Ledger\), manifest-rig/,
                   fn -> Manifest.build(@file_v1, [Domain, Ledger], [Work, Entries]) end
    end

    test "must be the name of a registered domain" do
      file = Map.put(@file_v1, "application", "billing")

      assert_raise ArgumentError,
                   ~r/names application: billing, and no registered domain has that name:/,
                   fn -> Manifest.build(file, [Domain, Ledger], [Work, Entries]) end
    end

    test "must name one domain, not two of one name" do
      file = Map.put(@file_v1, "application", "manifest-rig")

      assert_raise ArgumentError,
                   ~r/domain "manifest-rig" is ambiguous.*Domain.*DuplicateDomain/s,
                   fn -> Manifest.build(file, [Domain, DuplicateDomain], [Work]) end
    end

    test "is refused when the domain's name is not one EHOS takes, with the name to use" do
      assert_raise ArgumentError,
                   ~r/name: :manifest_rig is not a name EHOS takes for an application.*name: :"manifest-rig"/s,
                   fn -> Manifest.build(@file_v1, [SnakeDomain], [SnakeWork]) end
    end
  end

  test "refuses a domain with no contracts instead of writing a manifest that offers nothing" do
    assert_raise ArgumentError, ~r/has no contracts/, fn ->
      Manifest.build(@file_v1, [Ledger], [Work])
    end
  end

  test "refuses an ehos.yaml that holds a key the generator writes, rather than overwrite it" do
    file = Map.put(@file_v1, "offers", %{})

    assert_raise ArgumentError, ~r/ehos.yaml holds offers, which the generator writes/, fn ->
      Manifest.build(file, [Ledger], [Entries])
    end
  end

  describe "every valid ehos.yaml" do
    property "comes through unchanged: every key but schema at its path, nothing added" do
      check all(file <- ehos_yaml()) do
        # Written as JSON, which is YAML 1.2, so the file goes through the reader as well.
        assert EhosYaml.read(Jason.encode!(file)) == {:ok, file}

        manifest = Manifest.build(file, [Ledger], [Entries])

        assert manifest["ehos_yaml"] == file["schema"]

        assert Map.drop(manifest, ~w(schema ehos_yaml application offers engine)) ==
                 Map.drop(file, ~w(schema application))

        if Map.has_key?(file, "application"),
          do: assert(manifest["application"] == file["application"])
      end
    end
  end

  # Valid ehos.yaml/v1 files, from its schema: each optional key present or absent, and no
  # default ever written.
  defp ehos_yaml do
    gen all(
          needs <- optional(needs()),
          serves <- optional(list_of(serve(), max_length: 4)),
          application <- optional(constant("ledger")),
          health <- health()
        ) do
      %{"schema" => "ehos.yaml/v1", "health" => health}
      |> put_present("needs", needs)
      |> put_present("serves", serves)
      |> put_present("application", application)
    end
  end

  defp needs do
    gen all(database <- optional(database())) do
      put_present(%{}, "database", database)
    end
  end

  defp database do
    gen all(
          version <- optional(member_of(["16", ">= 16", ">=17", "9"])),
          migrate <- optional(list_of(command_word(), min_length: 1, max_length: 3))
        ) do
      %{"engine" => "postgres"}
      |> put_present("version", version)
      |> put_present("migrate", migrate)
    end
  end

  defp serve do
    gen all(
          name <- member_of(["web", "api", "admin-2", "m"]),
          port <- integer(1024..65_535),
          public <- optional(boolean())
        ) do
      put_present(%{"name" => name, "port" => port}, "public", public)
    end
  end

  defp health do
    gen all(
          port <- integer(1024..65_535),
          ready <- path(),
          live <- path()
        ) do
      %{"port" => port, "ready" => ready, "live" => live}
    end
  end

  defp path do
    gen all(segment <- string(Enum.concat([?a..?z, ?0..?9, [?-, ?_, ?.]]), max_length: 20)) do
      "/" <> segment
    end
  end

  defp command_word, do: string(:printable, min_length: 1, max_length: 30)

  defp optional(generator), do: one_of([constant(:absent), generator])

  defp put_present(map, _key, :absent), do: map
  defp put_present(map, key, value), do: Map.put(map, key, value)
end

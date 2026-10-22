defmodule EhOsContract.Auth.ManifestTest do
  @moduledoc """
  EH3: an application's `ehos.yaml` extended with what its contracts offer, into
  EHOS's `ehos.manifest/v2`, without fields the receiver would reject.

  `test/fixtures/manifests/ledger.v2.json` is EHOS's hand-written manifest of a real application,
  a ledger, unchanged: a fixture of EHOS's own tests, as it stood on 1 October 2026. EHOS deploys
  the ledger with it until this generator writes it. Its capabilities name the process the
  ledger's contract declared; a contract declares none since plan DD, P2h (#221), so the test
  reads that copy without them, a field EHOS keeps optional.

  `test/fixtures/manifests/ledger_sign_in.v2.json` is the same ledger written by hand
  from `ehos_yaml/accepted/sign_in.yaml`, an `ehos.yaml/v2` that signs people in
  (issue #83).

  `test/fixtures/manifests/ledger_people.v3.json` is that ledger written by hand from
  `ehos_yaml/accepted/people.yaml`, an `ehos.yaml/v3` that reads the company's people
  (issue #252).

  `test/fixtures/manifests/ledger_secrets.v4.json` is that ledger written by hand from
  `ehos_yaml/accepted/secrets.yaml`, an `ehos.yaml/v4` that seeds its database and is given
  secrets (issue #306).

  `test/fixtures/manifests/ledger_egress.v6.json` is that ledger written by hand from
  `ehos_yaml/accepted/egress.yaml`, an `ehos.yaml/v5` that reaches two hosts outside the
  installation (issue #408).
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias EhOsContract.Auth.{EhosYaml, Manifest}
  alias EhOsContract.Model

  doctest EhOsContract.Auth.Manifest, only: [schemas: 0]

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
    use EhOsContract.Contract, domain: Domain, context: :work, id: "manifest-rig.work"

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

      event(:job_finished, "Job finished")
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
  end

  defmodule ReadDomain do
    @moduledoc false
    use EhOsContract.Domain, name: :"read-rig", language: :en

    subdomain(:core, "Core", type: :core)
    context(:work, "Work", subdomain: :core)
    actor(:reader, :human, "Reader")
    actor(:feeder, :system, "Feeder")
  end

  defmodule ReadWork do
    @moduledoc false
    use EhOsContract.Contract, domain: ReadDomain, context: :work, id: "read-rig.read_work"

    aggregate :job, "Job" do
      identity(:job_id)
      command(:open_job, "Open a job", by: :feeder, emits: :job_opened)
      event(:job_opened, "Job opened")
    end

    read_model :jobs, "Jobs", projects: :job_opened do
      field(:job_id, :id)
    end

    query(:open_jobs, "Open jobs", reads: :jobs, by: :reader)
  end

  # A grant rule: an office employee may grant a client; a visitor holds nothing, so is no role.
  defmodule GrantDomain do
    @moduledoc false
    use EhOsContract.Domain, name: :"grant-rig", language: :en

    subdomain(:core, "Core", type: :core)
    context(:work, "Work", subdomain: :core)
    actor(:office_employee, :human, "Office employee", may_grant: [:client])
    actor(:client, :human, "Client")
    actor(:visitor, :human, "Visitor")
  end

  defmodule GrantWork do
    @moduledoc false
    use EhOsContract.Contract, domain: GrantDomain, context: :work, id: "grant-rig.grant_work"

    aggregate :case, "Case" do
      identity(:case_id)
      command(:open_case, "Open a case", by: :office_employee, emits: :case_opened)
      command(:comment_case, "Comment on a case", by: :client, emits: :case_commented)
      event(:case_opened, "Case opened")
      event(:case_commented, "Case commented")
    end
  end

  defmodule RoleLessGrantDomain do
    @moduledoc false
    use EhOsContract.Domain, name: :"grant-rig", language: :en

    subdomain(:core, "Core", type: :core)
    context(:work, "Work", subdomain: :core)
    actor(:office_employee, :human, "Office employee", may_grant: [:client, :visitor])
    actor(:client, :human, "Client")
    actor(:visitor, :human, "Visitor")
  end

  defmodule RoleLessGrantWork do
    @moduledoc false
    use EhOsContract.Contract,
      domain: RoleLessGrantDomain,
      context: :work,
      id: "grant-rig.role_less_grant_work"

    aggregate :case, "Case" do
      identity(:case_id)
      command(:open_case, "Open a case", by: :office_employee, emits: :case_opened)
      command(:comment_case, "Comment on a case", by: :client, emits: :case_commented)
      event(:case_opened, "Case opened")
      event(:case_commented, "Case commented")
    end
  end

  defmodule MachineDomain do
    @moduledoc false
    use EhOsContract.Domain, name: :"machine-rig", language: :en

    subdomain(:core, "Core", type: :core)
    context(:work, "Work", subdomain: :core)
    actor(:feeder, :system, "Feeder")
  end

  defmodule MachineWork do
    @moduledoc false
    use EhOsContract.Contract,
      domain: MachineDomain,
      context: :work,
      id: "machine-rig.machine_work"

    aggregate :job, "Job" do
      identity(:job_id)
      command(:open_job, "Open a job", by: :feeder, emits: :job_opened)
      event(:job_opened, "Job opened")
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
    use EhOsContract.Contract, domain: SnakeDomain, context: :work, id: "manifest_rig.snake_work"

    aggregate :job, "Job" do
      identity(:job_id)
      command(:start_job, "Start a job", by: :clerk, emits: :job_started)
      event(:job_started, "Job started")
    end
  end

  defmodule TrailingDomain do
    @moduledoc false
    use EhOsContract.Domain, name: :shop_, language: :en

    subdomain(:core, "Core", type: :core)
    context(:work, "Work", subdomain: :core)
    actor(:clerk, :human, "Clerk")
  end

  defmodule TrailingWork do
    @moduledoc false
    use EhOsContract.Contract, domain: TrailingDomain, context: :work, id: "shop_.trailing_work"

    aggregate :job, "Job" do
      identity(:job_id)
      command(:start_job, "Start a job", by: :clerk, emits: :job_started)
      event(:job_started, "Job started")
    end
  end

  # Names the engine takes and EHOS does not, past 63 characters. An empty label the
  # engine refuses too (N1, D1), so the test blanks two in the models it hands over.
  defmodule LongDomain do
    @moduledoc false
    use EhOsContract.Domain, name: :"long-rig", language: :en

    subdomain(:core, "Core", type: :core)
    context(:work, "Work", subdomain: :core)
    actor(:clerk_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa, :human, "Clerk")
    actor(:auditor, :human, "Auditor")
  end

  defmodule LongWork do
    @moduledoc false
    use EhOsContract.Contract, domain: LongDomain, context: :work, id: "long-rig.long_work"

    aggregate :job, "Job" do
      identity(:job_id)

      command(:record_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb, "Record",
        by: :clerk_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa,
        emits: :job_started
      )

      command(:flag_job, "Flag a job", by: :auditor, emits: :job_flagged)
      event(:job_started, "Job started")
      event(:job_flagged, "Job flagged")
    end
  end

  # Made up in the shape of the ledger's offers: a clerk records an entry, an auditor flags one.
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
    use EhOsContract.Contract, domain: Ledger, context: :entries, id: "ledger.entries"

    aggregate :entry, "Entry" do
      identity(:entry_id)
      command(:record_entry, "Record an entry", by: :clerk, emits: :recorded)
      command(:flag_entry, "Flag an entry", by: :auditor, emits: :flagged)
      event(:recorded, "Entry recorded")
      event(:flagged, "Entry flagged")
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
        @fixtures
        |> Path.join("manifests/ledger.v2.json")
        |> File.read!()
        |> Jason.decode!()
        |> update_in(["offers", "capabilities"], fn capabilities ->
          Enum.map(capabilities, &Map.delete(&1, "process"))
        end)

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

  describe "sign_in, from ehos.yaml/v2" do
    test "is carried as written, beside the rest, into the manifest written by hand" do
      expected =
        @fixtures
        |> Path.join("manifests/ledger_sign_in.v2.json")
        |> File.read!()
        |> Jason.decode!()

      manifest =
        Manifest.build(ehos_yaml!("ehos_yaml/accepted/sign_in.yaml"), [Ledger], [Entries])

      assert manifest == Map.put(expected, "engine", @engine)
    end

    # `{}` asks for the application's own sign-in only, and EHOS reads its presence.
    test "is kept when empty" do
      file = %{"schema" => "ehos.yaml/v2", "health" => @health, "sign_in" => %{}}

      manifest = Manifest.build(file, [Ledger], [Entries])
      assert manifest["ehos_yaml"] == "ehos.yaml/v2"
      assert manifest["sign_in"] == %{}
    end

    # `ehos.yaml` seldom names its application, so the reader cannot see this; EHOS refuses the
    # manifest for it at deploy (`Ehos.Applications.Manifest.V2`).
    test "never names the application the manifest is of" do
      file = %{
        "schema" => "ehos.yaml/v2",
        "health" => @health,
        "sign_in" => %{"applications" => ["pages", "ledger"]}
      }

      assert_raise ArgumentError,
                   ~r/sign_in\.applications names ledger, the application this manifest is of/,
                   fn -> Manifest.build(file, [Ledger], [Entries]) end
    end
  end

  describe "needs.people, from ehos.yaml/v3" do
    test "makes an ehos.manifest/v3, carried as written, as the one written by hand" do
      expected =
        @fixtures
        |> Path.join("manifests/ledger_people.v3.json")
        |> File.read!()
        |> Jason.decode!()

      manifest =
        Manifest.build(ehos_yaml!("ehos_yaml/accepted/people.yaml"), [Ledger], [Entries])

      assert manifest == Map.put(expected, "engine", @engine)
    end

    # A manifest keeps the meaning EHOS accepted it with: v2 never reads needs.people.
    test "is the only thing that makes a v3: a v1 or v2 file still makes a v2" do
      for version <- ["ehos.yaml/v1", "ehos.yaml/v2"] do
        manifest =
          Manifest.build(%{"schema" => version, "health" => @health}, [Ledger], [Entries])

        assert manifest["schema"] == "ehos.manifest/v2"
      end

      file = %{"schema" => "ehos.yaml/v3", "health" => @health}
      assert Manifest.build(file, [Ledger], [Entries])["schema"] == "ehos.manifest/v3"
    end
  end

  describe "needs.database.seed and needs.secrets, from ehos.yaml/v4" do
    test "makes an ehos.manifest/v4, carried as written, as the one written by hand" do
      expected =
        @fixtures
        |> Path.join("manifests/ledger_secrets.v4.json")
        |> File.read!()
        |> Jason.decode!()

      manifest =
        Manifest.build(ehos_yaml!("ehos_yaml/accepted/secrets.yaml"), [Ledger], [Entries])

      assert manifest == Map.put(expected, "engine", @engine)
    end

    # EHOS refuses a v2 or v3 that names an ehos.yaml/v4: neither ever read a seed or a secret.
    test "is the only thing that makes a v4" do
      file = %{"schema" => "ehos.yaml/v4", "health" => @health}
      assert Manifest.build(file, [Ledger], [Entries])["schema"] == "ehos.manifest/v4"

      file = %{"schema" => "ehos.yaml/v3", "health" => @health}
      assert Manifest.build(file, [Ledger], [Entries])["schema"] == "ehos.manifest/v3"
    end
  end

  describe "needs.egress, from ehos.yaml/v5" do
    test "makes an ehos.manifest/v6, carried as written, as the one written by hand" do
      expected =
        @fixtures
        |> Path.join("manifests/ledger_egress.v6.json")
        |> File.read!()
        |> Jason.decode!()

      manifest =
        Manifest.build(ehos_yaml!("ehos_yaml/accepted/egress.yaml"), [Ledger], [Entries])

      assert manifest == Map.put(expected, "engine", @engine)
    end

    # EHOS refuses a v2 to v5 that names an ehos.yaml/v5: none ever read a host.
    test "is the only thing that makes a v6, and makes one whether or not a role may grant" do
      file = %{"schema" => "ehos.yaml/v5", "health" => @health}
      assert Manifest.build(file, [Ledger], [Entries])["schema"] == "ehos.manifest/v6"
      assert Manifest.build(file, [GrantDomain], [GrantWork])["schema"] == "ehos.manifest/v6"

      file = %{"schema" => "ehos.yaml/v4", "health" => @health}
      assert Manifest.build(file, [Ledger], [Entries])["schema"] == "ehos.manifest/v4"
    end
  end

  describe "a role that may grant another" do
    test "makes an ehos.manifest/v5 whose role carries the roles its actor may grant" do
      manifest = Manifest.build(@file_v1, [GrantDomain], [GrantWork])

      assert manifest["schema"] == "ehos.manifest/v5"
      assert manifest["ehos_yaml"] == "ehos.yaml/v1"

      assert manifest["offers"]["roles"] == [
               %{
                 "name" => "grant-rig.client",
                 "label" => "Client",
                 "capabilities" => ["grant-rig.comment_case"]
               },
               %{
                 "name" => "grant-rig.office_employee",
                 "label" => "Office employee",
                 "capabilities" => ["grant-rig.open_case"],
                 "may_grant" => ["grant-rig.client"]
               }
             ]
    end

    # EHOS's v5 takes every ehos.yaml v4 does; an ehos.yaml/v5 makes a v6, which takes a rule too.
    test "is v5 whatever the version of ehos.yaml before v5" do
      for version <- EhosYaml.versions() -- ["ehos.yaml/v5"] do
        file = %{"schema" => version, "health" => @health}

        assert Manifest.build(file, [GrantDomain], [GrantWork])["schema"] == "ehos.manifest/v5",
               version
      end
    end

    test "is refused when it names an actor that holds no capability, and so is no role" do
      assert_raise ArgumentError,
                   ~r/actor :office_employee's may_grant names :visitor, which holds no capability and so is no role/,
                   fn ->
                     Manifest.build(@file_v1, [RoleLessGrantDomain], [RoleLessGrantWork])
                   end
    end

    # A domain given as a map has not been through D4: what EHOS refuses, the generator refuses.
    test "a domain given as a map is held to what EHOS takes" do
      with_rule = fn actor, rule ->
        domain = Model.fetch(GrantDomain)

        actors =
          Enum.map(domain.actors, fn
            %{name: ^actor} = a -> Map.put(a, :may_grant, rule)
            a -> a
          end)

        fn -> Manifest.build(@file_v1, [%{domain | actors: actors}], [GrantWork]) end
      end

      for {actor, rule, reason} <- [
            {:office_employee, [:office_employee], "names the actor itself"},
            {:office_employee, [:client, :client], "names :client twice"},
            {:office_employee, [:robot, :"ehos.admin"],
             ~s|names :robot, :"ehos.admin", no person actor of this domain|},
            {:office_employee, nil, "is nil, not a list of person actors"},
            {:visitor, [:client], "actor :visitor has may_grant but holds no capability"}
          ] do
        error = assert_raise ArgumentError, with_rule.(actor, rule)
        assert error.message =~ reason, inspect(rule)
      end
    end

    test "a domain given as a map has no system with a rule, nor rules that lead back" do
      domain = Model.fetch(GrantDomain)

      rule = fn rules ->
        actors = Enum.map(domain.actors, &Map.put(&1, :may_grant, Map.get(rules, &1.name, [])))
        fn -> Manifest.build(@file_v1, [%{domain | actors: actors}], [GrantWork]) end
      end

      system = %{name: :sync, kind: :system, label: "Sync", may_grant: [:client]}

      error =
        assert_raise ArgumentError, fn ->
          Manifest.build(@file_v1, [%{domain | actors: domain.actors ++ [system]}], [GrantWork])
        end

      assert error.message =~ "actor :sync is a system and cannot have may_grant"

      error =
        assert_raise ArgumentError,
                     rule.(%{office_employee: [:client], client: [:office_employee]})

      assert error.message =~
               "actor :client, :office_employee have may_grant rules that lead back to them"
    end
  end

  # schemas/0 is what a release says the package produces: exactly what build/3 writes from
  # every ehos.yaml it can read, no more, with a rule and without.
  test "schemas/0 lists exactly the versions build/3 writes" do
    written =
      for version <- EhosYaml.versions(),
          {domain, contract} <- [{Ledger, Entries}, {GrantDomain, GrantWork}],
          uniq: true do
        file = %{"schema" => version, "health" => @health}
        Manifest.build(file, [domain], [contract])["schema"]
      end

    # Oldest first, by the number: as text, "ehos.manifest/v10" would sort before "/v2".
    assert Enum.sort_by(written, &schema_number/1) == Manifest.schemas()
  end

  defp schema_number("ehos.manifest/v" <> number), do: String.to_integer(number)

  test "offers the commands, queries and recordings a human holds, and the roles that hold them" do
    assert Manifest.build(@file_v1, [Domain], [Work]) == %{
             "schema" => "ehos.manifest/v2",
             "ehos_yaml" => "ehos.yaml/v1",
             "application" => "manifest-rig",
             "engine" => @engine,
             "health" => @health,
             "offers" => %{
               "capabilities" => [
                 %{
                   "name" => "manifest-rig.job_noted",
                   "record" => "job_noted",
                   "label" => "Job noted",
                   "principals" => ["human"]
                 },
                 %{
                   "name" => "manifest-rig.jobs_in_branch",
                   "query" => "jobs_in_branch",
                   "label" => "Jobs in a branch",
                   "principals" => ["human"]
                 },
                 %{
                   "name" => "manifest-rig.start_job",
                   "command" => "start_job",
                   "label" => "Start a job",
                   "principals" => ["human"]
                 }
               ],
               "roles" => [
                 %{
                   "name" => "manifest-rig.clerk",
                   "label" => "Clerk",
                   "capabilities" => [
                     "manifest-rig.job_noted",
                     "manifest-rig.jobs_in_branch",
                     "manifest-rig.start_job"
                   ]
                 }
               ]
             }
           }
  end

  # Plan DD, P2h (#221): a contract declares no process, so no capability names one;
  # EHOS keeps the field optional and reads it nowhere. `Work` offers a
  # command, a query and a recording.
  test "a capability names no process" do
    %{"offers" => %{"capabilities" => capabilities}} =
      Manifest.build(@file_v1, [Domain], [Work])

    assert capabilities != []
    refute Enum.any?(capabilities, &Map.has_key?(&1, "process"))
  end

  test "accepts a domain whose people only read, and refuses one where no human holds anything" do
    readers = Manifest.build(@file_v1, [ReadDomain], [ReadWork])

    assert [%{"name" => "read-rig.open_jobs", "query" => "open_jobs"}] =
             readers["offers"]["capabilities"]

    assert_raise ArgumentError, ~r/has no capabilities a human holds/, fn ->
      Manifest.build(@file_v1, [MachineDomain], [MachineWork])
    end
  end

  test "invents no fields for scope, publications or system actors, nor contracts" do
    document = Manifest.build(@file_v1, [Domain], [Work])
    encoded = Jason.encode!(document)

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
                   ~r/2 domains with contracts; say which one this image is in ehos.yaml, as application: <name>.*ledger \(.*Ledger\), manifest-rig/,
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
                   ~r/domain "manifest-rig" is ambiguous.*Domain.*DuplicateDomain.*give one of them another name:/s,
                   fn -> Manifest.build(file, [Domain, DuplicateDomain], [Work]) end
    end

    test "suggests no name that EHOS would refuse too" do
      error =
        assert_raise ArgumentError, fn ->
          Manifest.build(@file_v1, [TrailingDomain], [TrailingWork])
        end

      assert error.message =~ ~s(Rename the domain, such as name: :"shop")
      refute error.message =~ ~s(:"shop-")
    end

    test "counts only domains with contracts" do
      assert %{"application" => "ledger"} =
               Manifest.build(@file_v1, [Domain, Ledger], [Entries])
    end

    test "named in ehos.yaml as EHOS spells it, finds the domain named with _, and says to rename it" do
      file = Map.put(@file_v1, "application", "manifest-rig")

      assert_raise ArgumentError, ~r/name: :manifest_rig is not a name EHOS takes/, fn ->
        Manifest.build(file, [SnakeDomain, Ledger], [SnakeWork, Entries])
      end
    end

    test "is refused when the domain's name is not one EHOS takes, with the name to use" do
      assert_raise ArgumentError,
                   ~r/name: :manifest_rig is not a name EHOS takes for an application.*name: :"manifest-rig"/s,
                   fn -> Manifest.build(@file_v1, [SnakeDomain], [SnakeWork]) end
    end
  end

  describe "names and labels EHOS refuses" do
    test "are refused here, each named, rather than at deploy" do
      # A model handed over as a map, not compiled from the DSL, can still carry one.
      blank = fn declarations, name ->
        Enum.map(declarations, &if(&1.name == name, do: %{&1 | label: " "}, else: &1))
      end

      domain = Map.update!(Model.fetch(LongDomain), :actors, &blank.(&1, :auditor))
      work = Map.update!(Model.fetch(LongWork), :commands, &blank.(&1, :flag_job))

      error = assert_raise ArgumentError, fn -> Manifest.build(@file_v1, [domain], [work]) end

      assert error.message =~ "EHOS would refuse what the contracts offer"

      assert error.message =~
               "command :record_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb is 64 characters; EHOS takes at most 63"

      assert error.message =~
               "actor :clerk_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa is 64 characters; EHOS takes at most 63"

      assert error.message =~ "command :flag_job has an empty label"
      assert error.message =~ "actor :auditor has an empty label"
    end
  end

  test "refuses a domain with no contracts instead of writing a manifest that offers nothing" do
    assert_raise ArgumentError, ~r/no registered domain has contracts/, fn ->
      Manifest.build(@file_v1, [Ledger], [Work])
    end

    assert_raise ArgumentError, ~r/Ledger has no contracts/, fn ->
      Manifest.build(Map.put(@file_v1, "application", "ledger"), [Domain, Ledger], [Work])
    end
  end

  test "refuses a map that is not a read ehos.yaml, as an argument error" do
    assert_raise ArgumentError, ~r/EhOsContract.Auth.EhosYaml.read\/1/, fn ->
      Manifest.build(%{"health" => @health}, [Ledger], [Entries])
    end
  end

  test "refuses an ehos.yaml that holds a key the generator writes, rather than overwrite it" do
    file = Map.put(@file_v1, "offers", %{})

    assert_raise ArgumentError, ~r/ehos.yaml holds offers, which the generator writes/, fn ->
      Manifest.build(file, [Ledger], [Entries])
    end
  end

  describe "every ehos.yaml its schema accepts" do
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

  # ehos.yaml/v1 files its schema accepts: each optional key present or absent, and no default
  # ever written. Not all are files EHOS accepts: it refuses repeated names and ports beside the
  # schema, and the generator carries them as they are.
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

  # The schema's paths: a slash, then printable ASCII without spaces.
  defp path do
    gen all(segment <- string(?!..?~, max_length: 60)) do
      "/" <> segment
    end
  end

  defp command_word, do: string(:printable, min_length: 1, max_length: 30)

  defp optional(generator), do: one_of([constant(:absent), generator])

  defp put_present(map, _key, :absent), do: map
  defp put_present(map, key, value), do: Map.put(map, key, value)
end

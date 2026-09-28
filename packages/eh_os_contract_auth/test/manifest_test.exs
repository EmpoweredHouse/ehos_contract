defmodule EhOsContract.Auth.ManifestTest do
  @moduledoc """
  E10: the contract's command authority projected onto EHOS's strict manifest v1,
  without private fields the receiver would reject.
  """

  use ExUnit.Case, async: true

  alias EhOsContract.Auth.Manifest

  defmodule Domain do
    @moduledoc false
    use EhOsContract.Domain, name: :manifest_rig, language: :en

    subdomain(:core, "Core", type: :core)
    context(:work, "Work", subdomain: :core)

    actor(:clerk, :human, "Clerk", scope: [:branch_id])
    actor(:observer, :human, "Observer")
    actor(:scheduler, :system, "Scheduler")
  end

  defmodule Work do
    @moduledoc false
    use EhOsContract.Next.Contract, domain: Domain, context: :work

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

  test "contains exactly the v1 schema's command capabilities and roles" do
    assert Manifest.build(Domain, [Work]) == %{
             "schema" => "ehos.manifest/v1",
             "application" => "manifest_rig",
             "capabilities" => [
               %{
                 "name" => "manifest_rig.start_job",
                 "command" => "start_job",
                 "label" => "Start a job",
                 "process" => "work",
                 "principals" => ["human"]
               }
             ],
             "roles" => [
               %{
                 "name" => "manifest_rig.clerk",
                 "label" => "Clerk",
                 "capabilities" => ["manifest_rig.start_job"]
               }
             ]
           }
  end

  test "does not invent v1 fields for queries, recordings, scope or system actors" do
    document = Manifest.build(Domain, [Work])
    encoded = Jason.encode!(document)

    refute encoded =~ "jobs_in_branch"
    refute encoded =~ "job_noted"
    refute encoded =~ "branch_id"
    refute encoded =~ "scheduler"
    refute encoded =~ "observer"
    refute Map.has_key?(document, "engine")
    refute Map.has_key?(document, "contracts")
  end

  test "refuses a domain with no contracts instead of writing an invalid empty manifest" do
    assert_raise ArgumentError, ~r/has no v2 contracts/, fn -> Manifest.build(Domain, []) end
  end
end

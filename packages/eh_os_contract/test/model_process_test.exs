defmodule EhOsContract.ModelProcessTest do
  @moduledoc """
  **The one place a reader asks what a contract's process is and which events make
  its run** (plan DD, P2a, #202): `Model.process/1` and `Model.process_events/1`,
  over a process with stages, one without, and a contract with none.
  """

  use ExUnit.Case, async: true

  alias EhOsContract.Model
  alias ProcessShapes.Promised

  defmodule Staged do
    @moduledoc false
    use EhOsContract.Contract,
      domain: ProcessShapes.Domain,
      context: :handling,
      id: "process_shapes.staged_followup"

    consumes Promised, [:request_received, :request_completed], as: [request_completed: :done]

    aggregate :followup, "Follow-up" do
      identity :request_id

      command :note_request, "Note a request", by: :reviewer, emits: :request_noted
      command :follow_up, "Follow up", by: :reviewer, emits: :followed_up

      stage :before do
        event :request_noted, "Request noted"
      end

      stage :after do
        event :followed_up, "Followed up", terminal: true
      end
    end

    process :followup, "Follow-up" do
      correlate :request_id

      stage :before do
        include :request_received
      end

      stage :after do
        include :done, terminal: true
      end
    end
  end

  defmodule Flat do
    @moduledoc false
    use EhOsContract.Contract,
      domain: ProcessShapes.Domain,
      context: :handling,
      id: "process_shapes.flat_followup"

    consumes Promised, [:request_refused, :refusal_notified]

    process :refusals, "Refusals", accountable: :reviewer do
      correlate :request_id
      include :request_refused
      include :refusal_notified, terminal: true
    end
  end

  describe "process/1" do
    test "is the process the contract declares, from a module or its model" do
      assert %{name: :followup, label: "Follow-up", correlate: [:request_id]} =
               Model.process(Staged)

      assert Model.process(Staged) == Model.process(Model.fetch(Staged))
      assert %{name: :refusals, accountable: :reviewer} = Model.process(Flat)
    end

    test "is nil for a contract without a process, and for a domain" do
      assert Model.process(ShreddingRig.Members) == nil
      assert Model.process(ProcessShapes.Domain) == nil
    end
  end

  describe "process_events/1" do
    test "are the contract's own events, then the includes in stage order, each resolved" do
      assert [
               %{
                 type: "process_shapes.staged_followup.request_noted",
                 name: :request_noted,
                 contract: Staged,
                 stage: :before,
                 terminal: false,
                 included: false
               },
               %{
                 type: "process_shapes.staged_followup.followed_up",
                 name: :followed_up,
                 contract: Staged,
                 stage: :after,
                 terminal: true,
                 included: false
               },
               %{
                 type: "process_shapes.promised.request_received",
                 name: :request_received,
                 contract: Promised,
                 stage: :before,
                 terminal: false,
                 included: true
               },
               # Under the name this contract consumes it as; terminal by the include,
               # though the sibling declares it terminal too.
               %{
                 type: "process_shapes.promised.request_completed",
                 name: :done,
                 contract: Promised,
                 stage: :after,
                 terminal: true,
                 included: true
               }
             ] = Model.process_events(Staged)
    end

    test "an included event's terminal is the include's, not its declaration's" do
      [received | _] = for %{included: true} = e <- Model.process_events(Staged), do: e
      assert received.declaration.name == :request_received
      assert received.declaration.label == "Request received"

      # `request_refused` ends no run in `Promised`, nor here; `refusal_notified` ends
      # one in both, and here only because its include says so.
      assert [
               %{name: :request_refused, stage: nil, terminal: false, contract: Promised},
               %{name: :refusal_notified, stage: nil, terminal: true, contract: Promised}
             ] = Model.process_events(Flat)
    end

    test "are the same from a module or its model" do
      assert Model.process_events(Staged) == Model.process_events(Model.fetch(Staged))
    end

    test "are none without a process, though the contract has events" do
      assert Model.fetch(ShreddingRig.Members).events != []
      assert Model.process_events(ShreddingRig.Members) == []
    end
  end
end

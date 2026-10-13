defmodule EhOsContract.ModelProcessTest do
  @moduledoc """
  **The one place a reader asks what a process is and which events make its run**
  (plan DD, P2a, #202): `Model.process/1` and `Model.process_events/1`, over a process
  module, a contract and a domain. Since plan DD, P2h (#221) only a process module
  declares a process.
  """

  use ExUnit.Case, async: true

  alias EhOsContract.Model
  alias ProcessShapes.{Handling, Promised}

  describe "process/1" do
    test "is the process a module declares, under its id, from the module or its model" do
      assert %{name: "process_shapes.handling", label: "Request handling"} =
               Model.process(Handling)

      assert %{correlate: [:request_id], accountable: nil} = Model.process(Handling)
      assert Model.process(Handling) == Model.process(Model.fetch(Handling))
    end

    test "is nil for a contract and for a domain, which declare none" do
      assert Model.process(Promised) == nil
      assert Model.process(ShreddingRig.Members) == nil
      assert Model.process(ProcessShapes.Domain) == nil
    end
  end

  describe "process_events/1" do
    test "are the includes in stage order, each resolved to the contract declaring it" do
      assert [
               %{
                 type: "process_shapes.promised.request_received",
                 name: :request_received,
                 contract: Promised,
                 stage: :intake,
                 terminal: false
               },
               %{name: :request_logged, stage: :intake},
               %{name: :request_approved, stage: :decision},
               %{name: :request_refused, stage: :decision},
               %{name: :request_completed, stage: :closing, terminal: true},
               %{name: :refusal_notified, stage: :closing, terminal: true}
             ] = Model.process_events(Handling)

      [received | _] = Model.process_events(Handling)
      assert received.declaration.label == "Request received"
    end

    test "end a run where the module's ends_on names them" do
      ends = for %{terminal: true} = e <- Model.process_events(Handling), do: e.name
      assert ends == Model.fetch(Handling).ends_on
    end

    test "are the same from a module or its model" do
      assert Model.process_events(Handling) == Model.process_events(Model.fetch(Handling))
    end

    test "are none for a contract, though it has events" do
      assert Model.fetch(Promised).events != []
      assert Model.process_events(Promised) == []
    end
  end
end

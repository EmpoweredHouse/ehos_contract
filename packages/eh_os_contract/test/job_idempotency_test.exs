defmodule EhOsContract.JobIdempotencyTest do
  @moduledoc """
  **The idempotency key must not be ambiguous about which fact it names.**

  Oban gives at-least-once, so an asynchronous handler will see the same event
  twice; the key it gets in its context is what lets it tell a repeat from a new
  fact. `EhOsContract.Job` builds that key by joining the values of the event's `identity`.

  Joining is where a separator can be eaten by the values it separates. With
  `identity: [:a, :b]`, the values `("x:y", "z")` and `("x", "y:z")` used to produce
  the same string — so two **different** business facts arrived at the client's
  idempotency table as one, the second one's handler never ran, and nothing recorded
  that a consequence had been skipped. Both events sit in the log looking handled.

  `EhOsContract.Instance` had already escaped its own separator for the same reason, on the
  run key. The two disagreed, and only one of them was right.

  ## Why the fixture is here rather than in `test/support/`

  The collision needs two `:id` fields in one `identity`, and no fixture in the
  repository has that — every rig event pairs an identifier with an integer, which
  cannot carry a separator. This contract exists for one line of arithmetic and is
  deliberately kept out of the registry, so it changes nothing about what
  `mix eh_os_contract.check` or the graph reports.
  """

  use EhOsContract.DataCase, async: false

  defmodule Contract do
    @moduledoc "Invented. Two identifier fields in one identity, which is all this needs."

    use EhOsContract.Contract

    event :note_taken,
      label: "Note taken",
      payload: %{case_id: :id, note_id: :id},
      identity: [:case_id, :note_id],
      process: :noting

    process :noting, label: "Noting", instance: [:case_id]
  end

  defmodule Handler do
    @moduledoc "Reports the key it was handed and does nothing else."

    use EhOsContract.Handler,
      contract: EhOsContract.JobIdempotencyTest.Contract,
      event: :note_taken,
      publishes: []

    @impl EhOsContract.Handler
    def handle(_payload, ctx) do
      send(self(), {:idempotency_key, ctx.idempotency_key})
      :ok
    end
  end

  defp key_for(case_id, note_id) do
    args = %{
      "handler" => inspect(Handler),
      "event_id" => Ecto.UUID.generate(),
      "event_type" => "note_taken",
      "payload" => %{"case_id" => case_id, "note_id" => note_id},
      "correlation_id" => Ecto.UUID.generate(),
      "causation_id" => nil,
      "chain" => ["note_taken"],
      "actor" => nil
    }

    assert :ok = EhOsContract.Job.perform(%Oban.Job{args: args, attempt: 1})
    assert_received {:idempotency_key, key}
    key
  end

  describe "a separator appearing inside the values it separates" do
    test "two different facts do not collide" do
      # If this fails, the second of the two facts is silently deduplicated at the
      # client's idempotency table: its handler never runs, no row records a skipped
      # attempt, and the log shows both events as though both had been handled. That
      # is a missing consequence with no observable failure, which is the one shape of
      # defect this whole product exists to detect in other people's systems.
      refute key_for("x:y", "z") == key_for("x", "y:z")
    end

    test "the separator survives as an escape rather than disappearing" do
      # Escaping rather than rejecting: an identifier's representation belongs to the
      # client, and a colon inside one is not a defect. What matters is that the key
      # is reversible in principle — a value's colon must not be indistinguishable
      # from the join's colon.
      assert key_for("x:y", "z") =~ "%3A"
    end

    test "the ordinary case is unchanged" do
      # The control. Escaping must not rewrite keys that had nothing to escape: those
      # keys are already written into clients' idempotency tables, and moving them
      # would make every fact in flight look new exactly once.
      assert key_for("c-1", "n-1") == "note_taken:c-1:n-1"
    end
  end

  describe "a value containing the escape sequence itself" do
    test "does not collide with one containing the separator" do
      # The same fault `EhOsContract.Instance` had on its run key: escaping `:` as `%3A` while
      # leaving `%` alone is not reversible, so a value that literally contains the
      # text `%3A` produced the same key as one containing `:`. Fixed the same way, by
      # escaping `%` first.
      refute key_for("x%3Ay", "z") == key_for("x:y", "z")
    end
  end
end

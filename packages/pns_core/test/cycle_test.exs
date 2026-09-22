defmodule PNS.CycleTest do
  @moduledoc """
  Stage 2.4: **a cycle at run time is stopped, and a backward edge is not a cycle.**

  `mix pns.check` reports a backward edge, which is a different thing and deliberately
  legal — one of them is the acceptance criterion of stage 1.3, because the workshop
  describes exactly that shape: a turnover with no invoice, then the invoice arrives
  and the pair closes. What nothing stopped was A causing B causing A, which runs until
  the stack or the connection gives out and arrives as a failure that says nothing
  about the contract having a loop.

  The rule is narrow on purpose: **the same event type twice on one path from the root
  emission.** Every cheaper rule is wrong, and the controls below are what make that
  claim more than a comment — a diamond and a repeated type in one transaction both
  have to pass.
  """

  use PNS.DataCase, async: false
  use Oban.Testing, repo: PNS.TestRepo

  alias ProcessShapes.Rig

  defp logged(type), do: Repo.aggregate(from(e in PNS.Event, where: e.type == ^type), :count)
  defp all_logged, do: Repo.aggregate(PNS.Event, :count)

  describe "the synchronous path" do
    test "a cycle raises and the message names the path that closed it" do
      error =
        assert_raise ArgumentError, fn ->
          PNS.emit!(Rig, :item_disputed, %{case_id: "c-1", item_no: 1})
        end

      assert error.message =~ "would close a cycle"
      assert error.message =~ "item_disputed → item_rechecked → item_disputed"

      # A message that only says "cycle detected" leaves somebody reading three
      # handlers to work out which two of them close it.
      assert error.message =~ "needs its own event"

      # And it has to say that going asynchronous is not the way out. The first
      # version of this message suggested exactly that, which the queued test below
      # disproves: the chain travels with the job, so the loop only gets slower.
      assert error.message =~ "does **not** help"
    end

    test "nothing is written, because nothing happened" do
      assert_raise ArgumentError, fn ->
        PNS.emit!(Rig, :item_disputed, %{case_id: "c-1", item_no: 1})
      end

      # The guard runs before the insert, and the transaction rolls back regardless.
      # A half-written cycle in the log would be worse than the recursion: it would
      # be a fact that never occurred.
      assert all_logged() == 0
    end
  end

  describe "the queued path" do
    test "a cycle closing across the queue is stopped too" do
      # The reason the chain travels in job arguments. A loop through jobs never
      # exhausts a stack — it just runs forever, and each hop looks like ordinary
      # work, which makes it the more dangerous of the two.
      PNS.emit!(Rig, :item_appealed, %{case_id: "c-1", item_no: 1})
      Oban.drain_queue(queue: :events)

      assert logged("item_appealed") == 1
      assert logged("item_reopened") == 1

      # Not two. Without the chain crossing the queue, the second `item_appealed`
      # would be emitted and the loop would keep going one job at a time.
      assert logged("item_appealed") == 1
    end

    test "the handling row says what went wrong instead of claiming success" do
      event = PNS.emit!(Rig, :item_appealed, %{case_id: "c-1", item_no: 1})
      Oban.drain_queue(queue: :events)

      reopened = Repo.one!(from(e in PNS.Event, where: e.type == "item_reopened"))

      [handling] =
        Repo.all(from(h in PNS.EventHandling, where: h.event_id == ^reopened.id))

      assert handling.status == "error"
      assert handling.error =~ "would close a cycle"

      # The event that started it is a fact and stays one.
      assert event.type == "item_appealed"
    end
  end

  describe "what is not a cycle" do
    test "a backward edge is legal, and the rig has one on purpose" do
      # `clarification_answered` is in `resolution` and publishes `item_paired` from
      # `matching` — the pair closes after the process moved on. `pns.check` reports
      # it; the runtime must not.
      PNS.emit!(Rig, :item_received, %{case_id: "c-1", item_no: 1, amount: -1})
      PNS.emit!(Rig, :clarification_answered, %{case_id: "c-1", item_no: 1})

      assert logged("item_paired") == 1
    end

    test "the same event type twice in one transaction is not a cycle" do
      # The case that kills the cheap rule "this type already appeared in this
      # transaction". Two items in one command produce two `item_paired` and two
      # `case_closed`, and neither occurrence is an ancestor of the other.
      {:ok, _} =
        PNS.emit_all(Rig, [
          PNS.event(:item_received, %{case_id: "c-1", item_no: 1, amount: 100}),
          PNS.event(:item_received, %{case_id: "c-1", item_no: 2, amount: 100})
        ])

      assert logged("item_received") == 2
      assert logged("item_paired") == 2
      assert logged("case_closed") == 2
    end

    test "a chain deeper than two is fine, so this is not a depth limit" do
      # `item_received → item_paired → case_closed` is three deep and legitimate.
      # A depth limit would need a number, and the number would be what decides
      # whether a real contract works.
      PNS.emit!(Rig, :item_received, %{case_id: "c-1", item_no: 1, amount: 100})

      assert logged("case_closed") == 1
    end
  end
end

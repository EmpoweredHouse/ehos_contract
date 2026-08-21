defmodule PNS.PublicationsTest do
  @moduledoc """
  Stage 2.1: **a handler emits only what it declared it publishes.**

  Until now `publishes:` was checked in one direction only. The compile gate verifies
  that every name in the declaration exists in the contract; nothing verified that
  what a handler actually emits appears in the declaration. So a handler could
  declare `publishes: [:x]`, emit `:y`, and pass compilation and `mix pns.check`
  alike as long as `:y` was declared somewhere in the contract.

  Why that matters more than tidiness: the deployment graph's edges come from
  `publishes:`, so an undeclared emission produces an observed edge that no recorded
  wiring contains, and the report calls it **drift** — correctly in form, for a false
  reason. The declaration would be describing the code instead of binding it.

  Both halves of every test here are load-bearing. A check that fired on any handler
  return at all would pass every positive case, so each path is paired with the same
  handler emitting nothing and staying silent.
  """

  use PNS.DataCase, async: false
  use Oban.Testing, repo: PNS.TestRepo

  alias ProcessShapes.Rig

  defp review(item_no), do: PNS.emit!(Rig, :item_reviewed, %{case_id: "c-1", item_no: item_no})
  defp escalate(item_no), do: PNS.emit!(Rig, :item_escalated, %{case_id: "c-1", item_no: item_no})

  defp logged(type) do
    Repo.aggregate(from(e in PNS.Event, where: e.type == ^type), :count)
  end

  describe "the synchronous path" do
    test "an undeclared emission raises, naming the handler and the declaration" do
      error = assert_raise ArgumentError, fn -> review(1) end

      assert error.message =~ "OnItemReviewed"
      assert error.message =~ "[:item_paired]"
      assert error.message =~ "publishes: []"

      # The message has to say why this is a defect, not only that it happened —
      # `publishes:` looks like documentation until someone reads what depends on it.
      assert error.message =~ "drift"
    end

    test "nothing reaches the log, not even the event that triggered the handler" do
      assert_raise ArgumentError, fn -> review(1) end

      # The check runs **before** emitting, and the synchronous handler's failure
      # rolls the transaction back — so the log does not carry a state change that
      # did not happen. That is the same rule as for any other synchronous failure
      # (ADR §13), and the reason 2.3 exists as a separate gap.
      assert logged("item_reviewed") == 0
      assert logged("item_paired") == 0
    end

    test "the same handler emitting nothing does not raise" do
      # The control. Without it the test above would also pass for a check that
      # rejected every handler return.
      event = review(0)

      assert event.type == "item_reviewed"
      assert logged("item_paired") == 0
    end
  end

  describe "the queued path" do
    test "an undeclared emission is recorded against the event, not raised at the caller" do
      # The consequence follows the transaction boundary rather than the rule
      # (ADR §9-10): the caller of an asynchronous handler is long gone, so the
      # failure belongs in the handling row where every other one already is.
      event = escalate(1)
      Oban.drain_queue(queue: :events)

      [handling] = Repo.all(from h in PNS.EventHandling, where: h.event_id == ^event.id)

      assert handling.status == "error"
      assert handling.error =~ "OnItemEscalated"
      assert handling.error =~ "without declaring it"
    end

    test "the triggering event survives, and the undeclared one is never emitted" do
      escalate(1)
      Oban.drain_queue(queue: :events)

      # Asymmetric with the synchronous path on purpose. The job runs outside a
      # transaction — deliberately, since an asynchronous handler exists to do I/O —
      # so the fact that triggered it stays a fact. What must not exist is the
      # emission itself.
      assert logged("item_escalated") == 1
      assert logged("item_paired") == 0
    end

    test "the same handler emitting nothing succeeds" do
      event = escalate(0)
      Oban.drain_queue(queue: :events)

      [handling] = Repo.all(from h in PNS.EventHandling, where: h.event_id == ^event.id)

      assert handling.status == "ok"
      assert logged("item_paired") == 0
    end
  end

  describe "what the rule does not reach" do
    test "a declared emission passes on both paths" do
      # The rig's four other handlers emit exactly what they declare and are driven
      # by the shape tests. Repeated here as one assertion so this file states its
      # own negative case rather than relying on another file to hold it.
      PNS.emit!(Rig, :item_received, %{case_id: "c-9", item_no: 1, amount: 100})
      Oban.drain_queue(queue: :events)

      assert logged("item_paired") == 1
    end

    test "a command's emissions are bounded by the contract, not by any declaration" do
      # A decision function has no `publishes:` to be measured against — its bound
      # is the contract, enforced in the emitter. Checking that here keeps the two
      # bounds from being confused: the narrower one applies to handlers only.
      assert_raise ArgumentError, ~r/does not declare event/, fn ->
        PNS.emit!(Rig, :nothing_like_this, %{case_id: "c-1"})
      end
    end
  end
end

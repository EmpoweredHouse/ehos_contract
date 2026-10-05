defmodule EhOsContract.DayTagsTest do
  @moduledoc """
  Plan W2: a required, non-personal date or timestamp is tagged with its day, in
  UTC, when the event is appended, so a boundary that buckets by day (B2) finds every
  event that could fall on it; an optional one is not. On the invented
  `DispatchRig.Ledger`'s `:day_closed`.
  """

  use EhOsContract.DataCase, async: false

  alias DispatchRig.Ledger
  alias DispatchRig.Ledger.Events.DayClosed
  alias EhOsContract.{Actor, Event, Key}

  @auditor Actor.credential("u-2", ["dispatch_rig.day_closed"])

  defp record(event), do: {:ok, _} = EhOsContract.record(Ledger, event, actor: @auditor)

  defp tags,
    do: Repo.one!(from(e in Event, where: e.type == "ledger.day_closed", select: e.tags))

  test "a required date and timestamp are tagged with their day; control: an optional date is not" do
    record(%DayClosed{
      account_id: "a-1",
      closed_on: ~D[2026-10-05],
      closed_at: ~U[2026-10-05 23:30:00Z],
      reopens_on: ~D[2026-10-07]
    })

    assert tags() == [
             "account_id:a-1",
             "closed_on.day:2026-10-05",
             "closed_at.day:2026-10-05"
           ]
  end

  test "a day tag reads apart from a field's tag" do
    assert Key.day_tag(:closed_at, ~U[2026-10-05 00:00:00Z]) == "closed_at.day:2026-10-05"
    assert Key.day_tag(:closed_on, ~D[2026-12-31]) == "closed_on.day:2026-12-31"
    refute Key.bucket_field?(%{type: :date, optional: true, personal: nil})
    refute Key.bucket_field?(%{type: :timestamp, optional: false, personal: :account_id})
    assert Key.bucket_field?(%{type: :timestamp, optional: false, personal: nil})
  end
end

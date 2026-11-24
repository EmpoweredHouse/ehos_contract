defmodule EhosContract.DayTagsTest do
  @moduledoc """
  Plan W2: a required, non-personal date or timestamp is tagged with its day, a
  timestamp's in the domain's `time_zone:`, when the event is appended, so a boundary
  that buckets by day (B2) finds every event that could fall on it; an optional one is
  not, and a domain value resting on a date is. On the invented `DispatchRig.Ledger`'s
  `:day_closed`, whose domain keeps the days of Warsaw and types `closed_on` by its
  value `:business_day`.
  """

  use EhosContract.DataCase, async: false

  alias DispatchRig.Ledger
  alias DispatchRig.Ledger.Events.DayClosed
  alias EhosContract.{Actor, Event, Key}

  @auditor Actor.credential("u-2", ["dispatch_rig.day_closed"])

  defp record(event), do: {:ok, _} = EhosContract.record(Ledger, event, actor: @auditor)

  defp tags,
    do:
      Repo.one!(
        from(e in Event, where: e.type == "dispatch_rig.ledger.day_closed", select: e.tags)
      )

  test "a required date and timestamp are tagged with their day; control: an optional date is not" do
    # 23:30 in UTC on the 5th is 01:30 on the 6th in Warsaw, the domain's zone.
    record(%DayClosed{
      account_id: "a-1",
      closed_on: ~D[2026-10-05],
      closed_at: ~U[2026-10-05 23:30:00Z],
      reopens_on: ~D[2026-10-07]
    })

    assert tags() == [
             "account_id:a-1",
             "closed_on.day:2026-10-05",
             "closed_at.day:2026-10-06"
           ]
  end

  test "a day tag reads apart from a field's tag" do
    assert Key.day_tag(:closed_at, ~U[2026-10-05 00:00:00Z]) == "closed_at.day:2026-10-05"

    assert Key.day_tag(:closed_at, ~U[2026-10-05 22:30:00Z], "Europe/Warsaw") ==
             "closed_at.day:2026-10-06"

    assert Key.day_tag(:closed_at, ~U[2026-01-05 22:30:00Z], "Europe/Warsaw") ==
             "closed_at.day:2026-01-05"

    assert Key.day_tag(:closed_on, ~D[2026-12-31]) == "closed_on.day:2026-12-31"
    refute Key.bucket_field?(%{type: :date, optional: true, personal: nil})
    refute Key.bucket_field?(%{type: :timestamp, optional: false, personal: :account_id})
    assert Key.bucket_field?(%{type: :timestamp, optional: false, personal: nil})
  end
end

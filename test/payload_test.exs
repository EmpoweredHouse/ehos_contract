defmodule PNS.PayloadTest do
  @moduledoc """
  Stage 2.2b: **the payload matches its declaration, and a type means something.**

  Until now the contract could say `task_count: :integer` and nothing checked. Worse,
  `PNS.Payload`'s own moduledoc promised that a synchronous and an asynchronous handler
  see "the same shape", and for values that was false: a `:timestamp` was a `DateTime`
  in one and ISO 8601 text in the other. Domain code paid for it by serialising by hand
  at the emit site, which is a field declared as a point in time deliberately holding
  text.

  Two halves, and both are needed for either to mean anything. Restoring values makes
  the type name a shape; validating them makes the declaration binding.
  """

  use Taxvision.DataCase, async: false

  alias PNS.Payload
  alias Taxvision.Contracts.AccountingMonth, as: Contract

  defp event_def(name), do: Contract.event(name)

  defp emit(name, payload), do: PNS.emit!(Contract, name, payload)

  describe "the promise that used to be false: one shape on both sides" do
    test "a timestamp given as a DateTime stays one" do
      cast = Payload.cast(event_def(:registry_status_checked), %{
        company_id: "c-1",
        period: "2026-07",
        checked_at: ~U[2026-08-05 09:00:00Z]
      })

      assert cast.checked_at == ~U[2026-08-05 09:00:00Z]
    end

    test "a timestamp arriving as text — the queue, the database — becomes a DateTime" do
      # This is the half that was missing. The asynchronous handler reads its payload
      # from job arguments, which are JSON, so text is the only thing that can arrive.
      cast = Payload.cast(event_def(:registry_status_checked), %{
        "company_id" => "c-1",
        "period" => "2026-07",
        "checked_at" => "2026-08-05T09:00:00Z"
      })

      assert cast.checked_at == ~U[2026-08-05 09:00:00Z]
    end

    test "the log holds text, and reading it back gives a DateTime again" do
      # The round trip end to end, through Postgres rather than through a hand-built
      # map: JSON has no way to carry a point in time, so the column holds ISO 8601 and
      # `cast/2` repairs the one thing the round trip destroys.
      emit(:registry_status_checked, %{
        company_id: "c-1",
        period: "2026-07",
        checked_at: ~U[2026-08-05 09:00:00Z]
      })

      row = Repo.one!(from e in PNS.Event, where: e.type == "registry_status_checked")

      assert row.payload["checked_at"] == "2026-08-05T09:00:00Z"
      assert Payload.cast(event_def(:registry_status_checked), row.payload).checked_at ==
               ~U[2026-08-05 09:00:00Z]
    end

    test "an integer needs no repair, because JSON does not damage it" do
      # The rule is "cast repairs exactly what JSON destroys", not "cast coerces". An
      # `:integer` arriving as `"5"` is a caller passing the wrong thing, and coercing
      # it would hide what validation exists to surface.
      assert_raise ArgumentError, ~r/`task_count` is declared as :integer and holds "5"/, fn ->
        emit(:monthly_tasks_generated, %{company_id: "c-1", period: "2026-07", task_count: "5"})
      end
    end
  end

  describe "a declaration nothing enforced" do
    test "a declared field that is missing is refused" do
      # The one that matters most: the contract says this fact carries a period and it
      # does not. Nothing caught this, and it is the exact shape of hole the product
      # exists to detect — a declaration nobody honoured reads as satisfied.
      assert_raise ArgumentError, ~r/`period` is declared and missing from the payload/, fn ->
        emit(:accounting_month_opened, %{company_id: "c-1"})
      end
    end

    test "a declared field holding nil is refused, and the message says why" do
      error =
        assert_raise ArgumentError, fn ->
          emit(:accounting_month_opened, %{company_id: "c-1", period: nil})
        end

      assert error.message =~ "holds nil"

      # There is no optional field in the payload DSL, so `nil` is not a lesser case of
      # present — it is absent with a key on it, and the message has to say so or
      # somebody adds `nil` to mean "not applicable".
      assert error.message =~ "no optional one"
    end

    test "each type refuses what it is not" do
      wrong = [
        {:monthly_tasks_generated, %{task_count: "many"}, ":integer"},
        {:registry_discrepancy_detected, %{diff: 12}, ":string"},
        {:registry_status_checked, %{checked_at: "not a date"}, ":timestamp"}
      ]

      for {event, bad, type} <- wrong do
        payload = Map.merge(%{company_id: "c-1", period: "2026-07"}, bad)

        error = assert_raise ArgumentError, fn -> emit(event, payload) end
        assert error.message =~ "declared as #{type}"
      end
    end

    test "nothing reaches the log when the payload is refused" do
      assert_raise ArgumentError, fn -> emit(:accounting_month_opened, %{company_id: "c-1"}) end

      assert Repo.aggregate(PNS.Event, :count) == 0
    end
  end

  describe "what an identifier accepts" do
    test "text or an integer, because the representation is the client's business" do
      # A client keying on a database sequence should not have to call it a string. What
      # the identifier refers to is theirs, and so is how they write it.
      assert Payload.validate!(Contract, :accounting_month_opened, event_def(:accounting_month_opened), %{
               company_id: 42,
               period: "2026-07"
             }) == :ok
    end

    test "not an empty string, which is a missing identifier with a type" do
      assert_raise ArgumentError, ~r/`company_id` is declared as :id and holds ""/, fn ->
        emit(:accounting_month_opened, %{company_id: "", period: "2026-07"})
      end
    end
  end

  describe "validation runs on the payload as supplied, before retain" do
    test "a dropped field is supplied, validated, and then gone from the log" do
      # The order was wrong on the first attempt and this is the case that proves why.
      # Validating after `retain` looks right — it checks what gets stored — and `:drop`
      # removes the field, so a declared field would be permanently missing and every
      # such event refused. Nothing in either contract used `:drop`, so the trap was
      # unreachable rather than absent.
      event = PNS.emit!(ProcessShapes.Rig, :item_noted, %{case_id: "c-1", item_no: 1, note: "text"})

      refute Map.has_key?(event.payload, "note")
      assert event.payload["case_id"] == "c-1"
    end

    test "a dropped field still has to be supplied and still has to typecheck" do
      # `retain` says what the log keeps; it does not excuse the caller from the
      # declaration. Otherwise `:drop` would be a way to opt a field out of its type.
      assert_raise ArgumentError, ~r/`note` is declared as :string and holds 12/, fn ->
        PNS.emit!(ProcessShapes.Rig, :item_noted, %{case_id: "c-1", item_no: 1, note: 12})
      end

      assert_raise ArgumentError, ~r/`note` is declared and missing/, fn ->
        PNS.emit!(ProcessShapes.Rig, :item_noted, %{case_id: "c-1", item_no: 1})
      end
    end

    test "a hashed field is judged on what the caller gave, not on the digest" do
      # The other half of the same mistake. `:hash` turns anything into a hex string, so
      # after `retain` a `:string` field could never fail and an `:integer` field could
      # never pass — the check would stop applying to exactly the fields carrying
      # sensitive content.
      assert_raise ArgumentError, ~r/`diff` is declared as :string and holds 12/, fn ->
        emit(:registry_discrepancy_detected, %{company_id: "c-1", period: "2026-07", diff: 12})
      end
    end
  end

  describe "strict on write, defensive on read" do
    test "an undeclared field is kept, not refused" do
      # Refused where it matters — a handler emitting an undeclared *event* does not get
      # this far — and one extra key is visible in the log rather than silent. Same
      # argument that made the retention check a report instead of a gate.
      event =
        emit(:accounting_month_opened, %{company_id: "c-1", period: "2026-07", extra: "kept"})

      assert event.payload["extra"] == "kept"

      cast = Payload.cast(event_def(:accounting_month_opened), event.payload)
      assert cast["extra"] == "kept"
      assert cast.company_id == "c-1"
    end

    test "an event written under an older shape can still be read" do
      # Nothing validates on the way out, deliberately. The log holds events written
      # under contracts that have since changed, and a report that cannot read history
      # is worse than one that reads it loosely — ADR §7-8 calls this reading the
      # payload defensively.
      Repo.insert!(%PNS.Event{
        type: "accounting_month_opened",
        contract: inspect(Contract),
        contract_version: "0000deadbeef",
        correlation_id: Ecto.UUID.generate(),
        payload: %{"company_id" => "c-1"},
        occurred_at: DateTime.utc_now()
      })

      row = Repo.one!(from e in PNS.Event, where: e.contract_version == "0000deadbeef")

      # No raise: the field the contract declares today is simply absent.
      assert Payload.cast(event_def(:accounting_month_opened), row.payload) == %{
               company_id: "c-1"
             }
    end
  end
end

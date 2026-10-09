defmodule Rehmed.AuthorizationTest do
  @moduledoc """
  Rehmed's v2 contracts behind the host's door (v2 plan, EA): a bearer
  credential verified by `EhOsContract.Auth.Plug`, every command served by
  `EhOsContract.Plug` over HTTP, and every decision recorded by `EhOsContract.Auth`.

  The first test is the one `eh-os` D-34 asks of every host: each capability the
  contract declares is mapped to the entry point that serves it, and each entry
  refuses a credential without it. The rest are its controls.
  """

  use Taxvision.DataCase, async: false
  use EhOsContract.Auth.Testing

  import Phoenix.ConnTest
  import Plug.Conn

  alias EhOsContract.Event

  alias Rehmed.Contracts.{
    ClinicalDocumentation,
    ExternalPayers,
    Scheduling,
    Settlement,
    StatutoryReporting
  }

  @contracts [Scheduling, ClinicalDocumentation, StatutoryReporting, Settlement, ExternalPayers]

  @endpoint EhOsContractHostWeb.Endpoint

  defp command(token, capability, body) do
    build_conn()
    |> put_req_header("authorization", "Bearer " <> token)
    |> put_req_header("content-type", "application/json")
    |> post("/api/rehmed/commands/#{capability}", Jason.encode!(body))
  end

  defp query(token, capability, params) do
    build_conn()
    |> put_req_header("authorization", "Bearer " <> token)
    |> get("/api/rehmed/queries/#{capability}?#{params}")
  end

  defp record(token, capability, body) do
    build_conn()
    |> put_req_header("authorization", "Bearer " <> token)
    |> put_req_header("content-type", "application/json")
    |> post("/api/rehmed/records/#{capability}", Jason.encode!(body))
  end

  @visit %{visit_id: "visit-anna"}
  @booking %{
    patient_id: "patient-anna",
    service_id: "service-physiotherapy",
    specialist_id: "specialist-ewa",
    scheduled_at: "2026-10-05T09:00:00Z"
  }
  @payer_period %{payer_id: "payer-luxmed", period_id: "2026-09"}
  @close %{
    visit_id: "visit-anna",
    patient_id: "patient-anna",
    pesel: "85010112345",
    icd10: "M54.5",
    icd9: "93.39",
    practitioner_number: "practitioner-ewa"
  }

  # Every capability of the five contracts. What only the application's own code
  # does — the reactions' commands, the integration's recordings — has none, and the
  # door answers 404 for it (the last test).
  defp entries do
    commands = %{
      "rehmed.book_visit" => @booking,
      "rehmed.cancel_visit" => @visit,
      "rehmed.record_no_show" => @visit,
      "rehmed.code_diagnosis" => Map.take(@close, [:visit_id, :patient_id, :icd10, :icd9]),
      "rehmed.close_visit_clinically" => @close,
      "rehmed.hand_over_visit" => @visit,
      "rehmed.add_service_line" => %{visit_id: "visit-anna", service_id: "usg"},
      "rehmed.record_payment" => %{visit_id: "visit-anna", method: "card", amount: 20_000},
      "rehmed.close_settlement" => @visit,
      "rehmed.book_correction" => %{visit_id: "visit-anna", delta: -1_000},
      "rehmed.mark_settled_with_payer" => Map.put(@payer_period, :visit_id, "visit-anna"),
      "rehmed.exclude_visit_from_invoice" =>
        Map.merge(@payer_period, %{visit_id: "visit-anna", reason: "duplicate"}),
      "rehmed.issue_payer_invoice" =>
        Map.put(@payer_period, :invoice_id, "invoice-luxmed-2026-09")
    }

    records = ~w(rehmed.patient_arrived rehmed.visit_completed)

    Map.new(commands, fn {capability, body} -> {capability, &command(&1, capability, body)} end)
    |> Map.merge(Map.new(records, &{&1, fn token -> record(token, &1, @visit) end}))
    |> Map.put(
      "rehmed.daily_totals_for",
      &query(&1, "rehmed.daily_totals_for", "business_date=2026-09-28")
    )
  end

  defp decisions(subject) do
    Repo.query!(
      "SELECT capability, outcome, reason FROM eh_os_contract_auth_decisions WHERE subject = $1",
      [subject]
    ).rows
  end

  test "every entry point refuses a credential without its capability" do
    assert assert_every_entry_refuses(@contracts, entries()) == :ok
  end

  test "the control: a credential with the capability goes through, and has its row too" do
    token = credential("u-specialist", ["rehmed.add_service_line"])

    conn =
      command(token, "rehmed.add_service_line", %{visit_id: "visit-anna", service_id: "usg"})

    assert conn.status == 200
    assert decisions("u-specialist") == [["rehmed.add_service_line", "allowed", nil]]

    assert Repo.all(from(e in Event, select: {e.type, e.actor})) ==
             [{"rehmed.settlement.service_line_added", "actor:u-specialist"}]
  end

  test "a request without a credential stops at the door, before any decision" do
    conn =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> post("/api/rehmed/commands/rehmed.hand_over_visit", "{}")

    assert {conn.status, Jason.decode!(conn.resp_body)} == {401, %{"error" => "no_credential"}}
    assert Repo.query!("SELECT count(*) FROM eh_os_contract_auth_decisions").rows == [[0]]
  end

  test "fields that do not fit are refused first to a credential without the capability" do
    body = %{visit_id: "visit-anna", payer_id: 7}

    stranger = credential("u-stranger", [])
    refused = command(stranger, "rehmed.close_settlement", body)

    assert {refused.status, Jason.decode!(refused.resp_body)} ==
             {403, %{"refused" => "missing_capability"}}

    assert decisions("u-stranger") == [
             ["rehmed.close_settlement", "refused", "missing_capability"]
           ]

    # The control: with the capability, the problem with the fields is the answer,
    # and the request is still one decision.
    reception = credential("u-reception", ["rehmed.close_settlement"])
    invalid = command(reception, "rehmed.close_settlement", body)

    assert {invalid.status, Jason.decode!(invalid.resp_body)} ==
             {422, %{"invalid" => %{"payer_id" => "type"}}}

    assert decisions("u-reception") == [["rehmed.close_settlement", "allowed", nil]]
  end

  test "only the specialist the visit is booked with closes it, by the flag of its booking" do
    # Plan DD, A2 (#249): the specialist reception booked the visit with closes it
    # (`AGG-02` invariant 3), and whether the codes are required is the booking's flag.
    # Both specialists hold the role's whole permission, as the clinic grants it.
    specialist = ["rehmed.visit_completed", "rehmed.close_visit_clinically"]
    reception = credential("u-reception", ["rehmed.book_visit"])
    ewa = credential("specialist-ewa", specialist)
    ola = credential("specialist-ola", specialist)

    booked =
      build_conn()
      |> put_req_header("authorization", "Bearer " <> reception)
      |> put_req_header("content-type", "application/json")
      |> put_req_header("idempotency-key", "booking-anna")
      |> post("/api/rehmed/commands/rehmed.book_visit", Jason.encode!(@booking))

    %{"identity" => %{"visit_id" => visit}} = Jason.decode!(booked.resp_body)
    close = %{@close | visit_id: visit}

    # A colleague who records the patient leaving is still not the one the visit is
    # booked with, and is refused, as the business refuses it.
    assert record(ola, "rehmed.visit_completed", %{visit_id: visit}).status == 200
    other = command(ola, "rehmed.close_visit_clinically", close)

    assert {other.status, Jason.decode!(other.resp_body)} ==
             {422, %{"rejected" => "closed_by_its_specialist"}}

    # Physiotherapy is reported, by its booking: without the codes it does not close.
    uncoded = command(ewa, "rehmed.close_visit_clinically", Map.drop(close, [:icd10, :icd9]))

    assert {uncoded.status, Jason.decode!(uncoded.resp_body)} ==
             {422, %{"rejected" => "codes_before_clinical_close"}}

    assert command(ewa, "rehmed.close_visit_clinically", close).status == 200

    assert [%{"p1_reported" => true}] =
             Repo.all(
               from(e in Event,
                 where: e.type == "rehmed.clinical_documentation.visit_closed_clinically",
                 select: e.payload
               )
             )
  end

  test "a visit the host does not price is the host's to answer, and nothing is written" do
    # Plan T1s: the settlement's total is the host's; a visit it has no price for is a
    # 503, not the caller's fault.
    reception = credential("u-reception", ["rehmed.close_settlement"])
    unknown = command(reception, "rehmed.close_settlement", %{visit_id: "visit-zofia"})

    assert {unknown.status, Jason.decode!(unknown.resp_body)} ==
             {503, %{"error" => "not_supplied"}}

    assert Repo.aggregate(Event, :count) == 0
  end

  test "a booking reads its service from the catalogue, and the visit keeps its P1 flag" do
    # Plan DD, T2s (#245): whether the visit is reported to P1 is the catalogue's to say,
    # as it stood when the visit was booked (`AGG-15`).
    reception = credential("u-reception", ["rehmed.book_visit"])

    # A booking creates the visit, so it carries an idempotency key.
    book = fn service ->
      build_conn()
      |> put_req_header("authorization", "Bearer " <> reception)
      |> put_req_header("content-type", "application/json")
      |> put_req_header("idempotency-key", "booking-" <> service)
      |> post(
        "/api/rehmed/commands/rehmed.book_visit",
        Jason.encode!(%{@booking | service_id: service})
      )
    end

    for {service, reported} <- [{"service-physiotherapy", true}, {"service-fitness", false}] do
      booked = book.(service)
      assert booked.status == 200

      assert [%{"p1_reported" => ^reported}] =
               Repo.all(
                 from(e in Event,
                   where: e.type == "rehmed.scheduling.visit_booked",
                   where: fragment("?->>'service_id' = ?", e.payload, ^service),
                   select: e.payload
                 )
               )
    end

    # A service the catalogue does not have names nothing: refused as the field's
    # problem, and nothing is written.
    written = Repo.aggregate(Event, :count)
    unknown = book.("service-yoga")

    assert {unknown.status, Jason.decode!(unknown.resp_body)} ==
             {422, %{"invalid" => %{"service_id" => "unknown"}}}

    assert Repo.aggregate(Event, :count) == written
  end

  test "a settlement's total is the host's too, by who pays" do
    # Reception could otherwise settle for any amount: the payment lines are held to
    # the total, and the total to nothing.
    reception = credential("u-reception", ["rehmed.record_payment", "rehmed.close_settlement"])

    paid =
      command(reception, "rehmed.record_payment", %{
        visit_id: "visit-anna",
        method: "card",
        amount: 20_000
      })

    assert paid.status == 200

    sent = command(reception, "rehmed.close_settlement", %{visit_id: "visit-anna", total: 1})

    assert {sent.status, Jason.decode!(sent.resp_body)} ==
             {422, %{"invalid" => %{"total" => "supplied"}}}

    closed = command(reception, "rehmed.close_settlement", @visit)
    assert closed.status == 200

    assert [%{"total" => 20_000}] =
             Repo.all(
               from(e in Event,
                 where: e.type == "rehmed.settlement.visit_closed_commercially",
                 select: e.payload
               )
             )
  end

  test "what only the application's own code does is not a door, whatever the credential names" do
    # A credential granted these by mistake could otherwise record "sent to P1"
    # without a send, or queue a report with any PESEL (plan, E9a review).
    token =
      credential("u-mistaken", [
        "rehmed.p1_report_sent",
        "rehmed.queue_p1_report",
        "rehmed.create_documentation_overdue_task"
      ])

    assert record(token, "rehmed.p1_report_sent", @visit).status == 404
    assert command(token, "rehmed.queue_p1_report", @close).status == 404
    assert command(token, "rehmed.create_documentation_overdue_task", @visit).status == 404
    assert Repo.all(from(e in Event, select: e.type)) == []
  end

  test "recording the arrival at a visit nobody booked answers 404, not a refusal" do
    # The visit's identity is the library's, so an arrival for an identifier no booking
    # returned names no visit; 403 would read as a missing capability.
    token = credential("u-reception", ["rehmed.patient_arrived"])
    conn = record(token, "rehmed.patient_arrived", %{visit_id: Ecto.UUID.generate()})

    assert {conn.status, Jason.decode!(conn.resp_body)} == {404, %{"error" => "not_created"}}
    assert decisions("u-reception") == [["rehmed.patient_arrived", "allowed", nil]]
  end

  describe "the check itself" do
    test "fails on a declared capability with no entry point, naming it" do
      entries = Map.delete(entries(), "rehmed.book_correction")

      error =
        assert_raise ExUnit.AssertionError, fn ->
          assert_every_entry_refuses(@contracts, entries)
        end

      assert error.message =~ "no entry for: rehmed.book_correction"
    end

    test "fails on an entry the contract does not declare, naming it" do
      entries = Map.put(entries(), "rehmed.pay_everything", fn _token -> :ok end)

      error =
        assert_raise ExUnit.AssertionError, fn ->
          assert_every_entry_refuses(@contracts, entries)
        end

      assert error.message =~ "not declared: rehmed.pay_everything"
    end

    test "fails on an entry point that never asks" do
      entries = Map.put(entries(), "rehmed.close_settlement", fn _token -> :ok end)

      error =
        assert_raise ExUnit.AssertionError, fn ->
          assert_every_entry_refuses(@contracts, entries)
        end

      assert error.message =~ "the entry point for rehmed.close_settlement did not ask"
    end
  end
end

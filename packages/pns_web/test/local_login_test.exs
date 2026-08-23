defmodule PNS.Web.LocalLoginTest do
  @moduledoc """
  The provisional login end to end: form renders, a missing subject is
  refused, and a successful login's session is what
  `PNS.Web.Plug.Authenticate` reads back on the *next* request — proven by
  actually making two requests, not by asserting on `put_session` in
  isolation.
  """

  use ExUnit.Case, async: true

  import Phoenix.ConnTest

  @endpoint PNS.Web.TestHost.Endpoint

  setup do
    {:ok, conn: build_conn()}
  end

  test "GET renders a form asking who you are", %{conn: conn} do
    html = conn |> get("/pns/login") |> html_response(200)
    assert html =~ ~s(name="subject")
    assert html =~ ~s(name="role")
  end

  test "an empty subject is refused, not silently accepted", %{conn: conn} do
    conn = post(conn, "/pns/login", %{"subject" => "", "role" => "pns_admin"})
    assert html_response(conn, 200) =~ "Subject is required."
  end

  test "logging in and then visiting the dashboard sees the session, not a header",
       %{conn: conn} do
    conn = post(conn, "/pns/login", %{"subject" => "alice", "role" => "pns_admin"})
    assert redirected_to(conn, 303) == "/pns/contract"

    # /pns/accounts, not /pns/contract: this test proves the *session*
    # carries the actor forward, which needs no database — Agent-backed
    # Accounts is the cheaper of the two screens to prove it with.
    conn = conn |> recycle() |> get("/pns/accounts")
    assert html_response(conn, 200) =~ "Access: all"
  end

  test "read only comes back from the login screen too", %{conn: conn} do
    conn = post(conn, "/pns/login", %{"subject" => "bob", "role" => "pns_read"})
    conn = conn |> recycle() |> get("/pns/accounts")
    assert html_response(conn, 200) =~ "Access: read only"
  end

  test "logging out clears the session — the dashboard asks again", %{conn: conn} do
    conn = post(conn, "/pns/login", %{"subject" => "alice", "role" => "pns_admin"})

    conn = conn |> recycle() |> get("/pns/logout")
    assert redirected_to(conn) == "/pns/login"

    conn = conn |> recycle() |> get("/pns/contract")
    assert redirected_to(conn) == "/pns/login"
  end
end

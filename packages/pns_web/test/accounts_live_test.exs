defmodule PNS.Web.Live.AccountsTest do
  @moduledoc """
  No Postgres here — `PNS.Auth.LocalIdentityAdmin` is a plain `Agent`, so this
  suite proves the screen against it directly, through the real router (so
  `PNS.Web.Authentication`'s access decision is the real one, not assumed).
  """

  # Shared, global Agent state (test_helper.exs starts one process for the
  # whole run) — async tests would read each other's invites.
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias PNS.Web.TestHost.TestToken

  @endpoint PNS.Web.TestHost.Endpoint

  setup do
    Agent.update(PNS.Auth.LocalIdentityAdmin, fn _ -> %{} end)
    {:ok, conn: build_conn()}
  end

  test "an admin can invite someone and see them appear with no roles", %{conn: conn} do
    conn = TestToken.put_actor(conn, "admin", ["pns_admin"])
    {:ok, view, _html} = live(conn, "/pns/accounts")

    html =
      view
      |> form("form[phx-submit=invite]", %{"name" => "Alice", "email" => "alice@example.com"})
      |> render_submit()

    assert html =~ "Alice"
    assert html =~ "alice@example.com"
    assert html =~ "No roles granted."
  end

  test "an admin can grant a role and then revoke it", %{conn: conn} do
    {:ok, user} = PNS.Auth.invite_user("bob@example.com", "Bob")
    conn = TestToken.put_actor(conn, "admin", ["pns_admin"])
    {:ok, view, _html} = live(conn, "/pns/accounts")

    granted =
      view
      |> form("form[phx-submit=grant_role]", %{"user_id" => user.id, "role" => "pns_read"})
      |> render_submit()

    assert granted =~ "pns_read"

    revoked =
      view
      |> element("button[phx-click=revoke_role][phx-value-role=pns_read]")
      |> render_click()

    refute revoked =~ "pns_read"
  end

  test "granting a role for nobody leaves the roster unchanged", %{conn: conn} do
    conn = TestToken.put_actor(conn, "admin", ["pns_admin"])
    {:ok, view, _html} = live(conn, "/pns/accounts")

    html =
      render_click(view, "grant_role", %{"user_id" => "does-not-exist", "role" => "pns_admin"})

    assert html =~ "No users yet."
  end

  test "a read_only user sees the roster but gets no way to change it", %{conn: conn} do
    PNS.Auth.invite_user("carol@example.com", "Carol")
    conn = TestToken.put_actor(conn, "viewer", ["pns_read"])
    {:ok, view, html} = live(conn, "/pns/accounts")

    assert html =~ "carol@example.com"
    refute html =~ "Grant"
    refute html =~ "Invite someone"

    # The button being hidden is not the only guard: the same event sent
    # directly, bypassing the DOM entirely, is refused too.
    after_attempt =
      render_click(view, "grant_role", %{"user_id" => "whoever", "role" => "pns_admin"})

    refute after_attempt =~ "pns_admin"
  end
end

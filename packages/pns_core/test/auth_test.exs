defmodule PNS.AuthTest do
  @moduledoc """
  `PNS.Auth.LocalIdentityAdmin`, the fake `docs/adr/identity-seam.md`'s
  accounts screen calls through `PNS.Auth`. Not a `PNS.DataCase` test: this
  fake is a plain `Agent`, no repo involved.
  """

  use ExUnit.Case, async: false

  setup do
    Agent.update(PNS.Auth.LocalIdentityAdmin, fn _ -> %{} end)
    :ok
  end

  test "an invited user starts with no roles" do
    assert {:ok, user} = PNS.Auth.invite_user("alice@example.com", "Alice")
    assert user.email == "alice@example.com"
    assert user.roles == []
    assert PNS.Auth.list_users() == [user]
  end

  test "granting a role is visible on the next read, and does not duplicate" do
    {:ok, user} = PNS.Auth.invite_user("bob@example.com", "Bob")

    assert :ok = PNS.Auth.grant_role(user.id, "pns_admin")
    assert :ok = PNS.Auth.grant_role(user.id, "pns_admin")

    assert [%{roles: ["pns_admin"]}] = PNS.Auth.list_users()
  end

  test "revoking removes exactly that role" do
    {:ok, user} = PNS.Auth.invite_user("carol@example.com", "Carol")
    PNS.Auth.grant_role(user.id, "pns_admin")
    PNS.Auth.grant_role(user.id, "pns_read")

    assert :ok = PNS.Auth.revoke_role(user.id, "pns_admin")
    assert [%{roles: ["pns_read"]}] = PNS.Auth.list_users()
  end

  test "granting or revoking a role for nobody is an error, not a silent no-op" do
    assert {:error, :not_found} = PNS.Auth.grant_role("does-not-exist", "pns_admin")
    assert {:error, :not_found} = PNS.Auth.revoke_role("does-not-exist", "pns_admin")
  end

  test "the user list is sorted by email, not by insertion order" do
    PNS.Auth.invite_user("zed@example.com", "Zed")
    PNS.Auth.invite_user("amy@example.com", "Amy")

    assert [%{email: "amy@example.com"}, %{email: "zed@example.com"}] = PNS.Auth.list_users()
  end
end

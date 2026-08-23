defmodule PNS.Web.Resolvers.DefaultTest do
  use ExUnit.Case, async: true

  alias PNS.Auth.Actor
  alias PNS.Web.Resolvers.Default

  test "an actor entitled to pns_admin gets :all" do
    assert Default.resolve_access(%Actor{subject: "a", roles: ["pns_admin"]}) == :all
  end

  test "an actor entitled to pns_read only gets :read_only" do
    assert Default.resolve_access(%Actor{subject: "a", roles: ["pns_read"]}) == :read_only
  end

  test "pns_admin outranks pns_read when both are present" do
    assert Default.resolve_access(%Actor{subject: "a", roles: ["pns_read", "pns_admin"]}) == :all
  end

  test "an actor with an unrelated role is forbidden" do
    assert Default.resolve_access(%Actor{subject: "a", roles: ["something_else"]}) ==
             {:forbidden, "/"}
  end

  test "no actor at all is forbidden" do
    assert Default.resolve_access(nil) == {:forbidden, "/"}
  end

  test "resolve_user reads conn.assigns[:pns_actor]" do
    actor = %Actor{subject: "a"}
    conn = %Plug.Conn{assigns: %{pns_actor: actor}}
    assert Default.resolve_user(conn) == actor
  end

  test "resolve_user is nil when nothing set the assign" do
    conn = %Plug.Conn{}
    assert Default.resolve_user(conn) == nil
  end
end

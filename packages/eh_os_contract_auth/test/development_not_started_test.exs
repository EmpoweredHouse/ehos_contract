defmodule EhOsContract.Auth.DevelopmentNotStartedTest do
  # The development mode in `mix test`, where it never starts: what each part of it answers
  # there.
  use ExUnit.Case, async: true

  alias EhOsContract.Auth.{Development, SignIn}
  alias EhOsContract.Auth.Development.{Credential, Guard}

  test "without the switch, the child starts nothing" do
    assert Application.get_env(:eh_os_contract_auth, :development) == nil
    assert Development.start_link([]) == :ignore
    assert :ets.whereis(Development) == :undefined
  end

  test "where the mode has not started, it signs nothing, renews nothing, and makes no key" do
    assert Development.sign_in("u-dev", []) == {:error, :not_started}
    assert Development.credential("u-dev", []) == {:error, :not_started}
    assert Development.renew(SignIn, "u-dev", "a.b.c") == {:error, :not_started}
    assert Development.sign_in_path(SignIn) == nil
    refute Development.token?("anything")
    refute Development.key?(%{"kty" => "OKP", "crv" => "Ed25519", "x" => "AAAA"})
    assert :ets.whereis(Development) == :undefined
  end

  test "the guard and the endpoint answer 403 where the mode has not started" do
    conn = %{Plug.Test.conn(:get, "/dev/sign-in?token=x") | host: "localhost"}
    assert Guard.check(conn) == {:error, :not_started}
    assert Guard.call(conn, []).status == 403
    assert Credential.call(%{Plug.Test.conn(:post, "/") | host: "localhost"}, []).status == 403
  end
end

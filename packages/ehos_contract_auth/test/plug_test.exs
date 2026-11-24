defmodule EhosContract.Auth.PlugTest do
  @moduledoc """
  EA: the bearer plug in front of `EhosContract.Plug` — a verified credential
  becomes `conn.assigns.ehos_contract_actor`, anything else stops at 401 with the
  reason and without a row.
  """

  use EhosContract.Auth.KeyCase, async: false

  import Plug.Conn
  import Plug.Test

  alias EhosContract.Actor
  alias EhosContract.Auth.Plug, as: BearerPlug

  setup do
    pair = key_pair()
    keys = start_keys(ehos({:keys, [pair]}))
    %{pair: pair, opts: BearerPlug.init(keys: keys)}
  end

  defp call(opts, authorization) do
    conn = conn(:post, "/commands/clinic.record_payment")
    conn = if authorization, do: put_req_header(conn, "authorization", authorization), else: conn
    BearerPlug.call(conn, opts)
  end

  defp decisions, do: Repo.query!("SELECT count(*) FROM ehos_contract_auth_decisions").rows

  test "an option verify/2 does not take is refused at init, not ignored" do
    assert_raise ArgumentError, ~r/not \[:audiance\]/, fn ->
      BearerPlug.init(audiance: "clinic/staging")
    end
  end

  test "a verified credential goes on, with its actor", %{pair: pair, opts: opts} do
    conn = call(opts, "Bearer " <> credential(pair, %{"sub" => "u-anna"}))

    refute conn.halted
    assert %Actor{kind: :credential, subject: "u-anna"} = conn.assigns.ehos_contract_actor
  end

  test "the scheme is read without regard to case", %{pair: pair, opts: opts} do
    refute call(opts, "bearer " <> credential(pair)).halted
  end

  test "no credential is 401 no_credential", %{opts: opts} do
    for authorization <- [nil, "Basic dTpw", "Bearer ", "Bearer"] do
      conn = call(opts, authorization)

      assert {conn.status, Jason.decode!(conn.resp_body)} == {401, %{"error" => "no_credential"}},
             "for #{inspect(authorization)}"

      assert conn.halted
      assert get_resp_header(conn, "www-authenticate") == ["Bearer"]
    end
  end

  test "a refused credential is 401 with its reason, and no row", %{pair: pair, opts: opts} do
    for {token, reason} <- [
          {credential(pair, %{"aud" => "clinic/production"}), "wrong_audience"},
          {credential(pair, %{"exp" => 0}), "expired"},
          {credential(key_pair()), "unknown_key"},
          {"not-a-credential", "bad_signature"}
        ] do
      conn = call(opts, "Bearer " <> token)

      assert {conn.status, Jason.decode!(conn.resp_body)} == {401, %{"error" => reason}}
      assert conn.halted
      assert get_resp_header(conn, "www-authenticate") == [~s(Bearer error="invalid_token")]
    end

    assert decisions() == [[0]]
  end
end

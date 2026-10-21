defmodule EhOsContract.Auth.VerifyTest do
  @moduledoc """
  EA: what `EhOsContract.Auth.verify/2` accepts, and each reason it refuses with
  (`eh-os` D-33, D-34). Every refusal has a control beside it that differs in the
  one thing refused.
  """

  use EhOsContract.Auth.KeyCase, async: false

  alias EhOsContract.{Actor, Auth, Clock}

  setup do
    pair = key_pair()
    ehos = ehos({:keys, [pair]})
    %{pair: pair, ehos: ehos, keys: start_keys(ehos)}
  end

  test "a credential EHOS signed becomes the actor it describes", %{pair: pair, keys: keys} do
    scp = %{"clinic.open_visits_for_clinic" => %{"clinic_id" => ["north"]}}

    token =
      credential(pair, %{
        "sub" => "u-anna",
        "cap" => ["clinic.open_visits_for_clinic", "clinic.record_payment"],
        "scp" => scp
      })

    assert {:ok, %Actor{kind: :credential} = actor} = Auth.verify(token, keys: keys)
    assert actor.subject == "u-anna"

    assert actor.capabilities ==
             MapSet.new(["clinic.open_visits_for_clinic", "clinic.record_payment"])

    assert actor.scopes == scp
  end

  test "a credential without scp carries no scopes", %{pair: pair, keys: keys} do
    assert {:ok, %Actor{scopes: scopes}} = Auth.verify(credential(pair), keys: keys)
    assert scopes == %{}
  end

  describe "the algorithm is the header's Ed25519 and nothing else" do
    # Two layers refuse this: the header check in `verify/2`, and Joken, which does
    # not verify an `EdDSA` token with an `Ed25519` signer. Removing either leaves
    # the test green (checked 27 September 2026); it pins the outcome, not a layer.
    test "alg EdDSA is refused, though the key and the signature are the same kind",
         %{pair: pair, keys: keys} do
      token = credential(pair, %{}, header: %{"alg" => "EdDSA"})
      assert Auth.verify(token, keys: keys) == {:error, :bad_signature}
    end

    test "a header without kid is refused", %{pair: pair, keys: keys} do
      [header, payload, signature] = String.split(credential(pair), ".")
      header = header |> Base.url_decode64!(padding: false) |> Jason.decode!()
      header = header |> Map.delete("kid") |> Jason.encode!() |> Base.url_encode64(padding: false)

      assert Auth.verify(Enum.join([header, payload, signature], "."), keys: keys) ==
               {:error, :bad_signature}
    end

    test "a header naming critical parameters is refused", %{pair: pair, keys: keys} do
      token = credential(pair, %{}, header: %{"crit" => ["exp"]})
      assert Auth.verify(token, keys: keys) == {:error, :bad_signature}
    end

    test "something that is not a JWT is refused", %{keys: keys} do
      assert Auth.verify("not-a-credential", keys: keys) == {:error, :bad_signature}
      assert Auth.verify("", keys: keys) == {:error, :bad_signature}
    end
  end

  describe "the signature" do
    test "a credential signed by another key under a known kid is refused",
         %{pair: pair, keys: keys} do
      forger = key_pair()
      token = credential(%{forger | kid: pair.kid})
      assert Auth.verify(token, keys: keys) == {:error, :bad_signature}
    end

    test "a claim changed after signing is refused", %{pair: pair, keys: keys} do
      [header, _payload, signature] = String.split(credential(pair), ".")

      widened =
        credential(pair, %{"cap" => ["clinic.record_payment", "clinic.close_visit"]})
        |> String.split(".")
        |> Enum.at(1)

      assert Auth.verify(Enum.join([header, widened, signature], "."), keys: keys) ==
               {:error, :bad_signature}
    end

    test "a key no set in force holds is unknown", %{keys: keys} do
      assert Auth.verify(credential(key_pair()), keys: keys) == {:error, :unknown_key}
    end
  end

  describe "the claims" do
    test "another issuer is refused", %{pair: pair, keys: keys} do
      token = credential(pair, %{"iss" => "https://elsewhere.test"})
      assert Auth.verify(token, keys: keys) == {:error, :wrong_issuer}
      assert {:ok, _} = Auth.verify(token, keys: keys, issuer: "https://elsewhere.test")
    end

    test "another audience is refused, and so is the right one in a list",
         %{pair: pair, keys: keys} do
      assert Auth.verify(credential(pair, %{"aud" => "clinic/production"}), keys: keys) ==
               {:error, :wrong_audience}

      assert Auth.verify(credential(pair, %{"aud" => ["clinic/test"]}), keys: keys) ==
               {:error, :wrong_audience}

      assert Auth.verify(credential(pair, %{"aud" => "ehos"}), keys: keys) ==
               {:error, :wrong_audience}

      assert {:ok, _} =
               Auth.verify(credential(pair, %{"aud" => "clinic/production"}),
                 keys: keys,
                 audience: "clinic/production"
               )
    end

    test "a credential past its exp is expired, by the engine's clock", %{pair: pair, keys: keys} do
      exp = ~U[2026-09-27 10:10:00.000000Z]
      token = credential(pair, %{"exp" => DateTime.to_unix(exp)})

      assert {:ok, _} = Clock.at(DateTime.add(exp, -1), fn -> Auth.verify(token, keys: keys) end)
      assert Clock.at(exp, fn -> Auth.verify(token, keys: keys) end) == {:error, :expired}
    end

    test "a credential that claims to live longer than EHOS issues is refused",
         %{pair: pair, keys: keys} do
      now = ~U[2026-09-27 10:00:00.000000Z]
      exp = fn seconds -> credential(pair, %{"exp" => DateTime.to_unix(now) + seconds}) end

      Clock.at(now, fn ->
        assert {:ok, _} = Auth.verify(exp.(15 * 60), keys: keys)
        assert Auth.verify(exp.(15 * 60 + 1), keys: keys) == {:error, :bad_signature}
        assert Auth.verify(exp.(365 * 24 * 3600), keys: keys) == {:error, :bad_signature}
      end)
    end

    test "a credential without exp is expired", %{pair: pair, keys: keys} do
      token = credential(pair, %{"exp" => nil})
      assert Auth.verify(token, keys: keys) == {:error, :expired}
    end

    test "a credential whose claims have not the shape EHOS writes is refused",
         %{pair: pair, keys: keys} do
      assert Auth.verify(credential(pair, %{"sub" => 81}), keys: keys) == {:error, :bad_signature}

      # An empty subject would label every such actor `actor:`, one actor for all of
      # them, sharing its idempotency keys and so its receipts.
      assert Auth.verify(credential(pair, %{"sub" => ""}), keys: keys) == {:error, :bad_signature}

      assert Auth.verify(credential(pair, %{"sub" => " "}), keys: keys) ==
               {:error, :bad_signature}

      # JSON's "\u0000" decodes to a NUL, which no text column holds: a subject is the actor's
      # name in every row, so one with a NUL would make every request a 500 (#66).
      assert Auth.verify(credential(pair, %{"sub" => "u-anna" <> <<0>>}), keys: keys) ==
               {:error, :bad_signature}

      assert Auth.verify(credential(pair, %{"cap" => "all"}), keys: keys) ==
               {:error, :bad_signature}

      assert Auth.verify(credential(pair, %{"scp" => %{"clinic.x" => "north"}}), keys: keys) ==
               {:error, :bad_signature}
    end
  end

  describe "the tokens sign-in brings (eh-os D-64)" do
    # An ID token is signed with the credentials' key and, for an application's own
    # client, carries its audience: only the missing `cap` tells it from a credential.
    # D-64 makes that refusal a security property, so it is pinned here (S9 in
    # docs/adr/browser-session.md).
    test "an ID token presented as a bearer credential is refused", %{pair: pair, keys: keys} do
      claims = %{
        "aud" => "clinic/test",
        "auth_time" => DateTime.to_unix(DateTime.utc_now()) - 60,
        "sid" => "s-81",
        "nonce" => "n-81"
      }

      id_token = credential(pair, claims, drop: ["cap", "jti"])
      assert Auth.verify(id_token, keys: keys) == {:error, :bad_signature}

      # Control: the same claims with a `cap` are a credential.
      with_cap = credential(pair, claims, drop: ["jti"])
      assert {:ok, _} = Auth.verify(with_cap, keys: keys)
    end

    # RFC 9068 §2.2: a credential issued through sign-in names the client it was
    # issued to. The verifier ignores the claim; recording it is G-3's, later.
    test "a credential that names its client_id is accepted as it is", %{pair: pair, keys: keys} do
      token = credential(pair, %{"client_id" => "clinic-pages/test"})

      assert {:ok, %Actor{subject: "u-anna"} = actor} = Auth.verify(token, keys: keys)
      assert actor.capabilities == MapSet.new(["clinic.record_payment"])
    end
  end

  test "a credential signed by the previous key verifies while the JWKS publishes both",
       %{pair: previous, ehos: ehos, keys: keys} do
    current = key_pair()
    answer(ehos, {:keys, [current, previous]})
    :ok = EhOsContract.Auth.Keys.refresh(keys)

    assert {:ok, _} = Auth.verify(credential(previous), keys: keys)
    assert {:ok, _} = Auth.verify(credential(current), keys: keys)
  end
end

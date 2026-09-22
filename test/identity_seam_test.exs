defmodule Taxvision.IdentitySeamTest do
  @moduledoc """
  Three IAM levels on one request path, each with a different answer.

  The third level is the whole claim here: if it could be satisfied by an identity
  provider's configuration, the levels would not be separated and the whole value
  would be bought.
  """

  use Taxvision.DataCase, async: false
  use Oban.Testing, repo: Taxvision.Repo

  @params %{company_id: "c-1", period: "2026-07"}

  describe "level 1 — authentication, bought" do
    test "no token: refused" do
      assert {:error, :unauthenticated} = Taxvision.Api.open_month(nil, @params)
    end

    test "a token signed with the wrong key: refused" do
      forged =
        Base.url_encode64(~s({"sub":"someone","roles":["accounting"]}), padding: false) <>
          "." <> Base.url_encode64("an-invalid-signature", padding: false)

      assert {:error, :unauthenticated} = Taxvision.Api.open_month(forged, @params)
    end

    test "a token with an appended claim: refused, because the signature does not match" do
      valid = accountant("c-1")
      [body, mac] = String.split(valid, ".")
      {:ok, decoded} = Base.url_decode64(body, padding: false)
      tampered = String.replace(decoded, ~s("c-1"), ~s("c-2"))
      forged = Base.url_encode64(tampered, padding: false) <> "." <> mac

      assert {:error, :unauthenticated} = Taxvision.Api.open_month(forged, @params)
    end
  end

  describe "level 2 — entitlement, bought, one claim from the token" do
    test "a token without the accounting role: refused before any domain code" do
      assert {:error, :forbidden} = Taxvision.Api.open_month(client("c-1"), @params)

      # Verified by the absence of a row in the log rather than by the content of
      # the response. If the cut-off happened too late, the event would exist.
      assert Repo.aggregate(PNS.Event, :count) == 0
    end
  end

  describe "level 3 — the domain rule, ours, in the contract" do
    test "another company's accountant: a rejection with a reason, not a 403 from the provider" do
      # The role is there and entitlement passes. What stops it is the rule that
      # knows what a company and a month are — which the identity provider does
      # not.
      assert {:error, :not_this_company} = Taxvision.Api.open_month(accountant("c-2"), @params)
    end

    test "the company's own accountant: the month opens" do
      assert {:ok, correlation_id} = Taxvision.Api.open_month(accountant("c-1"), @params)

      assert [opened] = events_of(:accounting_month_opened)
      assert opened.correlation_id == correlation_id
      # `actor` carries the `sub` from the token — an opaque identifier, not an
      # email. This is the only place the log records who did it; the payload no
      # longer duplicates that.
      assert opened.actor == accountant_sub()
    end
  end

  describe "the structure of the seam" do
    test "the engine has no credentials table" do
      tables =
        Repo.query!(
          "select table_name from information_schema.tables where table_schema = 'public'"
        )
        |> Map.get(:rows)
        |> List.flatten()

      for table <- tables, column <- columns(table) do
        refute column in ~w(password password_hash hashed_password encrypted_password secret credential),
               "table #{table} has a #{column} column — the seam is broken, the engine holds credentials"
      end
    end

    test "no domain module calls token signing" do
      # `sign/1` is the first thing to disappear when a real provider takes over.
      # If the domain calls it, the swap becomes a rewrite rather than a
      # configuration change.
      callers = callers_of(:pns_prototype, {PNS.Auth.LocalToken, :sign, 1})

      # A positive control. Without it this test would pass vacuously if the
      # detector stopped working — and a test that always passes is worse than no
      # test. `Taxvision.DataCase` calls `sign/1` and has to be visible.
      assert Taxvision.DataCase in callers,
             "the call detector is not working — it cannot even see a known caller"

      domain = callers -- [PNS.Auth.LocalToken, Taxvision.DataCase]
      assert domain == [], "domain code calls token signing: #{inspect(domain)}"
    end

    test "the engine's configuration contains no vendor name" do
      config = :pns_prototype |> Application.get_all_env() |> inspect() |> String.downcase()

      for vendor <- ~w(zitadel keycloak workos auth0 okta authentik fusionauth) do
        refute config =~ vendor, "vendor name #{vendor} in the engine's configuration"
      end
    end
  end

  defp columns(table) do
    Repo.query!(
      "select column_name from information_schema.columns where table_name = $1",
      [table]
    )
    |> Map.get(:rows)
    |> List.flatten()
  end

  # Walking Erlang's abstract forms directly. The first version went through
  # `:erl_syntax_lib.fold/3` with a `rescue` at the end — and the `rescue`
  # swallowed a missing module, so the test passed vacuously. The positive control
  # above caught it.
  defp callers_of(app, mfa) do
    {:ok, modules} = :application.get_key(app, :modules)

    for caller <- modules,
        Code.ensure_loaded?(caller),
        {:ok, {_, [{:abstract_code, {:raw_abstract_v1, forms}}]}} =
          :beam_lib.chunks(:code.which(caller), [:abstract_code]),
        calls?(forms, mfa),
        do: caller
  end

  defp calls?(
         {:call, _, {:remote, _, {:atom, _, module}, {:atom, _, function}}, args},
         {module, function, arity}
       )
       when length(args) == arity,
       do: true

  defp calls?(term, mfa) when is_list(term), do: Enum.any?(term, &calls?(&1, mfa))

  defp calls?(term, mfa) when is_tuple(term),
    do: term |> Tuple.to_list() |> Enum.any?(&calls?(&1, mfa))

  defp calls?(_term, _mfa), do: false
end

defmodule Taxvision.IdentitySeamTest do
  @moduledoc """
  Trzy poziomy IAM na jednej ścieżce żądania, każdy z inną odpowiedzią.

  Test numer trzy jest tu całym twierdzeniem: gdyby dał się przejść
  konfiguracją providera tożsamości, poziomy nie byłyby rozdzielone i cała
  wartość byłaby kupiona.
  """

  use Taxvision.DataCase, async: false
  use Oban.Testing, repo: Taxvision.Repo

  @params %{company_id: "c-1", period: "2026-07"}

  describe "poziom 1 — uwierzytelnienie, kupione" do
    test "bez tokenu: odmowa" do
      assert {:error, :unauthenticated} = Taxvision.Api.open_month(nil, @params)
    end

    test "token podpisany niewłaściwym kluczem: odmowa" do
      forged =
        Base.url_encode64(~s({"sub":"ktos","roles":["accounting"]}), padding: false) <>
          "." <> Base.url_encode64("nieprawidlowy-podpis", padding: false)

      assert {:error, :unauthenticated} = Taxvision.Api.open_month(forged, @params)
    end

    test "token z doklejonym claimem: odmowa, bo podpis nie pasuje" do
      valid = accountant("c-1")
      [body, mac] = String.split(valid, ".")
      {:ok, decoded} = Base.url_decode64(body, padding: false)
      tampered = String.replace(decoded, ~s("c-1"), ~s("c-2"))
      forged = Base.url_encode64(tampered, padding: false) <> "." <> mac

      assert {:error, :unauthenticated} = Taxvision.Api.open_month(forged, @params)
    end
  end

  describe "poziom 2 — entitlement, kupione, jeden claim z tokenu" do
    test "token bez roli accounting: odmowa przed kodem domenowym" do
      assert {:error, :forbidden} = Taxvision.Api.open_month(client("c-1"), @params)

      # Weryfikowane brakiem wiersza w logu, nie treścią odpowiedzi. Gdyby
      # odcięcie nastąpiło za późno, zdarzenie już by istniało.
      assert Repo.aggregate(PNS.Event, :count) == 0
    end
  end

  describe "poziom 3 — reguła domenowa, nasza, w kontrakcie" do
    test "księgowa innej firmy: odrzucenie z powodem, nie 403 od providera" do
      # Rola jest, entitlement przechodzi. Zatrzymuje reguła, która wie, czym
      # jest firma i miesiąc — czego provider tożsamości nie wie.
      assert {:error, :not_this_company} = Taxvision.Api.open_month(accountant("c-2"), @params)
    end

    test "księgowa własnej firmy: miesiąc się otwiera" do
      assert {:ok, correlation_id} = Taxvision.Api.open_month(accountant("c-1"), @params)

      assert [opened] = events_of(:accounting_month_opened)
      assert opened.correlation_id == correlation_id
      # `actor` niesie `sub` z tokenu — nieprzezroczysty identyfikator, nie mail.
      # To jedyne miejsce, w którym log zapisuje, kto to zrobił; payload już
      # tego nie duplikuje.
      assert opened.actor == accountant_sub()
    end
  end

  describe "struktura szwu" do
    test "silnik nie ma tabeli z credentialami" do
      tables =
        Repo.query!("select table_name from information_schema.tables where table_schema = 'public'")
        |> Map.get(:rows)
        |> List.flatten()

      for table <- tables, column <- columns(table) do
        refute column in ~w(password password_hash hashed_password encrypted_password secret credential),
               "tabela #{table} ma kolumnę #{column} — szew złamany, silnik trzyma credentiale"
      end
    end

    test "żaden moduł domenowy nie woła podpisywania tokenów" do
      # `sign/1` jest pierwszą rzeczą, która znika przy podmianie na
      # prawdziwego providera. Jeśli domena jej woła, podmiana będzie
      # przepisaniem, a nie zmianą konfiguracji.
      callers = callers_of(:pns_prototype, {PNS.Auth.LocalToken, :sign, 1})

      # Kontrola dodatnia. Bez niej ten test przechodziłby pusto, gdyby detektor
      # przestał działać — a test, który zawsze przechodzi, jest gorszy niż jego
      # brak. `Taxvision.DataCase` woła `sign/1` i musi być widoczny.
      assert Taxvision.DataCase in callers,
             "detektor wywołań nie działa — nie widzi nawet znanego wołającego"

      domain = callers -- [PNS.Auth.LocalToken, Taxvision.DataCase]
      assert domain == [], "podpisywanie tokenów woła kod domenowy: #{inspect(domain)}"
    end

    test "konfiguracja silnika nie zawiera nazwy vendora" do
      config = :pns_prototype |> Application.get_all_env() |> inspect() |> String.downcase()

      for vendor <- ~w(zitadel keycloak workos auth0 okta authentik fusionauth) do
        refute config =~ vendor, "nazwa vendora #{vendor} w konfiguracji silnika"
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

  # Chodzenie po formach abstrakcyjnych Erlanga wprost. Pierwsza wersja szła
  # przez `:erl_syntax_lib.fold/3` z `rescue` na końcu — i `rescue` zjadał to,
  # że modułu nie ma, przez co test przechodził pusto. Kontrola dodatnia wyżej
  # to wyłapała.
  defp callers_of(app, mfa) do
    {:ok, modules} = :application.get_key(app, :modules)

    for caller <- modules,
        Code.ensure_loaded?(caller),
        {:ok, {_, [{:abstract_code, {:raw_abstract_v1, forms}}]}} =
          :beam_lib.chunks(:code.which(caller), [:abstract_code]),
        calls?(forms, mfa),
        do: caller
  end

  defp calls?({:call, _, {:remote, _, {:atom, _, module}, {:atom, _, function}}, args}, {module, function, arity})
       when length(args) == arity,
       do: true

  defp calls?(term, mfa) when is_list(term), do: Enum.any?(term, &calls?(&1, mfa))

  defp calls?(term, mfa) when is_tuple(term),
    do: term |> Tuple.to_list() |> Enum.any?(&calls?(&1, mfa))

  defp calls?(_term, _mfa), do: false
end

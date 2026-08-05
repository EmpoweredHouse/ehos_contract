defmodule PNS.InstanceTest do
  @moduledoc """
  Kryterium odbioru etapu 1.1: **assercja policzona dla dwóch równoległych
  przebiegów nie myli ich zdarzeń.**

  Ten plik jest napisany tak, żeby pokazać różnicę, a nie tylko sprawdzić nowy
  licznik. W każdym teście, w którym to ma sens, obok wyniku per przebieg stoi
  wynik per typ zdarzenia — czyli to, co silnik liczył przed tym etapem. Bez
  tego zestawienia „licznik pokazuje 1" jest liczbą bez znaczenia.
  """

  use Taxvision.DataCase, async: false

  alias Taxvision.Contracts.AccountingMonth

  @zgodne %{legal_form: "JDG", vat_status: "czynny", vies_status: "aktywny"}
  @rozjazd %{legal_form: "JDG", vat_status: "wykreślony", vies_status: "aktywny"}

  defp rejestry(mapa) do
    Application.put_env(:pns_prototype, Taxvision.Adapters.RegistryLookup.Fake, responses: mapa)
    on_exit(fn -> Application.delete_env(:pns_prototype, Taxvision.Adapters.RegistryLookup.Fake) end)
  end

  defp instancja(company_id, period), do: "accounting_month|#{company_id}|#{period}"

  describe "tożsamość przebiegu w logu" do
    test "klucz przebiegu pochodzi z `instance:` i jest zapisany na zdarzeniu" do
      {:ok, _} = Taxvision.Api.open_month(accountant("c-1"), %{company_id: "c-1", period: "2026-07"})

      event = List.first(events_of(:data_completeness_confirmed))

      assert event.process == "accounting_month"
      assert event.instance_id == instancja("c-1", "2026-07")
    end

    test "wszystkie zdarzenia jednej komendy trafiają do jednego przebiegu" do
      {:ok, _} = Taxvision.Api.open_month(accountant("c-1"), %{company_id: "c-1", period: "2026-07"})

      instancje = Repo.all(from e in PNS.Event, select: e.instance_id) |> Enum.uniq()

      assert instancje == [instancja("c-1", "2026-07")]
    end

    test "ta sama firma w dwóch miesiącach to dwa przebiegi, nie jeden" do
      # `correlation_id` odpowiedziałoby tu tak samo, bo to dwie komendy. Ale
      # jedna komenda otwierająca dwa miesiące też dałaby dwa przebiegi, a jeden
      # miesiąc otwierany dwiema komendami — jeden. To są różne pytania.
      for period <- ["2026-06", "2026-07"] do
        {:ok, _} = Taxvision.Api.open_month(accountant("c-1"), %{company_id: "c-1", period: period})
      end

      instancje = Repo.all(from e in PNS.Event, select: e.instance_id) |> Enum.uniq() |> Enum.sort()

      assert instancje == [instancja("c-1", "2026-06"), instancja("c-1", "2026-07")]
    end

    test "zdarzenie bez pola instancji nie wchodzi do logu" do
      # Brama kompilacyjna pilnuje, że pole jest **zadeklarowane**. Że zostało
      # podane, pilnuje dopiero to — a bez tego zdarzenie wpadłoby do logu z
      # pustym segmentem klucza i zlało się z przebiegiem innej firmy.
      assert_raise ArgumentError, ~r/nie niesie pola instancji :period/, fn ->
        PNS.emit(AccountingMonth, :registry_data_consistent, %{company_id: "c-1"})
      end

      assert events_of(:registry_data_consistent) == []
    end
  end

  describe "dwa równoległe przebiegi" do
    setup do
      # c-1 przechodzi weryfikację, c-2 nie. Oba przebiegi startują tym samym
      # zdarzeniem, więc per typ zdarzenia są nie do odróżnienia.
      rejestry(%{"c-1" => {:ok, @zgodne}, "c-2" => {:ok, @rozjazd}})

      for company <- ["c-1", "c-2"] do
        {:ok, _} = Taxvision.Api.open_month(accountant(company), %{company_id: company, period: "2026-07"})
      end

      :ok
    end

    test "assercja „po X ostatecznie Y” jest prawdziwa dla jednego przebiegu, nie dla obu" do
      # To jest cały powód, dla którego etap 1.1 stoi przed oceną assercji.
      # Assercja `month_opens_or_is_blocked` mówi: po potwierdzeniu kompletu
      # danych miesiąc się otwiera **albo** idzie powiadomienie o rozjeździe.
      c1 = PNS.Graph.observed(instance: instancja("c-1", "2026-07")).nodes
      c2 = PNS.Graph.observed(instance: instancja("c-2", "2026-07")).nodes

      assert Map.has_key?(c1, "data_completeness_confirmed")
      assert Map.has_key?(c2, "data_completeness_confirmed")

      assert Map.has_key?(c1, "accounting_month_opened")
      refute Map.has_key?(c2, "accounting_month_opened")

      # A tak wygląda ta sama assercja policzona per typ zdarzenia, czyli tak,
      # jak silnik liczył przed tym etapem: „`accounting_month_opened` zaszło
      # po `data_completeness_confirmed`" jest **prawdą globalnie** i zaliczyłoby
      # przebieg c-2, który się nie otworzył.
      globalnie = PNS.Graph.observed().nodes
      assert globalnie["data_completeness_confirmed"].count == 2
      assert globalnie["accounting_month_opened"].count == 1
    end

    test "licznik na krawędzi ma dwa wymiary: wystąpienia i przebiegi" do
      overlay = PNS.Graph.overlay()
      edge = Enum.find(overlay, &(&1.to == :accounting_month_opened))

      # Krawędź jest `confirmed`, bo ktoś nią przejechał. I dokładnie to jest
      # ukryta cisza: przejechał **jeden z dwóch** przebiegów.
      assert edge.state == :confirmed
      assert edge.count == 1
      assert edge.instances == 1
      assert edge.of_instances == 2
    end

    test "zdarzenie powtórzone w jednym przebiegu podnosi wystąpienia, nie przebiegi" do
      # Wystąpienia rosną, przebiegi nie. Wersja bez tego rozróżnienia czytała
      # jedną firmę powtarzającą operację jako pokrycie całej populacji.
      #
      # Ponowne sprawdzenie rejestrów w otwartym już miesiącu jest legalne i
      # niczego nie kaskaduje — dlatego to na nim, a nie na krawędzi otwierającej
      # miesiąc, którą niezmiennik agregatu słusznie przepuszcza tylko raz.
      PNS.emit!(AccountingMonth, :registry_status_checked, %{
        company_id: "c-1",
        period: "2026-07",
        checked_at: DateTime.utc_now() |> DateTime.to_iso8601()
      })

      node = PNS.Graph.observed().nodes["registry_status_checked"]

      assert node.count == 3
      assert node.instances == 2
    end

    test "liczba przebiegów procesu jest liczbą, nie listą firm" do
      # Świadomie. „Która firma nie ma otwartego lipca" to pytanie aplikacji
      # klienta; PNS odpowiada na pytanie o ścieżkę.
      assert PNS.Graph.process_instances() == %{"accounting_month" => 2}
    end
  end
end

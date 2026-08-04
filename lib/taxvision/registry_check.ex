defmodule Taxvision.RegistryCheck do
  @moduledoc """
  Logika biznesowa jest czystą funkcją: komenda wchodzi, błąd albo lista
  zdarzeń wychodzi. Efekty uboczne żyją tylko w handlerach.

  Testowalne bez żadnego setupu — i to jest kształt, który model generuje
  najpewniej: ograniczone wejście, jawne reguły, jawne wyjście, brak środowiska.

  Adapter rejestrów jest wołany **poza** tą funkcją. Gdyby był w środku,
  sprawdzenie nie umiałoby odróżnić "złamaliśmy regułę" od "rejestr był
  niedostępny", a dla klienta księgowego to jest całe pytanie (ADR §11-12).
  """

  use Boundary, deps: [PNS], exports: []

  @doc """
  Polityka P1 z warsztatu: kiedy zaczyna się miesiąc, sprawdź rejestry; kiedy
  dane zgodne, wygeneruj taski; kiedy niezgodne, zablokuj i powiadom.

  Warunkiem wstawienia szablonu jest brak rozjazdu statusu prawnego
  [WF 00:35:41].
  """
  def decide(%{command: :open_month} = input) do
    %{company_id: company_id, period: period} = input

    base = %{company_id: company_id, period: period}
    checked_at = input[:checked_at] || "1970-01-01T00:00:00Z"

    cond do
      not input.completeness_confirmed ->
        {:error, :data_completeness_not_confirmed}

      true ->
        prefix = [
          PNS.event(:data_completeness_confirmed, Map.put(base, :confirmed_by, input[:actor] || "unknown")),
          PNS.event(:registry_status_checked, Map.put(base, :checked_at, checked_at)),
          PNS.event(:registry_check_logged, Map.put(base, :checked_at, checked_at))
        ]

        case diff(input.abilia, input.registries) do
          [] ->
            prefix ++ [PNS.event(:registry_data_consistent, base)]

          differences ->
            # System pokazuje diff "to mamy w Abilii, to mówią systemy"
            # [WF 00:32:27].
            prefix ++ [PNS.event(:registry_discrepancy_detected, Map.put(base, :diff, render(differences)))]
        end
    end
  end

  @doc "Rozjazdy między tym, co mamy u siebie, a tym, co mówią rejestry."
  def diff(abilia, registries) do
    for {field, registry_field} <- [legal_form: :legal_form, vat_status: :vat_status],
        ours = Map.get(abilia, field),
        theirs = Map.get(registries, registry_field),
        ours != theirs do
      {field, ours, theirs}
    end
  end

  defp render(differences) do
    Enum.map_join(differences, "; ", fn {field, ours, theirs} ->
      "#{field}: Abilia=#{ours}, rejestry=#{theirs}"
    end)
  end
end

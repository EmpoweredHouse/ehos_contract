defmodule PNS.Trace do
  @moduledoc """
  Ocena assercji `trace` **per przebieg**.

  To jest pierwszy moment, w którym cokolwiek w runtime **czyta** `trace`. Do
  teraz assercja była zadeklarowana w kontrakcie i sprawdzana wyłącznie pod tym
  kątem, czy nazwy zdarzeń istnieją — czyli była prozą w składni Elixira. Log
  wiedział, co się stało; nikt nie pytał, czy to zgadza się z umową.

  Assercja czyta się tak:

      trace :month_opens_or_is_blocked do
        from :data_completeness_confirmed
        eventually :accounting_month_opened, within: {2, :day}
        or_else :discrepancy_notification_sent
      end

  *„Po potwierdzeniu kompletu danych, w ciągu dwóch dni miesiąc się otwiera albo
  idzie powiadomienie o rozjeździe."*

  ## Trzy werdykty, i czwarty którego jeszcze nie ma

  | Werdykt | Znaczenie |
  |---|---|
  | `:satisfied` | doszło do `eventually` **albo** do `or_else` w oknie |
  | `:violated` | okno minęło i nie doszło do żadnego z nich |
  | `:pending` | okno jeszcze nie minęło — nic jeszcze nie wiadomo |

  **`:satisfied` niesie `via:`** — `:eventually` albo `:or_else`. To jest cała
  subtelność tej assercji i najłatwiej ją zepsuć: zablokowanie miesiąca jest
  **poprawnym zakończeniem**, tylko nie takim, jak chcieliśmy. Werdykt musi
  brzmieć „spełniona", a raport ma umieć powiedzieć, którą drogą — bo narzędzie
  krzyczące na każdy poprawnie zablokowany miesiąc zostanie wyłączone w tydzień.

  Czwartego werdyktu — `:suspended`, okno niedostępności adaptera — **tu nie ma i
  nie da się go policzyć**: nic w systemie nie zapisuje, że zależność zewnętrzna
  była niedostępna. `unavailable_looks_like` w kontrakcie jest dziś zdaniem,
  którego nikt nie czyta. Szczegóły i warunek wstępny — w `PLAN.md`, etap 1.5b.
  Do tego czasu awaria rejestru w oknie assercji policzy się jako `:violated`,
  czyli obwinimy klienta za cudzy serwer. To jest znane i zapisane, nie ukryte.

  ## Trzy decyzje, które mają zęby

  **Okno liczy się od pierwszego wystąpienia `from`, nie od ostatniego.** Gdyby
  od ostatniego, proces mógłby uciekać przed terminem w nieskończoność, po prostu
  emitując `from` ponownie — assercja nie dałaby się naruszyć. Przy ponownym
  sprawdzeniu rejestrów to nie jest przypadek teoretyczny.

  **`within` obowiązuje także `or_else`.** „W ciągu dwóch dni X albo Y" znaczy, że
  oba mają się zmieścić. Wariant, w którym `or_else` nie ma terminu, czyni termin
  bezużytecznym: proces zakończony poprawnie, ale trzy miesiące później, byłby
  „spełniony". To jest jednak **decyzja process ownera**, nie nasza, i pierwsza
  do potwierdzenia przy tej assercji.

  **Assercja jest warunkowa: przebieg bez `from` nie jest oceniany.** Nie jest ani
  spełniony, ani naruszony — nie ma o czym orzekać. Liczenie go jako naruszenia
  zrobiłoby z każdej niezaczętej sprawy alarm.

  ## Granica raportu

  `evaluate/3` zwraca werdykty **per przebieg**, bo tylko tak da się je policzyć
  poprawnie i tylko tak da się je przetestować. Notatki §9 przewidują też widok
  jednego przebiegu — do debugowania, „co się stało z fakturą 4712".

  Ale **raport agreguje do liczb** (`summary/1`). „Która firma nie ma otwartego
  lipca" jest pytaniem o stan biznesu i należy do aplikacji klienta; PNS
  odpowiada na pytanie o assercję.
  """

  import Ecto.Query

  @repo Application.compile_env!(:pns_prototype, :repo)

  alias PNS.Event

  @doc """
  Werdykty dla wszystkich przebiegów, w których doszło do `from` tej assercji.

  `now:` pozwala ocenić assercję w zadanym momencie — bez tego różnica między
  `:pending` i `:violated` nie dałaby się przetestować.
  """
  def evaluate(contract, trace_name, opts \\ []) do
    trace =
      Enum.find(contract.traces(), &(&1.name == trace_name)) ||
        raise ArgumentError, "#{inspect(contract)} nie deklaruje assercji #{inspect(trace_name)}"

    now = Keyword.get(opts, :now) || DateTime.utc_now()
    from_type = to_string(trace.from)

    contract
    |> occurrences(trace, opts)
    |> Enum.flat_map(fn {instance_id, by_type} ->
      case Map.get(by_type, from_type) do
        # Przebieg bez `from` nie jest oceniany — assercja jest warunkowa.
        nil -> []
        times -> [verdict(trace, instance_id, Enum.min(times, DateTime), by_type, now)]
      end
    end)
    |> Enum.sort_by(& &1.from_at, DateTime)
  end

  @doc "Werdykty dla każdej assercji z każdego zarejestrowanego kontraktu."
  def evaluate_all(opts \\ []) do
    for contract <- PNS.Registry.contracts(), trace <- contract.traces() do
      %{
        contract: contract,
        trace: trace.name,
        verdicts: evaluate(contract, trace.name, opts)
      }
    end
  end

  @doc """
  Zwinięcie werdyktów do liczb — to jest kształt, który idzie do raportu.

  `satisfied` rozbite po `via`, bo „spełniona przez `or_else`" to inna
  informacja biznesowa niż „spełniona przez `eventually`", mimo tego samego
  werdyktu: w obu przypadkach umowa jest dotrzymana, ale w jednym miesiąc się
  otworzył, a w drugim stanął.
  """
  def summary(verdicts) do
    %{
      satisfied: count(verdicts, &(&1.verdict == :satisfied)),
      satisfied_via_eventually: count(verdicts, &(&1.via == :eventually)),
      satisfied_via_or_else: count(verdicts, &(&1.via == :or_else)),
      violated: count(verdicts, &(&1.verdict == :violated)),
      pending: count(verdicts, &(&1.verdict == :pending)),
      instances: length(verdicts)
    }
  end

  defp count(verdicts, fun), do: Enum.count(verdicts, fun)

  defp verdict(trace, instance_id, from_at, by_type, now) do
    deadline_at = trace.within && PNS.Duration.shift(from_at, trace.within)
    hit = fn name -> name && first_at_or_after(by_type[to_string(name)], from_at) end

    eventually_at = hit.(trace.eventually)
    or_else_at = hit.(trace.or_else)

    {verdict, via, at} =
      cond do
        in_window?(eventually_at, deadline_at) -> {:satisfied, :eventually, eventually_at}
        in_window?(or_else_at, deadline_at) -> {:satisfied, :or_else, or_else_at}
        pending?(deadline_at, now) -> {:pending, nil, nil}
        true -> {:violated, nil, nil}
      end

    %{
      instance_id: instance_id,
      verdict: verdict,
      via: via,
      from_at: from_at,
      deadline_at: deadline_at,
      resolved_at: at
    }
  end

  defp in_window?(nil, _deadline_at), do: false
  # Assercja bez `within` nie ma terminu, więc nie da się jej naruszyć — dowolne
  # wystąpienie ją spełnia. Taka assercja jest niefalsyfikowalna i to jest
  # zapisane w PLAN.md jako kandydat na `info` w `pns.check`.
  defp in_window?(_at, nil), do: true
  defp in_window?(at, deadline_at), do: DateTime.compare(at, deadline_at) != :gt

  defp pending?(nil, _now), do: true
  defp pending?(deadline_at, now), do: DateTime.compare(now, deadline_at) == :lt

  defp first_at_or_after(nil, _from_at), do: nil

  defp first_at_or_after(times, from_at) do
    times
    |> Enum.filter(&(DateTime.compare(&1, from_at) != :lt))
    |> Enum.min(DateTime, fn -> nil end)
  end

  defp occurrences(contract, trace, opts) do
    types =
      [trace.from, trace.eventually, trace.or_else]
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&to_string/1)

    query =
      from(e in Event,
        where: e.contract == ^inspect(contract),
        where: e.type in ^types,
        where: not is_nil(e.instance_id),
        select: {e.instance_id, e.type, e.occurred_at}
      )

    query
    |> maybe_since(Keyword.get(opts, :since))
    |> maybe_instance(Keyword.get(opts, :instance))
    |> repo().all()
    |> Enum.group_by(fn {instance, _t, _at} -> instance end, fn {_i, type, at} -> {type, at} end)
    |> Map.new(fn {instance, pairs} ->
      {instance, Enum.group_by(pairs, &elem(&1, 0), &elem(&1, 1))}
    end)
  end

  defp maybe_since(query, nil), do: query
  defp maybe_since(query, since), do: where(query, [e], e.occurred_at >= ^since)

  defp maybe_instance(query, nil), do: query
  defp maybe_instance(query, id), do: where(query, [e], e.instance_id == ^id)

  defp repo, do: @repo
end

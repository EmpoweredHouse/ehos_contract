defmodule PNS.ProcessShapesTest do
  @moduledoc """
  Etap 1.3: **kształty procesu, zasymulowane.**

  Kryterium odbioru ma dwie połowy i druga jest ważniejsza: `pns.check` **zgłasza**
  krawędź wsteczną przy domykaniu pary i **nie zgłasza** jej tam, gdzie jej nie
  ma. Sam fakt, że check znajduje przypadek zbudowany pod niego, nie dowodzi
  niczego — dowodem jest milczenie na trzech kontrolach.

  Stanowisko badawcze (`ProcessShapes.Rig`) jest jawnie **nie domeną**. Kształty
  pochodzą z tabeli w planie produktowym, nie z mojej wyobraźni; nazwy są
  bezbarwne, żeby nikt nie przeczytał ich jako wiedzy o czyimś procesie.
  """

  use Taxvision.DataCase, async: false

  alias ProcessShapes.Rig

  defp wplyw(case_id, item_no, amount) do
    PNS.emit!(Rig, :item_received, %{case_id: case_id, item_no: item_no, amount: amount})
  end

  defp typy(case_id) do
    instancja = "pairing|#{case_id}"

    Repo.all(
      from e in PNS.Event,
        where: e.instance_id == ^instancja,
        order_by: e.occurred_at,
        select: e.type
    )
  end

  describe "kryterium odbioru: krawędź wsteczna" do
    test "check zgłasza dokładnie jedną krawędź wsteczną — tę przy domykaniu pary" do
      krawedzie = PNS.Check.backward_edges()
      w_rigu = Enum.filter(krawedzie, &(&1.process == :pairing))

      assert [edge] = w_rigu
      assert edge.module == ProcessShapes.Resolution.OnClarificationAnswered
      assert edge.subscribes_in == :resolution
      assert edge.publishes_in == :matching
    end

    test "i milczy na trzech modułach, które publikują do przodu" do
      # To jest właściwa połowa kryterium. Check, który zgłasza wszystko, jest
      # tak samo bezużyteczny jak check, który nie zgłasza nic.
      zgloszone = PNS.Check.backward_edges() |> Enum.map(& &1.module)

      refute ProcessShapes.Intake.OnItemReceived in zgloszone
      refute ProcessShapes.Matching.OnPairingUnresolved in zgloszone
      refute ProcessShapes.Matching.OnItemPaired in zgloszone
    end

    test "krawędź wsteczna jest liczona po fazach, nie po pozycji zdarzenia" do
      # Dwa zdarzenia tej samej fazy nigdy nie są krawędzią wsteczną, bo kontrakt
      # nie twierdzi nic o kolejności wewnątrz fazy. `OnItemPaired` subskrybuje
      # `item_paired` z `matching` i publikuje `case_closed` z `resolution` —
      # gdyby check liczył po pozycji w liście, zgłosiłby tu fałszywy alarm.
      assert Rig.event(:item_paired).stage == :matching
      assert Rig.event(:case_closed).stage == :resolution
      refute ProcessShapes.Matching.OnItemPaired in Enum.map(PNS.Check.backward_edges(), & &1.module)
    end
  end

  describe "krok, który się cofa — w runtime, nie tylko w checku" do
    test "para domyka się po wyjaśnieniu i przebieg wraca do fazy `matching`" do
      wplyw("c-1", 1, 0)

      assert typy("c-1") == ~w(item_received pairing_unresolved clarification_requested)

      # Wyjaśnienie wchodzi **bez komendy**, z zewnątrz. Domyka parę wstecz.
      PNS.emit!(Rig, :clarification_answered, %{case_id: "c-1", item_no: 1})

      assert typy("c-1") ==
               ~w(item_received pairing_unresolved clarification_requested
                  clarification_answered item_paired case_closed)
    end
  end

  describe "to samo zdarzenie wiele razy w jednym przebiegu" do
    test "trzy pozycje to trzy fakty w jednym przebiegu, nie trzy przebiegi" do
      for n <- 1..3, do: wplyw("c-1", n, 100)

      przebiegi = PNS.Graph.process_instances()
      wezel = PNS.Graph.observed().nodes["item_paired"]

      assert przebiegi["pairing"] == 1
      assert wezel.count == 3
      assert wezel.instances == 1
    end

    test "handler liczy po tożsamości przebiegu, nie po typie zdarzenia" do
      # Gdyby liczył per typ, pozycje drugiej sprawy dopisałyby się do pierwszej
      # — czyli ten sam błąd, który etap 1.1 naprawiał w nakładce, popełniony
      # wewnątrz handlera.
      for n <- 1..2, do: wplyw("c-1", n, 100)
      for n <- 1..5, do: wplyw("c-2", n, 100)

      assert ProcessShapes.Matching.count("c-1", "item_paired") == 2
      assert ProcessShapes.Matching.count("c-2", "item_paired") == 5
    end
  end

  describe "zdarzenie wchodzące bez komendy" do
    test "nie ma aktora, a mimo to ma tożsamość przebiegu" do
      zdarzenie = wplyw("c-1", 1, 100)

      assert zdarzenie.actor == nil, "nikt tego nie wywołał — nie ma komu przypisać"
      assert zdarzenie.instance_id == "pairing|c-1"
      assert zdarzenie.causation_id == nil
    end

    test "aktor jako `nil` nie odróżnia „import” od „nie wiemy kto”" do
      # Znane i zapisane: sensowna wersja postulatu „każde zdarzenie ma aktora"
      # to nie „wymagany", a „nigdy cisza" — czyli jawny aktor systemowy.
      # Do rozstrzygnięcia, patrz PLAN.md.
      assert wplyw("c-1", 1, 100).actor == nil
    end
  end
end

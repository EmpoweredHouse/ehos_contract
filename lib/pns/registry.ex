defmodule PNS.Registry do
  @moduledoc """
  Rejestr handlerów i kontraktów (notatki §2).

  Nie generowany moduł z całym grafem — makro per-moduł nie umie tego
  zaaranżować, bo wymagałoby, żeby wszystkie handlery były już skompilowane.
  Zamiast tego marker `__pns_handler__/0` plus skan przy boocie.

  Ta własność jest cała: **graf pochodzi z binarki, która faktycznie działa.**
  """

  @key {__MODULE__, :graph}

  @doc "Skanuje aplikację i cache'uje wynik w `:persistent_term`."
  def load!(app \\ :pns_prototype) do
    {:ok, modules} = :application.get_key(app, :modules)

    # `Code.ensure_loaded?` jest potrzebne, bo w dev moduły ładują się leniwie;
    # release w trybie `:embedded` ma je wszystkie.
    loaded = Enum.filter(modules, &Code.ensure_loaded?/1)

    handlers =
      loaded
      |> Enum.filter(&function_exported?(&1, :__pns_handler__, 0))
      |> Enum.map(& &1.__pns_handler__())

    contracts =
      loaded
      |> Enum.filter(&function_exported?(&1, :__pns_contract__, 0))

    graph = %{handlers: handlers, contracts: contracts}
    :persistent_term.put(@key, graph)
    graph
  end

  def graph do
    case :persistent_term.get(@key, nil) do
      nil -> load!()
      graph -> graph
    end
  end

  def handlers, do: graph().handlers
  def contracts, do: graph().contracts

  def sync_handlers_for(event), do: for(h <- handlers(), h.event == event, not h.async, do: h)
  def async_handlers_for(event), do: for(h <- handlers(), h.event == event, h.async, do: h)
  def handlers_for(event), do: for(h <- handlers(), h.event == event, do: h)

  @doc """
  Krawędzie grafu statycznego: zdarzenie wejściowe -> handler -> zdarzenia
  publikowane. To jest to, co dashboard nakłada na log (notatki §9).
  """
  def edges do
    for h <- handlers(), published <- h.publishes do
      %{from: h.event, to: published, handler: h.module, async: h.async}
    end
  end

  @doc "Zdarzenia zadeklarowane we wszystkich kontraktach."
  def declared_events do
    for contract <- contracts(), event <- contract.events() do
      Map.put(event, :contract, contract)
    end
  end
end

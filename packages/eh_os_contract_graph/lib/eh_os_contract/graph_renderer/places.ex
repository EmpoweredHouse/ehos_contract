defmodule EhOsContract.GraphRenderer.Places do
  # Where the explorer can go, and where a card leads: plan DD, stage G1 (#297), the two
  # viewpoints of the user's decision of 15 October. A place of the structure is the
  # domain's system, a contract's full graph, or one of its units; a place of the processes
  # is their list, or one process module's picture.
  @moduledoc false

  @type t ::
          :domain
          | {:contract, String.t()}
          | {:unit, String.t(), String.t()}
          | :processes
          | {:process, String.t()}

  @doc "The document a place is drawn from, as a loader names it; none for the list of processes."
  @spec ref(t(), String.t()) :: EhOsContract.GraphRenderer.Loader.ref() | nil
  def ref(:domain, domain), do: {:domain, domain}
  def ref(:processes, domain), do: {:domain, domain}
  def ref({:contract, id}, _domain), do: {:contract, id}
  def ref({:unit, contract, _unit}, _domain), do: {:contract, contract}
  def ref({:process, id}, _domain), do: {:process, id}

  @doc "Which of the two viewpoints a place is of."
  @spec tab(t()) :: :structure | :processes
  def tab(:processes), do: :processes
  def tab({:process, _id}), do: :processes
  def tab(_place), do: :structure

  @doc """
  Where the card of `kind` and `node`, drawn from `document`, leads, with the words of the
  button that goes there; nil where it leads nowhere it is not already. A contract or a
  process of the domain's map opens it; a unit of a contract opens it; an event opens the
  unit or the contract it is declared in.
  """
  @spec destination(map(), String.t(), map()) :: {t(), String.t()} | nil
  def destination(%{"kind" => "domain"}, "contract", %{"name" => id}),
    do: {{:contract, id}, "Open this contract"}

  def destination(%{"kind" => "domain"}, "process", %{"name" => id}),
    do: {{:process, id}, "Open this process"}

  def destination(%{"kind" => "contract", "contract" => c}, "unit", %{"id" => id}),
    do: {{:unit, c, id}, "Open this unit"}

  def destination(%{"kind" => "contract", "contract" => c}, "event", %{"unit" => unit})
      when is_binary(unit),
      do: {{:unit, c, unit}, "Open its unit"}

  def destination(%{"kind" => "contract"}, "event", %{"declared_as" => "event:" <> declared}) do
    case String.split(declared, ":") do
      [contract, _ | _] when contract != "" -> {{:contract, contract}, "Open its contract"}
      _malformed -> nil
    end
  end

  def destination(%{"kind" => "process"} = document, "event", %{"contract" => contract}) do
    case Enum.find(get_in(document, ["nodes", "contract"]) || [], &(&1["id"] == contract)) do
      %{"name" => id} -> {{:contract, id}, "Open its contract"}
      nil -> nil
    end
  end

  def destination(_document, _kind, _node), do: nil
end

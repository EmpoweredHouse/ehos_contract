defmodule EhOsContract.GraphRenderer.Places do
  # Where the explorer can go, and where a card leads: plan DD, stage G1 (#297), the two
  # viewpoints of the user's decision of 15 October. A place of the structure is the
  # domain's system, a contract's full graph, or one of its units; a place of the processes
  # is their list, or one process module's picture. A landscape's box and the contracts in it
  # lead out of the landscape, to a page of the host's (#404).
  @moduledoc false

  @type t ::
          :domain
          | {:contract, String.t()}
          | {:unit, String.t(), String.t()}
          | :processes
          | {:process, String.t()}

  @typedoc """
  Where a landscape's box or a contract in it leads: the host's page of that domain, or of
  the application, with no domain, for the box of one the landscape has no document of.
  """
  @type outside ::
          {:outside, application :: String.t(), domain :: String.t() | nil, String.t() | nil}

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
  unit or the contract it is declared in. A landscape's box opens its domain, and a contract
  in it that contract, outside the landscape: on the host's page, when it has one; the box
  of an application the landscape has no document of opens the application.
  """
  @spec destination(map(), String.t(), map()) :: {t() | outside(), String.t()} | nil
  def destination(%{"kind" => "landscape"}, "domain", %{"application" => a, "domain" => d})
      when is_binary(a) and is_binary(d),
      do: {{:outside, a, d, nil}, "Open this domain"}

  def destination(%{"kind" => "landscape"}, "application", %{"application" => a})
      when is_binary(a),
      do: {{:outside, a, nil, nil}, "Open this application"}

  def destination(%{"kind" => "landscape"} = document, "contract", %{"in" => box, "name" => id})
      when is_binary(id) do
    case Enum.find(get_in(document, ["nodes", "domain"]) || [], &(&1["id"] == box)) do
      %{"application" => a, "domain" => d} when is_binary(a) and is_binary(d) ->
        {{:outside, a, d, id}, "Open this contract"}

      _none ->
        nil
    end
  end

  def destination(%{"kind" => "domain"}, "contract", %{"name" => id}),
    do: {{:contract, id}, "Open this contract"}

  def destination(%{"kind" => "domain"}, "process", %{"name" => id}),
    do: {{:process, id}, "Open this process"}

  def destination(%{"kind" => "contract", "contract" => c}, "unit", %{"id" => id}),
    do: {{:unit, c, id}, "Open this unit"}

  def destination(%{"kind" => "contract", "contract" => c}, "event", %{"unit" => unit})
      when is_binary(unit),
      do: {{:unit, c, unit}, "Open its unit"}

  def destination(%{"kind" => "contract"}, "event", node) do
    case declared_in(node) do
      nil -> nil
      contract -> {{:contract, contract}, "Open its contract"}
    end
  end

  def destination(%{"kind" => "process"} = document, "event", %{"contract" => contract}) do
    case Enum.find(get_in(document, ["nodes", "contract"]) || [], &(&1["id"] == contract)) do
      %{"name" => id} -> {{:contract, id}, "Open its contract"}
      nil -> nil
    end
  end

  def destination(_document, _kind, _node), do: nil

  @doc """
  The sibling contract an event of a contract's document is consumed from: its
  `declared_in`, or, in a document from before it, the contract its `declared_as` id
  names; nil for the contract's own event, a received one, or an id that names none.
  """
  @spec declared_in(map()) :: String.t() | nil
  def declared_in(%{"declared_in" => contract}) when is_binary(contract) and contract != "",
    do: contract

  def declared_in(%{"declared_as" => "event:" <> declared}) do
    case String.split(declared, ":") do
      [contract, _ | _] when contract != "" -> contract
      _malformed -> nil
    end
  end

  def declared_in(_node), do: nil
end

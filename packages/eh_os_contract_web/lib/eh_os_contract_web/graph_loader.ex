defmodule EhOsContract.Web.GraphLoader do
  # Plan DD, stage G1 (#297): the dashboard's loader for the renderer's explorer, over the
  # engine in the same application — the same documents and overlays `GET <mount>/graph/…`
  # serves (`EhOsContract.Web.Api.Graph`), each built only when the reader enters it.
  @moduledoc false

  @behaviour EhOsContract.GraphRenderer.Loader

  alias EhOsContract.Graph.{Document, Overlay}
  alias EhOsContract.Registry

  @impl true
  def document({:domain, name}, _opts),
    do: with_domain(name, &Document.domain(&1, modules()))

  def document({:contract, id}, _opts),
    do: with_module(Registry.contract(id), &Document.contract/1)

  def document({:process, id}, _opts), do: with_module(Registry.process(id), &Document.process/1)

  @impl true
  def overlay({:domain, name}, _opts), do: with_domain(name, &Overlay.domain(&1, modules()))
  def overlay({:contract, id}, _opts), do: with_module(Registry.contract(id), &Overlay.contract/1)
  def overlay({:process, id}, _opts), do: with_module(Registry.process(id), &Overlay.process/1)

  # The domain's document and overlay name the process modules beside the contracts, as the
  # API's do, so one digest names them.
  defp modules, do: Registry.contracts() ++ Registry.processes()

  defp with_domain(name, build) do
    case Enum.find(Registry.domains(), &(inspect(&1) == name)) do
      nil -> {:error, :not_found}
      domain -> {:ok, build.(domain)}
    end
  end

  defp with_module(nil, _build), do: {:error, :not_found}
  defp with_module(module, build), do: {:ok, build.(module)}
end

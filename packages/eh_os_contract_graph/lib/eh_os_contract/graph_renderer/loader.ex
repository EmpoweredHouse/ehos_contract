defmodule EhOsContract.GraphRenderer.Loader do
  @moduledoc """
  Where `EhOsContract.GraphRenderer.Explorer` gets the `graph.v1` documents it draws, and
  the overlays the log lays over them: a host implements it, and the explorer calls it in
  the background, only when the reader enters a picture.

  A host with the engine in the same application reads it directly:

      defmodule MyAppWeb.GraphLoader do
        @behaviour EhOsContract.GraphRenderer.Loader

        @impl true
        def document({:contract, id}, _opts),
          do: {:ok, EhOsContract.Graph.Document.contract(EhOsContract.Registry.contract(id))}

        # … a domain and a process module the same way

        @impl true
        def overlay({:contract, id}, _opts),
          do: {:ok, EhOsContract.Graph.Overlay.contract(EhOsContract.Registry.contract(id))}
      end

  A host that has only the application's JSON API, as the EHOS Console does, reads
  `GET <mount>/graph/domain/<name>`, `…/graph/<contract>` and `…/graph/process/<id>`,
  each with `/overlay`, and decodes them; `opts` is what it passed beside the module,
  `loader={{MyLoader, app: "rehmed"}}`, so one loader serves several applications.

  **A reference** names a document: `{:domain, name}` (the domain's module, as the
  documents name it, e.g. `"Rehmed.Domain"`), `{:contract, id}` and `{:process, id}` (the
  ids the domain's document gives its contract and process nodes as `name`).

  **What it answers:** `{:ok, document}` with string keys, as JSON decodes it;
  `{:ok, nil}` from `overlay/2` when the log says nothing; `{:error, reason}`, which the
  explorer shows as a picture it could not load. An overlay of another version of the
  document than the one drawn is not drawn (`EhOsContract.GraphRenderer.Canvas`).
  """

  @typedoc "What a document is of: a domain by its module's name, a contract or a process module by its id."
  @type ref :: {:domain, String.t()} | {:contract, String.t()} | {:process, String.t()}

  @doc "The `graph.v1` document `ref` names."
  @callback document(ref(), opts :: term()) :: {:ok, map()} | {:error, term()}

  @doc "What the log says over the document `ref` names: an `eh_os_contract.graph_overlay.v1`, or `nil`."
  @callback overlay(ref(), opts :: term()) :: {:ok, map() | nil} | {:error, term()}
end

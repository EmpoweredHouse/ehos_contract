defmodule Mix.Tasks.EhosContract.Graph do
  @shortdoc "Gives the graph.v1 document of a contract, a process module or a domain, or the log over it"

  @moduledoc """
  Gives the `graph.v1` document of a contract, a process module or a domain. A
  renderer draws this document (`EhosContract.Graph.Document`). With `--overlay`, the
  task also gives what the log says over it (`EhosContract.Graph.Overlay`).

      mix ehos_contract.graph --contract lending.circulation --output circulation.json
      mix ehos_contract.graph --contract lending.circulation --overlay --since 2026-07-01T00:00:00Z
      mix ehos_contract.graph --process fulfilment.order --overlay --output order.json
      mix ehos_contract.graph --domain lending --output lending.json
      mix ehos_contract.graph --output-dir graph

  | Option | Value |
  | --- | --- |
  | `--contract` | the `id:` of a contract |
  | `--process` | the `id:` of a process module. It can be the same as the `id:` of a contract, so the two are different options. |
  | `--domain` | the `name:` of a domain. You can leave it out if the application has one domain. |
  | `--overlay` | adds what the log says |
  | `--since` | the start of the period of the overlay, ISO 8601. A time without an offset is UTC. It needs `--overlay`. The overlay has no end of the period. |
  | `--output` | a file for the document |
  | `--output-dir` | a directory for each document of the application. It takes no other option. |

  Give one of `--contract`, `--process` and `--domain`, or none of them. With none,
  the task gives the document of the domain. The task takes no argument other than
  these options. A wrong combination stops it with an error.

  ## What a document holds

  The task finds a contract or a process module in the registry. So the document
  shows the code that runs.

  - The document of a domain holds its context map, its contracts and process
    modules, what flows between them, and its actors.
  - A document holds each fact of its contract or domain, also the facts that a
    renderer does not draw. The renderer `ehos_contract_graph` draws the pictures,
    and the dashboard mounts it.
  - The bytes are the bytes that the API serves, with the keys of each object in
    order. So you can compare two documents with `diff`.

  ## Add what the log says over the document

  > **`--overlay` starts the whole application.**
  > Run it only with the code that is deployed. The task records a deployment. It starts
  > the subscriptions, the relays, the inboxes and Oban. So effects can call external
  > systems from where you run it, and an inbox can take messages from the transport. If
  > your code differs from the deployed code, the engine rebuilds each changed process
  > manager at once. It also rebuilds each changed read model that has `reset/0`. A
  > rebuilt read model is empty until it catches up. A rebuilt process manager forgets
  > its runs, and learns them again from the log. An event appended before it reaches
  > the head never gets a reaction. A timer due by then is dropped, unless its job is
  > still in the queue. The deployed nodes then rebuild the same consumers again at
  > their next boot.

  The overlay reads the log through the repo of the application, so the task starts
  the application.

  ## Write each document of the application

  `--output-dir` writes each document of the application in one run. A pipeline sends
  these documents with a deployment. The project loads one time, not one time for
  each document.

  - The directory must not exist yet, or must be empty. So a document of a contract
    that you removed after an earlier run is never sent with the rest.
  - The document of a domain is `domain.<module>.json` (`domain.Lending.Domain.json`).
  - The document of a contract is `contract.<id>.json`. The document of a process
    module is `process.<id>.json`. The loader of the renderer uses these names.
  - Each file holds the bytes that `--output` writes for it.
  - The task writes no overlay.

  `mix ehos_contract.bundle`, in `ehos_contract_auth`, writes these documents with
  the manifest and an index of their digests. That is the bundle that the platform
  deploys from.

  ## Write the document to a file

  Use `--output`. Erlang keeps the standard output in latin1 when it is not a
  terminal. Each label of a document is in the language of the client.

  Without `--output`, the task writes the document to the standard output. When the
  application starts (`--overlay`), the task moves the log of the application to the
  standard error. But the code of the application can still print to the standard
  output, so `> graph.json` can hold more than the document. If you need the document
  alone, use `--output`. Mix also prints the compile to the standard output before the
  task runs.
  """

  use Boundary, classify_to: EhosContract
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    # Erlang keeps stdout in latin1 when the output is not a terminal, so
    # `mix ehos_contract.graph > graph.json` truncates every codepoint to a byte. Labels
    # come from the contract and are written in the client's language.
    :io.setopts(:standard_io, encoding: :unicode)

    {opts, rest} =
      OptionParser.parse!(args,
        strict: [
          contract: :string,
          process: :string,
          domain: :string,
          overlay: :boolean,
          since: :string,
          output: :string,
          output_dir: :string
        ]
      )

    cond do
      rest != [] ->
        Mix.raise("unexpected arguments: #{Enum.join(rest, " ")}")

      Enum.count([:contract, :process, :domain], &opts[&1]) > 1 ->
        Mix.raise(
          "--contract gives a contract's document, --process a process module's, " <>
            "--domain a domain's; pass one of them"
        )

      opts[:output_dir] &&
          Enum.any?([:contract, :process, :domain, :overlay, :since, :output], &opts[&1]) ->
        Mix.raise(
          "--output-dir writes every document of the application, and no overlay; " <>
            "pass it alone"
        )

      opts[:since] && !opts[:overlay] ->
        Mix.raise(
          "the document is the declarations unless --overlay; --since applies to --overlay"
        )

      true ->
        :ok
    end

    cond do
      opts[:output_dir] -> write_all(opts[:output_dir])
      opts[:output] -> write(opts)
      true -> logs_to_stderr(fn -> write(opts) end)
    end
  end

  # Every domain's, contract's and process module's document, each in a file of its own.
  defp write_all(dir) do
    alias EhosContract.Graph.Document

    case File.ls(dir) do
      {:ok, []} ->
        :ok

      {:ok, _files} ->
        Mix.raise("#{dir} holds files already; --output-dir writes into an empty one")

      {:error, :enoent} ->
        :ok

      {:error, reason} ->
        Mix.raise("cannot read #{dir}: #{:file.format_error(reason)}")
    end

    load(overlay: false)
    contracts = EhosContract.Registry.contracts()
    processes = EhosContract.Registry.processes()

    # Each named as a loader names it: a domain by its module, the others by their ids.
    documents =
      Enum.map(EhosContract.Registry.domains(), &Document.domain(&1, contracts ++ processes)) ++
        Enum.map(contracts, &Document.contract/1) ++ Enum.map(processes, &Document.process/1)

    File.mkdir_p!(dir)

    for document <- documents do
      name = "#{document["kind"]}.#{document[document["kind"]]}.json"
      File.write!(Path.join(dir, name), encoded(document))
    end

    Mix.shell().info("written: #{length(documents)} documents in #{dir}")
  end

  defp write(opts) do
    alias EhosContract.Graph.{Document, Overlay}

    load(overlay: opts[:overlay])

    period = [since: since(opts)]
    modules = EhosContract.Registry.contracts() ++ EhosContract.Registry.processes()

    document =
      cond do
        id = opts[:contract] ->
          contract = contract!(id)

          if opts[:overlay],
            do: Overlay.contract(contract, period),
            else: Document.contract(contract)

        id = opts[:process] ->
          process = process!(id)

          if opts[:overlay],
            do: Overlay.process(process, period),
            else: Document.process(process)

        true ->
          domain = EhosContract.Tools.domain!(EhosContract.Registry.domains(), opts[:domain])

          if opts[:overlay],
            do: Overlay.domain(domain, modules, period),
            else: Document.domain(domain, modules)
      end

    emit_output(encoded(document), opts)
  end

  # The project's registry: compiled, or started where the log is read.
  defp load(overlay: overlay?) do
    if overlay? do
      Mix.Task.run("app.start")
    else
      Mix.Task.run("compile")
      Application.load(:ehos_contract)
    end

    EhosContract.Registry.load!()
  end

  defp encoded(document), do: EhosContract.Graph.Document.encode(document, pretty: true) <> "\n"

  # Runs `fun` with the default log handler writing to stderr rather than stdout, and
  # puts it back after: a host's application logs as it starts (a relay with no bus, a
  # key set it cannot fetch), and on stdout that would land inside the document. Both
  # the handler running now and the one `app.start` adds when it restarts Logger, from
  # `config :logger, :default_handler`, are moved; a console the host turned off stays
  # off. A `runtime.exs` that sets `:default_handler` itself still wins. Called by
  # `run/1`; public for its test.
  @doc false
  @spec logs_to_stderr((-> result)) :: result when result: term()
  def logs_to_stderr(fun) do
    env = Application.fetch_env(:logger, :default_handler)
    handler = handler_env(env)
    if handler, do: Application.put_env(:logger, :default_handler, handler)
    moved? = move_handler(:standard_io, :standard_error) == :ok

    try do
      fun.()
    after
      case env do
        {:ok, value} -> Application.put_env(:logger, :default_handler, value)
        :error -> Application.delete_env(:logger, :default_handler)
      end

      # Putting it back never hides what `fun` raised.
      if moved?, do: move_handler(:standard_error, :standard_io)
    end
  end

  # The `:default_handler` Logger would start with, on stderr; nil where it starts
  # none, or one that is not a console. Unset, Logger builds it from the legacy
  # `:console` key, and starts none when `:backends` leaves the console out.
  defp handler_env({:ok, false}), do: nil

  defp handler_env({:ok, handler}), do: on_stderr(handler)

  defp handler_env(:error) do
    case Application.fetch_env(:logger, :backends) do
      {:ok, backends} when is_list(backends) ->
        if :console in backends, do: legacy_console()

      _unset ->
        legacy_console()
    end
  end

  defp legacy_console do
    :logger |> Application.get_env(:console, []) |> Keyword.take([:level]) |> on_stderr()
  end

  defp on_stderr(handler) do
    config = handler |> Keyword.get(:config, []) |> Map.new()

    if Keyword.get(handler, :module, :logger_std_h) == :logger_std_h and
         Map.get(config, :type, :standard_io) == :standard_io and not Map.has_key?(config, :file),
       do: Keyword.put(handler, :config, Map.put(config, :type, :standard_error))
  end

  # Moves the default handler from one device to the other, if it is on the first.
  defp move_handler(from, to) do
    with {:ok, %{module: :logger_std_h, config: %{type: ^from}} = handler} <-
           :logger.get_handler_config(:default),
         _synced <- :logger_std_h.filesync(:default),
         :ok <- :logger.remove_handler(:default) do
      :logger.add_handler(:default, :logger_std_h, put_in(handler.config.type, to))
    end
  end

  # By the contract's id (plan DD, P1a, #183), as the dashboard's APIs name it.
  defp contract!(id) do
    EhosContract.Registry.contract(id) ||
      Mix.raise(
        "no contract #{id}. Registered: " <>
          (EhosContract.Registry.contracts()
           |> Enum.map(&EhosContract.Model.fetch(&1).id)
           |> Enum.sort()
           |> Enum.join(", "))
      )
  end

  defp process!(id) do
    EhosContract.Registry.process(id) ||
      Mix.raise(
        "no process module #{id}. Registered: " <>
          (EhosContract.Registry.processes()
           |> Enum.map(&EhosContract.Model.fetch(&1).id)
           |> Enum.sort()
           |> Enum.join(", "))
      )
  end

  defp since(opts), do: opts[:since] && at(opts[:since])

  # An offset is kept, so `+02:00` is the instant it names; a time written without
  # one is UTC, as it always was here (`ehos_contract.report` asks for the offset).
  defp at(value) do
    case DateTime.from_iso8601(value) do
      {:ok, at, _offset} ->
        at

      _no_offset ->
        case NaiveDateTime.from_iso8601(value) do
          {:ok, naive} -> DateTime.from_naive!(naive, "Etc/UTC")
          _ -> Mix.raise("--since needs an ISO8601 time, e.g. 2026-07-01T00:00:00Z")
        end
    end
  end

  defp emit_output(text, opts) do
    case opts[:output] do
      nil ->
        Mix.shell().info(text)

      path ->
        File.write!(path, text)
        Mix.shell().info("written: #{path}")
    end
  end
end

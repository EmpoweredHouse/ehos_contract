defmodule Mix.Tasks.EhOsContract.Graph do
  @shortdoc "Gives a contract's, a process's or a domain's graph.v1 document, or the log over it"

  @moduledoc """
  The `graph.v1` document a renderer is given (`EhOsContract.Graph.Document`), of one
  contract or process module the registry finds — that is, of the binary that runs — or
  of its domain, and with `--overlay` what the log says over it
  (`EhOsContract.Graph.Overlay`).

      mix eh_os_contract.graph --contract lending.circulation --output circulation.json
      mix eh_os_contract.graph --contract lending.circulation --overlay --since 2026-07-01T00:00:00Z
      mix eh_os_contract.graph --process fulfilment.order --overlay --output order.json
      mix eh_os_contract.graph --domain lending --output lending.json

  `--contract` names a contract by its `id:`, `--process` a process module by its
  `id:`; a process module may share its id with a contract, so they are two options.
  Without either the task gives the domain's document — its context map, its contracts
  and process modules and what flows between them, its actors — and `--domain` names
  the domain by its `name:`, which it may leave out when the application has one. The
  bytes are the ones the API serves, every object's keys in order, so two of them
  compare with `diff`. A document holds every fact of its
  contract or domain, whatever a renderer draws of them; the pictures are the
  renderer's (`eh_os_contract_graph`), which the dashboard mounts.

  Use `--output`: Erlang keeps stdout in latin1 when it is not a terminal, and
  every label of a document is written in the client's language. Without it the
  document is the only thing the task writes to stdout: what the application logs as
  it starts (`--overlay` starts it) goes to stderr, so `> graph.json` is the document
  alone — once the project is compiled, since Mix prints its compilation to stdout
  before the task runs.
  """

  use Boundary, classify_to: EhOsContract
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    # Erlang keeps stdout in latin1 when the output is not a terminal, so
    # `mix eh_os_contract.graph > graph.json` truncates every codepoint to a byte. Labels
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
          output: :string
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

      opts[:since] && !opts[:overlay] ->
        Mix.raise(
          "the document is the declarations unless --overlay; --since applies to --overlay"
        )

      true ->
        :ok
    end

    if opts[:output], do: write(opts), else: logs_to_stderr(fn -> write(opts) end)
  end

  defp write(opts) do
    alias EhOsContract.Graph.{Document, Overlay}

    if opts[:overlay] do
      Mix.Task.run("app.start")
    else
      Mix.Task.run("compile")
      Application.load(:eh_os_contract)
    end

    EhOsContract.Registry.load!()

    period = [since: since(opts)]
    modules = EhOsContract.Registry.contracts() ++ EhOsContract.Registry.processes()

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
          domain = EhOsContract.Tools.domain!(EhOsContract.Registry.domains(), opts[:domain])

          if opts[:overlay],
            do: Overlay.domain(domain, modules, period),
            else: Document.domain(domain, modules)
      end

    emit_output(Document.encode(document, pretty: true) <> "\n", opts)
  end

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
    EhOsContract.Registry.contract(id) ||
      Mix.raise(
        "no contract #{id}. Registered: " <>
          (EhOsContract.Registry.contracts()
           |> Enum.map(&EhOsContract.Model.fetch(&1).id)
           |> Enum.sort()
           |> Enum.join(", "))
      )
  end

  defp process!(id) do
    EhOsContract.Registry.process(id) ||
      Mix.raise(
        "no process module #{id}. Registered: " <>
          (EhOsContract.Registry.processes()
           |> Enum.map(&EhOsContract.Model.fetch(&1).id)
           |> Enum.sort()
           |> Enum.join(", "))
      )
  end

  defp since(opts), do: opts[:since] && at(opts[:since])

  # An offset is kept, so `+02:00` is the instant it names; a time written without
  # one is UTC, as it always was here (`eh_os_contract.report` asks for the offset).
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

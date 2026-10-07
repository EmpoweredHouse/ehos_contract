defmodule Mix.Tasks.EhOsContract.Graph do
  @shortdoc "Draws a process, a contract, a unit or a domain as a Mermaid diagram, or gives its graph.v1 document"

  @moduledoc """
  The contracts the registry finds — that is, of the binary that runs — either as
  one picture, a Mermaid diagram, or with `--json` as the `graph.v1` document a
  renderer is given (below). Which picture or document is a flag, and with none the
  task refuses, printing the forms it takes.

  ## `--process`: one process, for the process owner

      mix eh_os_contract.graph --mermaid --process clinical_visit --output visit.mmd

  `--process` draws one process's **declared shape** — stages as lanes, how it can
  end, each promise as an arrow carrying its window — for the process owner, before
  anything is built. With `--overlay` it is drawn as its contract's full graph
  instead, with the log laid over it (below).

  ## `--contract`, `--unit` and `--lifecycle`: a contract, whole or one unit of it

      mix eh_os_contract.graph --contract rehmed.settlement --output settlement.mmd
      mix eh_os_contract.graph --contract rehmed.settlement --overlay --output settlement.mmd
      mix eh_os_contract.graph --contract rehmed.settlement --unit visit_settlement --output unit.mmd
      mix eh_os_contract.graph --contract appunite_equipment.computers --lifecycle computer --overlay --output computer.mmd

  `--contract` draws the contract's full graph (plan EG1,
  `EhOsContract.Graph.contract_to_mermaid/2`): commands, events, the consumers
  between them and timers, each kind in its Event Storming colour, and the actors,
  read models, queries and external systems around them. `--overlay` lays the log
  over its steps — runs per step, and what waits or fails there. `--unit` draws one
  unit instead (`EhOsContract.Graph.unit_to_mermaid/2`): its state, commands, events,
  invariants, and how many scenarios pin each path. `--lifecycle` draws an
  aggregate's lifecycle (`EhOsContract.Graph.lifecycle_to_mermaid/3`): where it
  starts, its statuses and ends, the transitions between them; `--overlay` puts the
  report's counts on them. All are Mermaid, so `--mermaid` is not needed.

  ## `--map` and `--system`: a domain

      mix eh_os_contract.graph --map rehmed --output map.mmd
      mix eh_os_contract.graph --system rehmed --overlay --output system.mmd

  `--map` draws the domain's context map (plan EG2,
  `EhOsContract.Graph.context_map_to_mermaid/1`): subdomains, their contexts, the
  external systems and the relations between them. `--system` draws its
  contracts in their contexts and what one consumes from another
  (`EhOsContract.Graph.system_to_mermaid/3`); `--overlay` lays the log over it —
  runs per contract, and per edge the consumed events and what waits or fails at
  the consumer. Both take the domain's `name:`.

  A process's picture is per process and never global on purpose: ADR §9 says
  *navigation is per-process, never global*. The system is not a global list of
  events: it draws contracts and what flows between them, and leaves each
  contract's own steps to `--contract`.

  ## `--json`: the document a renderer is given

      mix eh_os_contract.graph --json --contract rehmed.settlement --output settlement.json
      mix eh_os_contract.graph --json --contract rehmed.settlement --overlay --since 2026-07-01T00:00:00Z
      mix eh_os_contract.graph --json --system rehmed --output rehmed.json

  `--json` writes the contract's or the domain's `graph.v1` document
  (`EhOsContract.Graph.Document`) — the same bytes the API serves, its keys in order,
  so two of them compare with `diff` — and with `--overlay` what the log says over it
  (`EhOsContract.Graph.Overlay`). A document holds every fact of its contract or
  domain, whatever a renderer draws of them, so `--unit`, `--lifecycle` and `--process`
  take no `--json`, and `--map` and `--system` give the same domain document.

  Use `--output`: Erlang keeps stdout in latin1 when it is not a terminal, and
  every node of a diagram or a document is written in the client's language. Without
  it the diagram or the document is the only thing the task writes to stdout: what
  the application logs as it starts (`--overlay` starts it) goes to stderr, so
  `> graph.json` is the document alone — once the project is compiled, since Mix
  prints its compilation to stdout before the task runs.
  """

  use Boundary, classify_to: EhOsContract
  use Mix.Task

  @usage """
  mix eh_os_contract.graph draws one picture or gives one document; name which:

      mix eh_os_contract.graph --process NAME --mermaid [--overlay [--since AT]]
      mix eh_os_contract.graph --contract ID [--unit NAME | --lifecycle NAME] [--overlay [--since AT]]
      mix eh_os_contract.graph --map DOMAIN
      mix eh_os_contract.graph --system DOMAIN [--overlay [--since AT]]
      mix eh_os_contract.graph --json (--contract ID | --system DOMAIN) [--overlay [--since AT]]
      mix eh_os_contract.graph --json --map DOMAIN

  and --output PATH to write it to a file.
  """

  @impl Mix.Task
  def run(args) do
    # Erlang keeps stdout in latin1 when the output is not a terminal, so
    # `mix eh_os_contract.graph > graph.txt` truncates every codepoint to a byte. Event
    # labels come from the contract and are written in the client's language.
    :io.setopts(:standard_io, encoding: :unicode)

    {opts, _} =
      OptionParser.parse!(args,
        strict: [
          overlay: :boolean,
          mermaid: :boolean,
          json: :boolean,
          since: :string,
          output: :string,
          process: :string,
          contract: :string,
          unit: :string,
          lifecycle: :string,
          map: :string,
          system: :string
        ]
      )

    refuse_ignored!(opts)

    if opts[:output], do: write(opts), else: logs_to_stderr(fn -> write(opts) end)
  end

  defp write(opts) do
    if opts[:overlay] do
      Mix.Task.run("app.start")
    else
      Mix.Task.run("compile")
      Application.load(:eh_os_contract)
    end

    EhOsContract.Registry.load!()

    cond do
      opts[:json] -> json(opts)
      opts[:map] -> domain_picture(opts[:map], &EhOsContract.Graph.context_map_to_mermaid/1, opts)
      opts[:system] -> domain_picture(opts[:system], &system(&1, opts), opts)
      opts[:contract] -> contract(opts)
      opts[:process] -> declared(opts)
    end
  end

  @doc false
  # Runs `fun` with the default log handler writing to stderr rather than stdout, and
  # puts it back after: a host's application logs as it starts (a relay with no bus, a
  # key set it cannot fetch), and on stdout that would land inside the document. Both
  # the handler running now and the one `app.start` adds when it restarts Logger, from
  # `config :logger, :default_handler`, are moved; a console the host turned off stays
  # off. A `runtime.exs` that sets `:default_handler` itself still wins.
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

  # The declared shape of one process, for a person who has not read the module.
  # Deliberately per process rather than global: ADR §9 says navigation is per
  # process and never global.
  defp declared(opts) do
    name = String.to_atom(opts[:process])

    contract =
      Enum.find(EhOsContract.Registry.contracts(), fn c ->
        match?(%{name: ^name}, EhOsContract.Model.process(c))
      end)

    cond do
      not opts[:mermaid] ->
        Mix.raise("--process draws a diagram; pass --mermaid (and --output to keep the accents)")

      contract && opts[:overlay] ->
        emit_output(
          EhOsContract.Graph.contract_to_mermaid(contract, overlay: true, since: since(opts)),
          opts
        )

      contract ->
        emit_output(EhOsContract.Graph.declared_to_mermaid(contract, name), opts)

      true ->
        known =
          for(
            c <- EhOsContract.Registry.contracts(),
            %{name: n} <- [EhOsContract.Model.process(c)],
            do: n
          )
          |> Enum.sort()
          |> Enum.join(", ")

        Mix.raise("no process #{inspect(name)}. Declared: #{known}")
    end
  end

  # A flag the picture asked for would not use is refused rather than dropped: a unit
  # draws no log, and a contract and a process are two different pictures. No picture
  # at all is refused with the forms the task takes.
  defp refuse_ignored!(opts) do
    pictures = for key <- [:map, :system, :contract, :process], opts[key], do: "--#{key}"

    cond do
      opts[:json] && (opts[:unit] || opts[:lifecycle] || opts[:process] || opts[:mermaid]) ->
        Mix.raise(
          "--json gives a contract's or a domain's whole document; pass --contract or --system, " <>
            "without --unit, --lifecycle, --process or --mermaid"
        )

      opts[:unit] && !opts[:contract] ->
        Mix.raise("--unit names a unit of a contract; pass --contract too")

      opts[:unit] && (opts[:overlay] || opts[:since]) ->
        Mix.raise("--unit draws the declarations only; --overlay and --since apply to --contract")

      opts[:lifecycle] && !opts[:contract] ->
        Mix.raise("--lifecycle names an aggregate of a contract; pass --contract too")

      opts[:lifecycle] && opts[:since] && !opts[:overlay] ->
        Mix.raise(
          "--lifecycle draws the declarations unless --overlay; --since applies to --overlay"
        )

      opts[:lifecycle] && opts[:unit] ->
        Mix.raise("--unit and --lifecycle draw different pictures of a unit; pass one of them")

      opts[:map] && (opts[:overlay] || opts[:since]) ->
        Mix.raise(
          "--map draws the domain's declarations only; --overlay and --since apply to --system"
        )

      length(pictures) > 1 ->
        Mix.raise("#{Enum.join(pictures, " and ")} draw different pictures; pass one of them")

      pictures == [] ->
        Mix.raise(String.trim_trailing(@usage))

      true ->
        :ok
    end
  end

  # The document of a contract or a domain, or its overlay, as JSON.
  defp json(opts) do
    alias EhOsContract.Graph.{Document, Overlay}

    period = [since: since(opts)]
    contracts = EhOsContract.Registry.contracts()

    document =
      case opts[:contract] do
        nil ->
          domain = domain!(opts[:map] || opts[:system])

          if opts[:overlay],
            do: Overlay.domain(domain, contracts, period),
            else: Document.domain(domain, contracts)

        name ->
          contract = contract!(name)

          if opts[:overlay],
            do: Overlay.contract(contract, period),
            else: Document.contract(contract)
      end

    emit_output(Document.encode(document, pretty: true) <> "\n", opts)
  end

  # A picture of the domain named `name`, drawn by `draw` from its module.
  defp domain_picture(name, draw, opts), do: emit_output(draw.(domain!(name)), opts)

  defp domain!(name) do
    domains = EhOsContract.Registry.domains()
    domain = Enum.find(domains, &(Atom.to_string(EhOsContract.Model.fetch(&1).name) == name))

    unless domain do
      known = domains |> Enum.map(&EhOsContract.Model.fetch(&1).name) |> Enum.sort()
      Mix.raise("no domain #{name}. Registered: #{Enum.join(known, ", ")}")
    end

    domain
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

  defp system(domain, opts) do
    EhOsContract.Graph.system_to_mermaid(domain, EhOsContract.Registry.contracts(),
      overlay: opts[:overlay] || false,
      since: since(opts)
    )
  end

  # A v2 contract's full graph, or one of its units.
  defp contract(opts) do
    contract = contract!(opts[:contract])

    text =
      case {opts[:unit], opts[:lifecycle]} do
        {nil, nil} ->
          EhOsContract.Graph.contract_to_mermaid(contract,
            overlay: opts[:overlay] || false,
            since: since(opts)
          )

        {nil, unit} ->
          with_lifecycle =
            for u <- EhOsContract.Model.fetch(contract).units,
                EhOsContract.Lifecycle.of(u),
                do: Atom.to_string(u.name)

          cond do
            with_lifecycle == [] ->
              Mix.raise("#{opts[:contract]} declares no lifecycle")

            unit not in with_lifecycle ->
              Mix.raise(
                "#{opts[:contract]} has no aggregate #{unit} with a lifecycle. With one: " <>
                  Enum.join(with_lifecycle, ", ")
              )

            true ->
              :ok
          end

          EhOsContract.Graph.lifecycle_to_mermaid(contract, String.to_existing_atom(unit),
            overlay: opts[:overlay] || false,
            since: since(opts)
          )

        {unit, nil} ->
          units = Enum.map(EhOsContract.Model.fetch(contract).units, &Atom.to_string(&1.name))

          unless unit in units,
            do:
              Mix.raise(
                "#{opts[:contract]} has no unit #{unit}. Units: #{Enum.join(units, ", ")}"
              )

          EhOsContract.Graph.unit_to_mermaid(contract, String.to_existing_atom(unit))
      end

    emit_output(text, opts)
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

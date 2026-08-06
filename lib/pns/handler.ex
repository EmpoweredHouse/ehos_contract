defmodule PNS.Handler do
  @moduledoc """
  Compile-time enforcement (ADR §5-6, notes §2).

  The checks happen **in the macro body, not in `quote`** — that creates a compile
  dependency which makes the compiler take the contract first, and `__CALLER__`
  gives a file and line pointing at the handler rather than at the library.

  One half of the `publishes:` promise cannot be kept at compile time, and it lives
  here too rather than in the emitter: see `verify_publications!/2`. Keeping both
  halves in one file is deliberate — a declaration checked in one place and honoured
  in another is how the two drift apart.
  """

  @callback handle(payload :: map(), ctx :: map()) :: :ok | {:ok, list()} | {:error, term()}

  @doc false
  defmacro __using__(opts) do
    caller = __CALLER__
    contract = opts |> Keyword.fetch!(:contract) |> Macro.expand(caller)
    event = Keyword.fetch!(opts, :event)
    publishes = Keyword.get(opts, :publishes, [])
    async = Keyword.get(opts, :async, false)

    # Forcing compilation order: without this the contract might not exist yet,
    # and the check below would fall silent instead of firing.
    Code.ensure_compiled!(contract)

    unless function_exported?(contract, :__pns_contract__, 0) do
      bail!(caller, "#{inspect(contract)} is not a PNS contract (no `use PNS.Contract`)")
    end

    unless contract.event?(event) do
      bail!(
        caller,
        "handler declares event #{inspect(event)}, which contract #{inspect(contract)} does not " <>
          "declare. Declared events: #{inspect(contract.event_names())}"
      )
    end

    for published <- publishes, not contract.event?(published) do
      bail!(
        caller,
        "handler declares `publishes: #{inspect(published)}`, which contract " <>
          "#{inspect(contract)} does not declare"
      )
    end

    if async and is_nil(contract.event(event).identity) do
      bail!(
        caller,
        "an asynchronous handler requires event #{inspect(event)} to declare `identity:` in the " <>
          "contract. Oban gives at-least-once, so this event will arrive a second time, and the " <>
          "question \"what makes two occurrences the same fact\" is one for the process owner, " <>
          "not for the handler. Add `identity:` in #{inspect(contract)}."
      )
    end

    quote do
      @behaviour PNS.Handler

      @doc false
      def __pns_handler__ do
        %{
          module: __MODULE__,
          contract: unquote(contract),
          event: unquote(event),
          publishes: unquote(publishes),
          async: unquote(async)
        }
      end
    end
  end

  @doc """
  Raises unless a handler emitted only the events it declared it publishes.

  The compile-time check above verifies that each name in `publishes:` exists in the
  contract. It cannot verify the other direction, because what a handler emits is
  decided inside `handle/2` — so a handler may declare `publishes: [:x]`, emit `:y`,
  and pass both compilation and `mix pns.check` as long as `:y` is declared anywhere
  in the contract.

  That gap is not cosmetic. The deployment graph's edges come from `publishes:`
  (`PNS.Deployment`), so an undeclared emission produces an observed edge that no
  recorded wiring contains — and the report calls it drift, correctly in form and for
  a false reason. The declaration would be describing the code rather than binding
  it, which is the same failure as a graph built from a heuristic.

  A violation can only ever be a code defect, never a data condition: both the
  declaration and the emitted name are static in the handler. So this fires on the
  first test that exercises the handler, which is the point — it moves the discovery
  out of production.

  **What follows from a violation is split by the transaction boundary**, the same
  way every other failure is (ADR §9-10). Raised out of a synchronous handler it
  rolls the transaction back, so the log does not claim a state change that did not
  happen. Raised inside the queue it is caught where every other handler failure is
  caught, recorded against the event with its message, and nothing is emitted. One
  rule, two consequences, because the consequence belongs to the boundary rather
  than to the rule.

  Emissions from a command's decision function are **not** checked here and have
  nothing to be checked against: their bound is the contract itself, which
  `PNS.Emitter` enforces. A handler is bound by something narrower that it declared
  about itself.
  """
  @spec verify_publications!(map(), [PNS.Emission.t()]) :: :ok
  def verify_publications!(meta, emissions) do
    undeclared =
      emissions
      |> Enum.map(& &1.name)
      |> Enum.uniq()
      |> Enum.reject(&(&1 in meta.publishes))

    case undeclared do
      [] ->
        :ok

      names ->
        PNS.Telemetry.contract_violation(:undeclared_publication, %{
          contract: meta.contract,
          handler: meta.module,
          event_type: meta.event,
          undeclared: names
        })

        raise ArgumentError,
              "#{inspect(meta.module)} emitted #{inspect(names)} without declaring it. " <>
                "Declared: `publishes: #{inspect(meta.publishes)}`. The deployment graph is " <>
                "built from that declaration, so this path would be reported as drift while " <>
                "the code producing it is current. Either add it to `publishes:` or stop " <>
                "emitting it — the declaration decides which."
    end
  end

  @spec bail!(Macro.Env.t(), String.t()) :: no_return()
  defp bail!(caller, message) do
    raise CompileError, file: caller.file, line: caller.line, description: message
  end
end

defmodule PNS.Handler do
  @moduledoc """
  Compile-time enforcement (ADR §5-6, notes §2).

  The checks happen **in the macro body, not in `quote`** — that creates a compile
  dependency which makes the compiler take the contract first, and `__CALLER__`
  gives a file and line pointing at the handler rather than at the library.
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

  @spec bail!(Macro.Env.t(), String.t()) :: no_return()
  defp bail!(caller, message) do
    raise CompileError, file: caller.file, line: caller.line, description: message
  end
end

defmodule EhOsContract do
  @moduledoc """
  The package's public surface.

  What would be the `eh_os_contract` hex package — kept in `lib/eh_os_contract/` beside the client
  application in `lib/taxvision/`, with the boundary enforced by `boundary` from
  the first commit. The structure is the one notes §15 foresee for the first
  client, so moving it out beside the client's repository is a `git mv`.
  """

  use Boundary,
    deps: [],
    exports: [
      AsyncAPI,
      Check,
      Conformance,
      Conformance.Wire,
      Contract,
      ContractExample,
      Deployment,
      Duration,
      Emission,
      Emitter,
      Event,
      EventHandling,
      Graph,
      Handler,
      Instance,
      Job,
      Migrations,
      Payload,
      Registry,
      Report,
      Report.Sentence,
      Trace
    ]

  # Read from `mix.exs` at compile time rather than through
  # `Application.spec(:eh_os_contract, :vsn)`, which returns a charlist and needs the
  # application loaded — neither of which a report renderer should have to care
  # about. This is the package reading its own project file, so it carries no
  # host configuration into a compile-time attribute.
  @version Mix.Project.config()[:version]

  @doc """
  The engine version, as published.

  A conformance report is an arithmetic result, and this repository has already
  changed what counts as drift more than once — zero runs, work still queued,
  "never attempted" against "attempted and failing", the fourth verdict. Two
  clients on two engine versions get two answers to the same question, and the
  report is evidence somebody may be asked to defend. The version says which
  arithmetic produced it. `CHANGELOG.md` says what each one changed.
  """
  @spec version() :: String.t()
  def version, do: @version

  @doc "An intention to emit an event, returned by a pure decision function."
  @spec event(atom(), map()) :: EhOsContract.Emission.t()
  def event(name, payload \\ %{}), do: %EhOsContract.Emission{name: name, payload: payload}

  defdelegate emit(contract, type, payload, ctx \\ %{}), to: EhOsContract.Emitter
  defdelegate emit!(contract, type, payload, ctx \\ %{}), to: EhOsContract.Emitter
  defdelegate emit_all(contract, emissions, ctx \\ %{}), to: EhOsContract.Emitter
end

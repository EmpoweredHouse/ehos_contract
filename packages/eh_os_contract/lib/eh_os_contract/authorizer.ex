defmodule EhOsContract.Authorizer do
  @moduledoc """
  The question dispatch and query ask about a credential's actor: may it do this?

      config :eh_os_contract, authorizer: MyApp.Authorizer

  The engine asks it about every command, query and recorded event that arrives
  with a credential, before anything else runs. It is not asked about the
  application's own code — a `:system` actor or a reaction — which the contract
  holds to its declarations instead.

  **The decision is `check/2`**, and it reads nothing but the actor and the request:

    * `{:error, :missing_capability}` — the credential does not grant the capability;
    * `{:error, :unscoped_grant}` — the capability is scoped and the credential
      carries no values for it. Empty is not "all": a grant without values is a
      grant nobody finished, and it is refused;
    * `{:error, :outside_scope}` — the value asked for is not among them.

  Values are compared as the strings the credential carries, so a
  granted value that is not of the field's type matches nothing.

  **An implementation may narrow what a credential grants, and never widen it.**
  `EhOsContract.Authorizer.Default`, used when nothing is configured, is `check/2`
  alone. `eh_os_contract_auth` calls `check/2` and records a row for each decision.
  Whatever the configured implementation answers, the engine runs `check/2` again
  after an `:ok` and raises when that refuses, so a mistake in an implementation
  fails loudly instead of letting a call through. It follows that grants travel in
  the credential, as EHOS issues them.

  A refusal writes nothing, neither to the log nor to the table of commands
  (`eh_os_contract_commands`): the row that
  records it belongs to the implementation.
  """

  alias EhOsContract.Actor

  defmodule Request do
    # A scoped command: plan E9c. Rows keyed by the contract's `id:`: plan DD, ID4 (#178).
    @moduledoc """
    What an actor asks to do: the capability, under the name EHOS grants it by
    (`EhOsContract.Model.capabilities/1`), and for a scoped query or command the
    dimension and the value asked for, both as strings, in the form a credential's
    `scp` carries them. `contract` is the contract's module and `contract_id` its
    `id:`, the name a record of the decision stores, as every row of the engine does.
    """

    @enforce_keys [:kind, :capability, :contract, :contract_id, :version]
    defstruct [:kind, :capability, :contract, :contract_id, :version, :scope]

    @typedoc "One request to authorize."
    @type t :: %__MODULE__{
            kind: :command | :query | :record,
            capability: String.t(),
            contract: module(),
            contract_id: String.t(),
            version: String.t(),
            scope: nil | {dimension :: String.t(), value :: String.t() | nil}
          }
  end

  defmodule WidenedError do
    @moduledoc """
    Raised when the configured `EhOsContract.Authorizer` allows what the credential
    does not grant. That is a defect in the implementation, never a decision.
    """

    defexception [:message]
  end

  defmodule OutsideScopeError do
    @moduledoc """
    Raised when a query's implementation answers a row outside what the credential
    grants. The query's code is wrong, and no row leaves.
    """

    defexception [:message]
  end

  @typedoc "Why a request is refused. An implementation may have reasons of its own."
  @type reason :: :missing_capability | :unscoped_grant | :outside_scope | atom()

  @doc "Whether `actor` may make `request`."
  @callback authorize(Actor.t(), Request.t()) :: :ok | {:error, reason()}

  @doc """
  The decision, from the actor and the request alone. See the module's doc for the
  reasons it refuses with.
  """
  @spec check(Actor.t(), Request.t()) :: :ok | {:error, reason()}
  def check(%Actor{kind: :credential} = actor, %Request{} = request) do
    cond do
      not MapSet.member?(actor.capabilities, request.capability) ->
        {:error, :missing_capability}

      request.scope == nil ->
        :ok

      true ->
        {dimension, value} = request.scope

        case granted(actor, request.capability, dimension) do
          [] -> {:error, :unscoped_grant}
          values -> if value in values, do: :ok, else: {:error, :outside_scope}
        end
    end
  end

  # The values `actor`'s credential grants `capability` along `dimension`, or `[]`.
  # What a query's rows are checked against.
  # Called by dispatcher.ex.
  @doc false
  @spec granted(Actor.t(), String.t(), String.t()) :: [String.t()]
  def granted(%Actor{scopes: scopes}, capability, dimension) do
    case scopes do
      %{^capability => %{^dimension => values}} when is_list(values) -> values
      _ -> []
    end
  end

  # The configured implementation: `config :eh_os_contract, authorizer: MyAuthorizer`,
  # and `EhOsContract.Authorizer.Default` when nothing is configured.
  @doc false
  @spec impl() :: module()
  def impl, do: EhOsContract.Config.get(:authorizer)

  # What the engine calls: the implementation's answer, held to `check/2`.
  @doc false
  @spec run(Actor.t(), Request.t(), module()) :: :ok | {:error, reason()}
  def run(%Actor{kind: :credential} = actor, %Request{} = request, impl \\ impl()) do
    case impl.authorize(actor, request) do
      :ok ->
        with {:error, reason} <- check(actor, request) do
          raise WidenedError,
            message:
              "#{inspect(impl)} allowed #{request.capability}, which the credential of " <>
                "#{inspect(actor.subject)} does not grant (#{inspect(reason)}). An " <>
                "EhOsContract.Authorizer may narrow a grant, never widen it."
        end

      {:error, reason} when is_atom(reason) ->
        {:error, reason}
    end
  end
end

defmodule EhOsContract.Authorizer.Default do
  @moduledoc """
  The `EhOsContract.Authorizer` used when none is configured: `check/2` alone, and
  nothing recorded.
  """

  @behaviour EhOsContract.Authorizer

  @doc "`EhOsContract.Authorizer.check/2`, and nothing else."
  @impl true
  @spec authorize(EhOsContract.Actor.t(), EhOsContract.Authorizer.Request.t()) ::
          :ok | {:error, EhOsContract.Authorizer.reason()}
  def authorize(actor, request), do: EhOsContract.Authorizer.check(actor, request)
end

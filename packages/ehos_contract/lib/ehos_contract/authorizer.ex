defmodule EhosContract.Authorizer do
  @moduledoc """
  Decides if the actor of a credential can make a call: a command, a query or a
  recorded event.

      config :ehos_contract, authorizer: MyApp.Authorizer

  The engine asks the Authorizer about each call that arrives with a credential,
  before anything else runs. It does not ask about the code of the application: a
  `:system` actor or a reaction. The contract holds that code to its declarations.

  A declaration that no person can use has no capability. The engine refuses a call
  to it with `:missing_capability`, and does not ask the Authorizer.

  ## What does the check refuse?

  `check/2` is the decision. It reads only the actor and the request. It returns
  `:ok`, or refuses with one of these reasons:

  | Reason | The credential |
  | --- | --- |
  | `:missing_capability` | does not grant the capability. |
  | `:unscoped_grant` | grants a scoped capability with no values. An empty grant is not "all": it is an unfinished grant, and `check/2` refuses it. |
  | `:outside_scope` | grants values, but not the value of the request. |

  `check/2` compares the values as the strings that the credential carries. So a
  granted value that is not of the type of the field matches nothing.

  ## What can an implementation of your own do?

  An implementation can narrow what a credential grants. It can never widen it.

  - If the configuration names no implementation, the engine uses
    `EhosContract.Authorizer.Default`, which is `check/2` alone.
  - `ehos_contract_auth` calls `check/2`, and records a row for each decision.
  - After an `:ok` of any implementation, the engine runs `check/2` again. If
    `check/2` refuses, the engine raises `EhosContract.Authorizer.WidenedError`. So
    an error in an implementation stops the call, and does not let it through.

  So the grants travel in the credential, as the platform that issues the credential
  gives them. [Write an Authorizer](authorizer.md) tells how to add a rule of your own.

  A refusal writes nothing to the log or to the table of commands
  (`ehos_contract_commands`). A row that records the refusal belongs to the
  implementation.
  """

  alias EhosContract.Actor

  defmodule Request do
    # A scoped command: plan E9c. Rows keyed by the contract's `id:`: plan DD, ID4 (#178).
    @moduledoc """
    What an actor asks to do: the capability, under the name EHOS grants it by
    (`EhosContract.Model.capabilities/1`), and for a scoped query or command the
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
    Raised when the configured `EhosContract.Authorizer` allows what the credential
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

  @doc """
  Returns `:ok` if `actor` can make `request`, or `{:error, reason}`. A reason of
  your own is an atom.
  """
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

  # The configured implementation: `config :ehos_contract, authorizer: MyAuthorizer`,
  # and `EhosContract.Authorizer.Default` when nothing is configured.
  @doc false
  @spec impl() :: module()
  def impl, do: EhosContract.Config.get(:authorizer)

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
                "EhosContract.Authorizer may narrow a grant, never widen it."
        end

      {:error, reason} when is_atom(reason) ->
        {:error, reason}
    end
  end
end

defmodule EhosContract.Authorizer.Default do
  @moduledoc """
  The `EhosContract.Authorizer` used when none is configured: `check/2` alone, and
  nothing recorded.
  """

  @behaviour EhosContract.Authorizer

  @doc "`EhosContract.Authorizer.check/2`, and nothing else."
  @impl true
  @spec authorize(EhosContract.Actor.t(), EhosContract.Authorizer.Request.t()) ::
          :ok | {:error, EhosContract.Authorizer.reason()}
  def authorize(actor, request), do: EhosContract.Authorizer.check(actor, request)
end

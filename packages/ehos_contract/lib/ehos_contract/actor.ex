defmodule EhosContract.Actor do
  @moduledoc """
  Who issues a command, asks a query or records an event.

  **What an actor may do is decided by where the call comes from**:

    * **A credential's actor** comes through the application's door. Whoever verified
      the credential builds it, `ehos_contract_auth` for EHOS's, with `subject`,
      `capabilities` and `scopes` exactly as the credential carries them in `sub`,
      `cap` and `scp`. Everything it does is asked of the `EhosContract.Authorizer`.
    * **A `:system` actor of the domain** is the application's own code: a job, an
      import. It is held to the contract and may do what the declarations whose
      `by:` or `recorded_by:` name it allow. It carries no capabilities, since no
      credential was issued to it.
    * **The domain's `:seed` actor** is the application's own code loading sample
      data, in an environment made for previews. No declaration names it: it may
      issue every command and record every event some person of the domain may, in
      every scope, except what the domain lists in its `not_seeded:`. It may not ask
      a query, and may not issue a command kept for the person its unit names
      (`actor_is:`).

  One more kind, a reaction's, is made by the engine when a policy dispatches, and is
  held to what the reaction's `issues:` names. Nothing outside the engine builds one.

  An actor never carries personal data beyond the credential's subject, an opaque
  identifier: it is written to the log with every event.
  """

  # Who acts, and what decides what they may (v2 §11, D14; the note of 26 September
  # 2026 on where the call comes from).

  defstruct [:kind, :subject, :name, capabilities: MapSet.new(), scopes: %{}]

  @typedoc """
  The values a credential grants a scoped capability, per dimension, as sorted
  strings: `%{"fulfilment.open_pick_lists_for_warehouse" => %{"warehouse_id" => ["7"]}}`.
  """
  @type scopes :: %{String.t() => %{String.t() => [String.t()]}}

  @typedoc "An actor. Build one with `credential/3`, `system/1` or `seed/1`."
  @type t :: %__MODULE__{
          kind: :credential | :system | :seed | :reaction,
          subject: String.t() | nil,
          name: atom() | {atom(), atom()} | nil,
          capabilities: MapSet.t(String.t()),
          scopes: scopes()
        }

  @doc """
  The actor of a verified credential: its subject, the capabilities it grants and
  the values of each scoped one, as the credential carries them.

      EhosContract.Actor.credential("u-81", ["fulfilment.open_pick_lists_for_warehouse"],
        %{"fulfilment.open_pick_lists_for_warehouse" => %{"warehouse_id" => ["7"]}})

  Nothing here verifies anything: an actor built from a credential nobody checked
  is a hole the host opened, and the one place that builds these from a request
  is the package that verifies the credential.

  A blank subject raises: the subject is the actor's label and the space its
  idempotency keys live in, so a blank one would make every such credential one
  actor.
  """
  @spec credential(String.t(), [String.t()] | MapSet.t(String.t()), scopes()) :: t()
  def credential(subject, capabilities, scopes \\ %{}) when is_binary(subject) do
    capabilities = MapSet.new(capabilities)

    # The subject is who the actor is: its label in the log, and the space its
    # idempotency keys live in. An empty one would be one actor for every credential
    # that has it.
    if String.trim(subject) == "", do: raise(ArgumentError, "a credential's subject is not blank")

    unless Enum.all?(capabilities, &is_binary/1) and scopes?(scopes) do
      raise ArgumentError,
            "a credential's capabilities are strings, and its scopes map a capability to " <>
              "%{dimension => [value]}, all strings, as the credential carries them"
    end

    %__MODULE__{kind: :credential, subject: subject, capabilities: capabilities, scopes: scopes}
  end

  @doc """
  A `:system` actor of the domain, by its name: the application's own code acting
  as it. `EhosContract.dispatch/3` checks that the domain declares it `:system` and
  that the declaration names it.
  """
  @spec system(atom()) :: t()
  def system(name) when is_atom(name) and name not in [nil, true, false],
    do: %__MODULE__{kind: :system, name: name}

  @doc """
  The domain's `:seed` actor, by its name: the application's own code loading sample
  data as it.

      EhosContract.Actor.seed(:sample_data)

  `EhosContract.dispatch/3` checks that the domain declares it `:seed`, and permits
  it a command, and `EhosContract.record/3` an event, that a `:human` actor of the
  domain may use and the domain's `not_seeded:` does not name. It refuses
  `:not_declared` for a query, for a declaration no person may use, and for
  a command with `actor_is:`, since the seed is no person. No `EhosContract.Authorizer`
  is asked.

  The log labels it `system:<name>`, as a `:system` actor of the same name, so a seed
  that ran as a `:system` actor replays to the same idempotency key and label.
  """
  @spec seed(atom()) :: t()
  def seed(name) when is_atom(name) and name not in [nil, true, false],
    do: %__MODULE__{kind: :seed, name: name}

  @doc false
  @spec reaction(atom(), atom()) :: t()
  def reaction(kind, name) when is_atom(kind) and is_atom(name),
    do: %__MODULE__{kind: :reaction, name: {kind, name}}

  # How the actor is written to the log and to `_commands` (v2 §10.3): `"actor:<subject>"`
  # for a credential's, `"system:<name>"`, or `"<reaction kind>:<name>"`. The seed's is a
  # system's, so a seed that ran as a `:system` actor of the same name replays to the
  # same commands (#683).
  # Called by dispatcher.ex, personal.ex, v01.ex.
  @doc false
  @spec label(t()) :: String.t()
  def label(%__MODULE__{kind: :credential, subject: subject}), do: "actor:#{subject}"

  def label(%__MODULE__{kind: kind, name: name}) when kind in [:system, :seed],
    do: "system:#{name}"

  def label(%__MODULE__{kind: :reaction, name: {kind, name}}), do: "#{kind}:#{name}"

  defp scopes?(scopes) when is_map(scopes) do
    Enum.all?(scopes, fn
      {capability, dimensions} when is_binary(capability) and is_map(dimensions) ->
        Enum.all?(dimensions, fn {dimension, values} ->
          is_binary(dimension) and is_list(values) and Enum.all?(values, &is_binary/1)
        end)

      _ ->
        false
    end)
  end

  defp scopes?(_), do: false
end

defmodule EhOsContract.Auth.Migrations.V02 do
  @moduledoc false

  # One row per decision the `EhOsContract.Authorizer` makes about a credential's
  # actor (`eh-os` D-34, FM-21): a refusal as carefully as an acceptance. The engine
  # writes nothing when it refuses, so this is the only record of a refusal.
  #
  # It records the authorization, not the command: a command allowed here may still
  # be rejected on an invariant, and that outcome is the engine's row in
  # `eh_os_contract_commands`. Two facts, two rows.

  use Ecto.Migration

  @doc false
  @spec up() :: :ok
  def up do
    create table(:eh_os_contract_auth_decisions) do
      add :decided_at, :utc_datetime_usec,
        null: false,
        default: fragment("clock_timestamp()")

      # The credential's `sub`: an opaque identifier, never personal data (v2 §17).
      add :subject, :text, null: false
      add :kind, :text, null: false
      add :capability, :text, null: false
      add :contract, :text, null: false
      add :contract_version, :text, null: false
      # For a scoped query: the dimension, and the value asked for, as the credential
      # carries values — a string, or null when the parameter was missing; one the column
      # cannot hold, past 256 bytes, or starting `sha256:`, as `sha256:<hex>` (#66, written
      # by `authorize/2`).
      add :scope_dimension, :text
      add :scope_value, :text
      add :outcome, :text, null: false
      add :reason, :text
    end

    create constraint(:eh_os_contract_auth_decisions, :outcome,
             check: "outcome IN ('allowed', 'refused')"
           )

    create constraint(:eh_os_contract_auth_decisions, :reason,
             check: "(outcome = 'refused') = (reason IS NOT NULL)"
           )

    create index(:eh_os_contract_auth_decisions, [:decided_at])
    create index(:eh_os_contract_auth_decisions, [:subject, :decided_at])
    :ok
  end

  @doc false
  @spec down() :: :ok
  def down do
    drop table(:eh_os_contract_auth_decisions)
    :ok
  end
end

defmodule EhOsContract.Migrations.V05 do
  @moduledoc false

  # The tables of crypto-shredding (v2 §10.3, §14; plan stage E8).
  #
  #   * `eh_os_contract_subject_keys`: one data key per subject and key version,
  #     wrapped by a master key of `EhOsContract.Vault`, `kek_id` naming which. The
  #     personal fields of a subject's events are encrypted with it; deleting its
  #     rows is what erases the subject. `key_version` is always 1 until a subject's
  #     key can be rotated, which waits for someone who needs it.
  #   * `eh_os_contract_erasures`: one row per erased subject, so that nothing is
  #     appended for it again. Written by stage E8b, created here, as V04 created the
  #     tables of E7b and E7c.
  #
  # Neither is append-only: rotating a master key rewraps every data key in place,
  # and erasure deletes them.

  use Ecto.Migration

  @doc false
  @spec up() :: :ok
  def up do
    create table(:eh_os_contract_subject_keys, primary_key: false) do
      add :subject_type, :text, primary_key: true
      add :subject_id, :text, primary_key: true
      add :key_version, :integer, primary_key: true
      add :kek_id, :text, null: false
      add :wrapped_key, :binary, null: false
      add :inserted_at, :utc_datetime_usec, null: false, default: fragment("clock_timestamp()")
    end

    create constraint(:eh_os_contract_subject_keys, :eh_os_contract_subject_keys_version,
             check: "key_version > 0"
           )

    # `mix eh_os_contract.rewrap` looks for the keys a retired master key still wraps.
    create index(:eh_os_contract_subject_keys, [:kek_id])

    create table(:eh_os_contract_erasures, primary_key: false) do
      add :subject_type, :text, primary_key: true
      add :subject_id, :text, primary_key: true
      add :erased_at, :utc_datetime_usec, null: false
      add :requested_by, :text, null: false
    end

    :ok
  end

  @doc false
  @spec down() :: :ok
  def down do
    drop table(:eh_os_contract_erasures)
    drop table(:eh_os_contract_subject_keys)
    :ok
  end
end

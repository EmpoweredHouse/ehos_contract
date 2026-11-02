defmodule EhOsContract.RewrapCommitsTest do
  @moduledoc """
  `mix eh_os_contract.rewrap` beside another run of itself (plan E8a, found by its
  review): a batch skips the keys another transaction holds, so a run that found
  nothing to take may still leave keys on the old master key, and must not say it
  is done. Two transactions need real commits, so this runs on
  `EhOsContract.CommitRepo` and deletes its own rows.
  """

  use ExUnit.Case, async: false

  import Ecto.Query

  alias EhOsContract.CommitRepo, as: Repo
  alias EhOsContract.{Personal, Vault}

  @subject "rewrap-#{System.unique_integer([:positive])}"

  setup do
    configured = Application.get_env(:eh_os_contract, Vault)

    Application.put_env(:eh_os_contract, Vault,
      keys: [
        {"kek-new", Base.encode64(:binary.copy(<<2>>, 32))},
        {"kek-old", Base.encode64(:binary.copy(<<1>>, 32))}
      ]
    )

    Repo.insert_all("eh_os_contract_subject_keys", [
      %{
        subject_type: "member",
        subject_id: @subject,
        key_version: 1,
        kek_id: "kek-old",
        wrapped_key: <<0>>
      }
    ])

    on_exit(fn ->
      Application.put_env(:eh_os_contract, Vault, configured)
      Repo.delete_all(from(k in "eh_os_contract_subject_keys", where: k.subject_id == @subject))
    end)
  end

  test "a key another run holds is not reported as rewrapped" do
    test = self()

    holder =
      spawn_link(fn ->
        Repo.transaction(fn ->
          Repo.all(
            from(k in "eh_os_contract_subject_keys",
              where: k.subject_id == @subject,
              lock: "FOR UPDATE",
              select: k.subject_id
            )
          )

          send(test, :holding)

          receive do
            :release -> :ok
          end
        end)
      end)

    assert_receive :holding

    assert_raise ArgumentError,
                 ~r/0 data keys rewrapped, and 1 are still wrapped by another master key/,
                 fn ->
                   Personal.rewrap!(Repo, "kek-new")
                 end

    send(holder, :release)
  end
end

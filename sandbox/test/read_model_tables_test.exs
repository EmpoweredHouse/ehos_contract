defmodule EhOsContractHost.ReadModelTablesTest do
  @moduledoc """
  The host's read models that name a table, held to their contracts against the test
  database every migration has run on, as an application's own test would be (#493).
  """

  use EhOsContractHost.DataCase, async: false

  test "every read model's table fits its contract" do
    assert EhOsContract.Testing.assert_read_model_tables() == :ok
  end

  # The control: it reads the table, so a column the contract needs and the table lost
  # fails it. The change is the test transaction's, rolled back with it.
  test "a column the member directory lost fails it" do
    EhOsContractHost.Repo.query!("ALTER TABLE lending_member_directory DROP COLUMN email")

    error = assert_raise ExUnit.AssertionError, &EhOsContract.Testing.assert_read_model_tables/0

    assert error.message =~
             "read model :member_directory of Lending.Contracts.Membership: column email is missing"
  end
end

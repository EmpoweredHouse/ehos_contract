defmodule EhOsContract.Auth.DirectoryTypesTest do
  @moduledoc """
  #475: every implementation of `People.Directory` and `Grants.Granter` but EHOS's answers
  what the callbacks' types allow, each called through `Hammox.protect/3`, which raises on
  an argument or an answer outside them. A host's Hammox mock stubbed with one of them
  checks the same, but `stub_with/2` checks nothing by itself, so these are held here.
  EHOS's own are held to EHOS's answers by `people_test.exs` and `grants_test.exs`.
  """

  use ExUnit.Case, async: true

  import EhOsContract.Auth.Testing, only: [stub_people: 1, stub_grants: 1]

  alias EhOsContract.Auth.Grants.{Granter, Local}
  alias EhOsContract.Auth.People.Directory
  alias EhOsContract.Auth.People.Directory.{Static, Unconfigured}
  alias EhOsContract.Auth.Testing

  @ada %{id: "6f1c0a1e-0000-4000-8000-000000000001", email: "ada@example.com", name: "Ada"}
  @directories [Static, Unconfigured, Testing.People]
  @granters [Local, EhOsContract.Auth.Grants.Unconfigured, Testing.Grants]

  for directory <- @directories do
    test "#{inspect(directory)} answers within People.Directory's types" do
      stub_people([@ada])

      %{list_1: list, get_1: get} =
        Hammox.protect(unquote(directory), Directory, list: 1, get: 1)

      for opts <- [
            [],
            [q: "ad", state: [:invited, :joined], limit: 50],
            [after: Base.url_encode64("after=c", padding: false)]
          ],
          do: list.(opts)

      get.(@ada.id)
      get.("6f1c0a1e-0000-4000-8000-00000000000f")
    end
  end

  for granter <- @granters do
    test "#{inspect(granter)} answers within Grants.Granter's types" do
      %{grant_2: grant, revoke_3: revoke} =
        Hammox.protect(unquote(granter), Granter, grant: 2, revoke: 3)

      grant.(%{}, email: "ada@example.com", name: "Ada", role: "clinic.client")
      revoke.(%{}, @ada.id, "clinic.client")
    end
  end

  test "the tests' stand-ins answer a refusal within the types too" do
    stub_people({:error, :not_agreed})
    stub_grants({:error, :beyond_rule})

    %{list_1: list} = Hammox.protect(Testing.People, Directory, list: 1)
    %{grant_2: grant} = Hammox.protect(Testing.Grants, Granter, grant: 2)

    assert list.([]) == {:error, :not_agreed}
    assert grant.(%{}, email: "ada@example.com", role: "clinic.client") == {:error, :beyond_rule}
  end

  test "a reason outside the types is caught, as a host's mock would catch it" do
    stub_people({:error, :timeout})
    %{list_1: list} = Hammox.protect(Testing.People, Directory, list: 1)

    assert_raise Hammox.TypeMatchError, fn -> list.([]) end
  end
end

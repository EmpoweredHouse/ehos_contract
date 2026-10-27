defmodule EhOsContract.Auth.Testing.People do
  @moduledoc """
  The `EhOsContract.Auth.People.Directory` of a host's tests: the people
  `EhOsContract.Auth.Testing.stub_people/1` gave the test, nobody when it gave none. It
  answers as `EhOsContract.Auth.People.Directory.Static` does over them.

      # config/test.exs
      config :eh_os_contract_auth, people_directory: EhOsContract.Auth.Testing.People
  """

  @behaviour EhOsContract.Auth.People.Directory

  alias EhOsContract.Auth.People
  alias EhOsContract.Auth.People.Directory.Static
  alias EhOsContract.Auth.People.Person
  alias EhOsContract.Auth.Testing

  @impl true
  @doc "The test's people `opts` match, on one page."
  @spec list([People.list_option()]) ::
          {:ok, %{people: [Person.t()], next: nil}} | {:error, People.reason()}
  def list(opts \\ []) do
    case Testing.stubbed(:people, []) do
      {:error, reason} -> {:error, reason}
      people -> Static.list(opts, people)
    end
  end

  @impl true
  @doc "The test's person `id` names."
  @spec get(String.t()) :: {:ok, Person.t()} | {:error, People.reason()}
  def get(id) do
    case Testing.stubbed(:people, []) do
      {:error, reason} -> {:error, reason}
      people -> Static.get(id, people)
    end
  end
end

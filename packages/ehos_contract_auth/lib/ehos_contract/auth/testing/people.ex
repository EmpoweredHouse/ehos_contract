defmodule EhosContract.Auth.Testing.People do
  @moduledoc """
  The `EhosContract.Auth.People.Directory` of a host's tests: the people
  `EhosContract.Auth.Testing.stub_people/1` gave the test, nobody when it gave none. It
  answers as `EhosContract.Auth.People.Directory.Static` does over them.

      # config/test.exs
      config :ehos_contract_auth, people_directory: EhosContract.Auth.Testing.People
  """

  @behaviour EhosContract.Auth.People.Directory

  alias EhosContract.Auth.People
  alias EhosContract.Auth.People.Directory.Static
  alias EhosContract.Auth.People.Person
  alias EhosContract.Auth.Testing

  @impl true
  @doc "The test's people `opts` match, on one page."
  @spec list([People.list_option()]) ::
          {:ok, %{people: [Person.t()], next: nil}} | {:error, People.reason()}
  def list(opts \\ []) do
    case Testing.stubbed!(:people, []) do
      {:error, reason} -> {:error, reason}
      people -> Static.list(opts, people)
    end
  end

  @impl true
  @doc "The test's person `id` names."
  @spec get(String.t()) :: {:ok, Person.t()} | {:error, People.reason()}
  def get(id) do
    case Testing.stubbed!(:people, []) do
      {:error, reason} -> {:error, reason}
      people -> Static.get(id, people)
    end
  end
end

defmodule EhOsContract.Auth.People.Directory.Static do
  @moduledoc """
  The people the configuration lists, for development: an
  `EhOsContract.Auth.People.Directory` that never calls EHOS.

      # config/dev.exs
      config :eh_os_contract_auth,
        people_directory: EhOsContract.Auth.People.Directory.Static

      config :eh_os_contract_auth, EhOsContract.Auth.People.Directory.Static,
        people: [
          %{id: "6f1c0a1e-0000-4000-8000-000000000001", email: "ada@example.com", name: "Ada Lovelace"},
          %{id: "6f1c0a1e-0000-4000-8000-000000000002", email: "alan@example.com"}
        ]

  A person is a map with `id` and `email`, and optionally `name` and `state` (`:joined`
  when not given), or an `EhOsContract.Auth.People.Person`. Nobody when `people:` is not
  set.

  `list/1` reads options as EHOS does: `q:`, a prefix of the name or the email, either
  case; `state:`, the invited, the joined or both, never the disabled. It answers every
  person that matches on one page, in the order of their email, whatever `limit:` says,
  and so `after:` answers an empty page. `get/1` finds a disabled person too.

  `list/2` and `get/2` answer the same over the people given instead of the configured.

  Raises `ArgumentError` for an option `EhOsContract.Auth.People.list/1` does not take,
  and for a person without an `id` or an `email`.
  """

  @behaviour EhOsContract.Auth.People.Directory

  alias EhOsContract.Auth.People
  alias EhOsContract.Auth.People.Person

  @listed ~w(invited joined)a

  @impl true
  @doc "The configured people `opts` match, on one page."
  @spec list([People.list_option()]) ::
          {:ok, %{people: [Person.t()], next: nil}}
  def list(opts \\ []), do: list(opts, configured())

  @impl true
  @doc "The configured person `id` names."
  @spec get(String.t()) :: {:ok, Person.t()} | {:error, :not_found}
  def get(id), do: get(id, configured())

  @doc "The people of `people` that `opts` match, on one page."
  @spec list([People.list_option()], [map() | Person.t()]) ::
          {:ok, %{people: [Person.t()], next: nil}}
  def list(opts, people) when is_list(opts) and is_list(people) do
    unless Keyword.keyword?(opts) and
             Keyword.keys(opts) -- [:q, :state, :limit, :after, :server] == [] do
      raise ArgumentError, "list/1 takes q:, state:, limit:, or after: alone"
    end

    people = Enum.map(people, &person!/1)

    listed =
      if Keyword.has_key?(opts, :after) do
        []
      else
        q = opts |> Keyword.get(:q, "") |> String.downcase()
        states = opts |> Keyword.get(:state, @listed) |> List.wrap()

        people
        |> Enum.filter(&(&1.state in states and &1.state in @listed and matches?(&1, q)))
        |> Enum.sort_by(& &1.email)
      end

    {:ok, %{people: listed, next: nil}}
  end

  @doc "The person of `people` that `id` names."
  @spec get(String.t(), [map() | Person.t()]) :: {:ok, Person.t()} | {:error, :not_found}
  def get(id, people) when is_binary(id) and is_list(people) do
    case people |> Enum.map(&person!/1) |> Enum.find(&(&1.id == id)) do
      nil -> {:error, :not_found}
      person -> {:ok, person}
    end
  end

  defp configured do
    :eh_os_contract_auth |> Application.get_env(__MODULE__, []) |> Keyword.get(:people, [])
  end

  defp matches?(_person, ""), do: true

  defp matches?(%Person{email: email, name: name}, q),
    do:
      String.starts_with?(String.downcase(email), q) or
        String.starts_with?(String.downcase(name || ""), q)

  defp person!(%Person{} = person), do: person

  defp person!(%{id: id, email: email} = person) when is_binary(id) and is_binary(email),
    do: %Person{
      id: id,
      email: email,
      name: Map.get(person, :name),
      state: Map.get(person, :state, :joined)
    }

  defp person!(other),
    do: raise(ArgumentError, "a person is a map with id: and email:, not #{inspect(other)}")
end

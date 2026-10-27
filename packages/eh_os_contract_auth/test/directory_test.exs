defmodule EhOsContract.Auth.DirectoryTest do
  @moduledoc """
  #475: who answers about people and who grants roles where EHOS does not, which
  TaxVision and Rehmed each wrote, and the choice between them read at each call.

  Not async: the choice is `config :eh_os_contract_auth`.
  """

  use ExUnit.Case, async: false

  import EhOsContract.Auth.Testing, only: [stub_people: 1, stub_grants: 1]

  alias EhOsContract.Auth.{Grants, People}
  alias EhOsContract.Auth.Grants.{Grant, Local}
  alias EhOsContract.Auth.People.Directory.{Static, Unconfigured}
  alias EhOsContract.Auth.People.Person
  alias EhOsContract.Auth.Testing

  @ada %{id: "6f1c0a1e-0000-4000-8000-000000000001", email: "ada@example.com", name: "Ada"}
  @alan %{
    id: "6f1c0a1e-0000-4000-8000-000000000002",
    email: "alan@example.com",
    state: :invited
  }
  @grace %{
    id: "6f1c0a1e-0000-4000-8000-000000000003",
    email: "grace@example.com",
    name: "Grace",
    state: :disabled
  }
  @uuid ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-8[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/

  setup do
    previous = Application.get_all_env(:eh_os_contract_auth)

    on_exit(fn ->
      for {key, _value} <- Application.get_all_env(:eh_os_contract_auth),
          not Keyword.has_key?(previous, key),
          do: Application.delete_env(:eh_os_contract_auth, key)

      Application.put_all_env(eh_os_contract_auth: previous)
    end)

    for key <- [:people_directory, :granter, :workload, :people, :sign_in],
        do: Application.delete_env(:eh_os_contract_auth, key)

    :ok
  end

  describe "the choice" do
    test "EHOS's when its credentials are configured, the unconfigured one when not" do
      assert People.directory() == Unconfigured
      assert Grants.granter() == Grants.Unconfigured

      Application.put_env(:eh_os_contract_auth, :workload, client_id: "x")
      Application.put_env(:eh_os_contract_auth, :sign_in, client_id: "x")
      assert People.directory() == People
      assert Grants.granter() == Grants

      Application.delete_env(:eh_os_contract_auth, :workload)
      Application.put_env(:eh_os_contract_auth, :people, client_id: "x")
      assert People.directory() == People
    end

    test "the configured one over either, read at each call" do
      Application.put_env(:eh_os_contract_auth, :workload, client_id: "x")
      Application.put_env(:eh_os_contract_auth, :people_directory, Static)
      Application.put_env(:eh_os_contract_auth, :granter, Local)

      assert People.directory() == Static
      assert Grants.granter() == Local
    end

    test "anything but a module raises" do
      Application.put_env(:eh_os_contract_auth, :people_directory, "Static")
      assert_raise ArgumentError, ~r/people_directory: takes a module/, &People.directory/0

      Application.put_env(:eh_os_contract_auth, :granter, [Local])
      assert_raise ArgumentError, ~r/granter: takes a module/, &Grants.granter/0
    end
  end

  describe "the unconfigured" do
    test "answer :unavailable, never an empty list or a grant made" do
      assert Unconfigured.list(q: "a") == {:error, :unavailable}
      assert Unconfigured.get(@ada.id) == {:error, :unavailable}
      assert Grants.Unconfigured.grant(%{}, email: "a@b.c", role: "x.y") == {:error, :unavailable}
      assert Grants.Unconfigured.revoke(%{}, @ada.id, "x.y") == {:error, :unavailable}
    end
  end

  describe "Static" do
    test "lists the configured people, never the disabled, in the order of their email" do
      Application.put_env(:eh_os_contract_auth, Static, people: [@grace, @alan, @ada])

      assert {:ok, %{people: [ada, alan], next: nil}} = Static.list()

      assert %Person{id: "6f1c0a1e-0000-4000-8000-000000000001", name: "Ada", state: :joined} =
               ada

      assert %Person{name: nil, state: :invited} = alan

      assert {:ok, %Person{state: :disabled}} = Static.get(@grace.id)
      assert Static.get("6f1c0a1e-0000-4000-8000-00000000000f") == {:error, :not_found}
    end

    test "reads q:, state: and after: as EHOS does" do
      people = [@ada, @alan, @grace]

      assert {:ok, %{people: [%{email: "ada@example.com"}]}} = Static.list([q: "AD"], people)
      assert {:ok, %{people: [%{email: "alan@example.com"}]}} = Static.list([q: "al"], people)
      assert {:ok, %{people: []}} = Static.list([q: "gr"], people)
      assert {:ok, %{people: [%{state: :invited}]}} = Static.list([state: :invited], people)
      assert {:ok, %{people: [_, _]}} = Static.list([limit: 1], people)
      assert {:ok, %{people: [], next: nil}} = Static.list([after: "cursor"], people)
    end

    test "nobody when the configuration lists nobody" do
      assert Static.list() == {:ok, %{people: [], next: nil}}
    end

    test "raises for an option EHOS's does not take, and for a person without an id" do
      assert_raise ArgumentError, ~r/list\/1 takes/, fn -> Static.list([page: 2], []) end
      assert_raise ArgumentError, ~r/id: and email:/, fn -> Static.list([], [%{email: "a"}]) end
    end
  end

  describe "Local" do
    test "answers a grant as made, with an id derived from the email and never the email" do
      assert {:ok, %Grant{} = grant} =
               Local.grant(%{}, email: "Ada@Example.com", name: "Ada", role: "clinic.client")

      assert %Grant{
               email: "Ada@Example.com",
               state: :invited,
               role: "clinic.client",
               bound: :now,
               delivery: :mailed
             } = grant

      assert grant.person_id =~ @uuid
      assert grant.role_binding_id =~ @uuid
      assert grant.person_id == Local.person_id("ada@example.com")
      refute grant.person_id =~ "ada"

      assert {:ok, %{role_binding_id: binding, role: "clinic.client"}} =
               Local.revoke(%{}, grant.person_id, "clinic.client")

      assert binding == grant.role_binding_id
    end

    test "raises where EHOS's would" do
      assert_raise ArgumentError, ~r/grant\/3 takes/, fn -> Local.grant(%{}, email: "") end
      assert_raise ArgumentError, ~r/revoke\/3 takes/, fn -> Local.revoke(%{}, 7, "x.y") end
    end
  end

  describe "the tests' stand-ins" do
    test "nobody and every grant made until the test says otherwise" do
      assert Testing.People.list() == {:ok, %{people: [], next: nil}}
      assert {:ok, %Grant{}} = Testing.Grants.grant(%{}, email: "a@b.c", role: "x.y")

      stub_people([@ada])
      stub_grants({:error, :beyond_rule})

      assert {:ok, %{people: [%Person{email: "ada@example.com"}]}} = Testing.People.list(q: "a")
      assert {:ok, %Person{}} = Testing.People.get(@ada.id)
      assert Testing.Grants.grant(%{}, email: "a@b.c", role: "x.y") == {:error, :beyond_rule}
      assert Testing.Grants.revoke(%{}, @ada.id, "x.y") == {:error, :beyond_rule}

      stub_people({:error, :not_agreed})
      assert Testing.People.list() == {:error, :not_agreed}
      assert Testing.People.get(@ada.id) == {:error, :not_agreed}
    end

    test "what a test says reaches the processes it starts, and no other" do
      stub_people([@ada])

      assert Task.async(fn -> Testing.People.list() end) |> Task.await() ==
               Testing.People.list()

      stranger = spawn_link(fn -> receive do: (pid -> send(pid, Testing.People.list())) end)
      send(stranger, self())
      assert_receive {:ok, %{people: []}}
    end
  end

  describe "all/1" do
    defmodule Pages do
      @behaviour EhOsContract.Auth.People.Directory

      @impl true
      def list(opts) do
        send(self(), {:asked, opts})

        case Keyword.get(opts, :after) do
          nil -> {:ok, %{people: [person(1), person(2)], next: "2"}}
          "2" -> {:ok, %{people: [person(3)], next: "3"}}
          "3" -> {:error, :rate_limited}
        end
      end

      @impl true
      def get(_id), do: {:error, :not_found}

      def person(n),
        do: %Person{id: "#{n}", email: "#{n}@example.com", name: nil, state: :joined}
    end

    test "reads page after page, through the directory chosen" do
      stub_people([@alan, @ada])
      Application.put_env(:eh_os_contract_auth, :people_directory, Testing.People)

      assert {:ok, [%{email: "ada@example.com"}, %{email: "alan@example.com"}]} = People.all()
    end

    test "carries q: and state: to the first page only, and answers a page's refusal" do
      assert People.all(directory: Pages, q: "x", state: :joined) == {:error, :rate_limited}
      assert_received {:asked, [limit: 500, q: "x", state: :joined]}
      assert_received {:asked, [after: "2"]}
      assert_received {:asked, [after: "3"]}
    end

    test "answers :too_many past max:, never a list cut short" do
      assert People.all(directory: Pages, max: 2) == {:error, :too_many}
    end

    test "raises for an option it does not take" do
      assert_raise ArgumentError, ~r/all\/1 takes/, fn -> People.all(limit: 5) end
      assert_raise ArgumentError, ~r/all\/1 takes/, fn -> People.all(max: 0) end
    end
  end
end

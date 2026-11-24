defmodule EhosContract.Auth.DirectoryTest do
  @moduledoc """
  #475: who answers about people and who grants roles where EHOS does not, which
  TaxVision and Rehmed each wrote, and the choice between them read at each call.

  Not async: the choice is `config :ehos_contract_auth`.
  """

  use ExUnit.Case, async: false

  import EhosContract.Auth.Testing, only: [stub_people: 1, stub_grants: 1]

  alias EhosContract.Auth.{Grants, People}
  alias EhosContract.Auth.Grants.{Grant, Local}
  alias EhosContract.Auth.People.Directory.{Static, Unconfigured}
  alias EhosContract.Auth.People.Person
  alias EhosContract.Auth.Testing

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
    previous = Application.get_all_env(:ehos_contract_auth)

    on_exit(fn ->
      for {key, _value} <- Application.get_all_env(:ehos_contract_auth),
          not Keyword.has_key?(previous, key),
          do: Application.delete_env(:ehos_contract_auth, key)

      Application.put_all_env(ehos_contract_auth: previous)
    end)

    for key <- [:people_directory, :granter, :workload, :people, :sign_in],
        do: Application.delete_env(:ehos_contract_auth, key)

    :ok
  end

  describe "the choice" do
    test "EHOS's when its credentials are configured, the unconfigured one when not" do
      assert People.directory() == Unconfigured
      assert Grants.granter() == Grants.Unconfigured

      Application.put_env(:ehos_contract_auth, :workload, client_id: "x")
      Application.put_env(:ehos_contract_auth, :sign_in, client_id: "x")
      assert People.directory() == People
      assert Grants.granter() == Grants

      Application.delete_env(:ehos_contract_auth, :workload)
      Application.put_env(:ehos_contract_auth, :people, client_id: "x")
      assert People.directory() == People
    end

    test "the configured one over either, read at each call" do
      Application.put_env(:ehos_contract_auth, :people_directory, Static)
      Application.put_env(:ehos_contract_auth, :granter, Local)
      assert People.directory() == Static
      assert Grants.granter() == Local

      Application.put_env(:ehos_contract_auth, :workload, client_id: "x")
      Application.put_env(:ehos_contract_auth, :sign_in, client_id: "x")
      Application.put_env(:ehos_contract_auth, :people_directory, Unconfigured)
      Application.put_env(:ehos_contract_auth, :granter, Grants.Unconfigured)
      assert People.directory() == Unconfigured
      assert Grants.granter() == Grants.Unconfigured
    end

    test "a stand-in where EHOS's credentials are configured raises, as a release answering for EHOS" do
      Application.put_env(:ehos_contract_auth, :workload, client_id: "x")
      Application.put_env(:ehos_contract_auth, :sign_in, client_id: "x")

      for directory <- [Static, Testing.People] do
        Application.put_env(:ehos_contract_auth, :people_directory, directory)
        assert_raise ArgumentError, ~r/a stand-in for development or tests/, &People.directory/0
      end

      for granter <- [Local, Testing.Grants] do
        Application.put_env(:ehos_contract_auth, :granter, granter)
        assert_raise ArgumentError, ~r/a stand-in for development or tests/, &Grants.granter/0
      end
    end

    test "the tests' stand-ins answer only where test keys may be pinned" do
      Application.put_env(:ehos_contract_auth, :pin_keys, false)

      assert_raise ArgumentError, ~r/for tests only/, fn -> Testing.People.list() end

      assert_raise ArgumentError, ~r/for tests only/, fn ->
        Testing.Grants.grant(%{}, email: "a@b.c", role: "x.y")
      end
    end

    test "anything but a module raises" do
      Application.put_env(:ehos_contract_auth, :people_directory, "Static")
      assert_raise ArgumentError, ~r/people_directory: takes a module/, &People.directory/0

      Application.put_env(:ehos_contract_auth, :granter, [Local])
      assert_raise ArgumentError, ~r/granter: takes a module/, &Grants.granter/0

      for value <- [false, NoSuchModule, Local] do
        Application.put_env(:ehos_contract_auth, :people_directory, value)
        assert_raise ArgumentError, ~r/people_directory:/, &People.directory/0
      end

      for value <- [true, NoSuchModule, Static] do
        Application.put_env(:ehos_contract_auth, :granter, value)
        assert_raise ArgumentError, ~r/granter:/, &Grants.granter/0
      end
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
      Application.put_env(:ehos_contract_auth, Static, people: [@grace, @alan, @ada])

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
      cursor = Base.url_encode64("after=c&limit=50", padding: false)
      assert {:ok, %{people: [], next: nil}} = Static.list([after: cursor], people)
    end

    test "nobody when the configuration lists nobody" do
      assert Static.list() == {:ok, %{people: [], next: nil}}
    end

    test "raises for an option EHOS's does not take, and for a person without an id" do
      assert_raise ArgumentError, ~r/list\/1 takes/, fn -> Static.list([page: 2], []) end
      assert_raise ArgumentError, ~r/id: and email:/, fn -> Static.list([], [%{email: "a"}]) end
    end

    test "raises where EHOS's raises, so development fails where a release would" do
      for opts <- [
            [state: :disabled],
            [state: []],
            [limit: 0],
            [limit: 501],
            [q: nil],
            [after: "not a cursor"],
            [after: Base.url_encode64("after=c", padding: false), q: "a"]
          ] do
        assert_raise ArgumentError, fn -> Static.list(opts, []) end
      end
    end

    test "reads ids in lower case and orders emails in either case, as EHOS does" do
      people = [
        %{id: "6F1C-B", email: "Bob@example.com"},
        %{id: "6f1c-a", email: "ann@example.com"}
      ]

      assert {:ok, %{id: "6f1c-b"}} = Static.get("6f1c-B", people)

      assert {:ok, %{people: [%{email: "ann@example.com"}, %{email: "Bob@example.com"}]}} =
               Static.list([], people)
    end

    test "refuses a person of another shape, without their values in the message" do
      for person <- [
            %{id: "a", email: "ada@example.com", state: "joined"},
            %{id: "a", email: "ada@example.com", name: :ada}
          ] do
        error = assert_raise ArgumentError, fn -> Static.list([], [person]) end
        refute error.message =~ "ada"
      end
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

    test "refuses what EHOS refuses without asking a person" do
      assert Local.grant(%{}, email: "a@b.c", role: "client") == {:error, :unknown_role}
      assert Local.revoke(%{}, "nobody", "clinic.client") == {:error, :not_found}

      assert Local.revoke(%{}, Local.person_id("a@b.c"), "clinic/../x") ==
               {:error, :unknown_role}
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

    test "a stub that no call could answer is refused when it is made" do
      for stub <- [{:error}, {:error, :a, :b}, {:error, "unavailable"}] do
        assert_raise FunctionClauseError, fn -> stub_people(stub) end
        assert_raise FunctionClauseError, fn -> stub_grants(stub) end
      end
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
      @behaviour EhosContract.Auth.People.Directory

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
      Application.put_env(:ehos_contract_auth, :people_directory, Testing.People)

      assert {:ok, [%{email: "ada@example.com"}, %{email: "alan@example.com"}]} = People.all()
    end

    test "carries q: and state: to the first page only, and answers a page's refusal" do
      assert People.all(directory: Pages, q: "x", state: :joined) == {:error, :rate_limited}
      assert_received {:asked, [limit: 500, q: "x", state: :joined]}
      assert_received {:asked, [after: "2"]}
      assert_received {:asked, [after: "3"]}
    end

    defmodule Endless do
      @behaviour EhosContract.Auth.People.Directory

      @impl true
      def list([after: "same"] = _opts),
        do: {:ok, %{people: [Pages.person(9)], next: "same"}}

      def list(opts) do
        if opts[:q] == "same",
          do: {:ok, %{people: [Pages.person(8)], next: "same"}},
          else: {:ok, %{people: [], next: "again"}}
      end

      @impl true
      def get(_id), do: {:error, :not_found}
    end

    @tag capture_log: true
    test "answers :unavailable for a page that leads nowhere, never reading for ever" do
      for opts <- [[], [q: "same"]] do
        task = Task.async(fn -> People.all([{:directory, Endless} | opts]) end)
        assert Task.yield(task, 1_000) == {:ok, {:error, :unavailable}}
      end
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

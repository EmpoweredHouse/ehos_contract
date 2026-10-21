defmodule EhOsContract.Auth.SessionsTest do
  @moduledoc """
  EB2a (#78): the rows of people signed in through EHOS (S2, S3 and S11 in
  docs/adr/browser-session.md). The browser's token is stored as its hash, and EHOS's
  tokens only as ciphertexts bound to their row and column, under a key derived from
  `secret_key_base`.

  Not async: the tests change `config :eh_os_contract_auth`.
  """

  use ExUnit.Case, async: false

  alias EhOsContract.Auth.{FakeEhos, TestRepo}
  alias EhOsContract.Auth.SignIn
  alias EhOsContract.Auth.SignIn.Sessions

  @moduletag :tmp_dir

  @own "https://clinic.test"
  @ledger "https://ledger.test.ehos.test"

  setup %{tmp_dir: dir} do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(TestRepo)
    previous = Application.get_all_env(:eh_os_contract_auth)
    on_exit(fn -> restore(previous) end)

    {key_file, _key} = FakeEhos.client_key_file(dir)

    Application.put_env(:eh_os_contract_auth, :sign_in,
      client_id: "clinic/test",
      client_key_file: key_file,
      address: @own,
      secret_key_base: String.duplicate("s", 64),
      applications: %{"ledger" => @ledger}
    )

    %{name: start!(FakeEhos.start())}
  end

  describe "a session" do
    test "is read back as it was written, its credential under the application's address",
         %{name: name} do
      signed_in = signed_in()
      {:ok, token} = Sessions.create(name, signed_in)

      assert {:ok, session} = Sessions.fetch(name, token)
      assert session.subject == "u-anna"
      assert session.sid == signed_in.sid
      assert session.auth_time == DateTime.truncate(signed_in.auth_time, :second)
      assert session.refresh_token == signed_in.refresh_token
      assert session.id_token == signed_in.id_token

      assert session.credentials == %{
               @own => %{
                 token: signed_in.credential.token,
                 expires_at: signed_in.credential.expires_at,
                 refused_until: nil
               }
             }
    end

    test "is named in the browser by a token the table holds only the hash of (S2)",
         %{name: name} do
      {:ok, token} = Sessions.create(name, signed_in())
      {:ok, raw} = Base.url_decode64(token, padding: false)

      assert byte_size(raw) == 32
      assert column("token_hash") == [:crypto.hash(:sha256, raw)]
      refute Enum.any?(dump(), &String.contains?(&1, [token, raw]))
    end

    test "holds no refresh token, ID token or credential in plain text (S3)", %{name: name} do
      signed_in = signed_in()
      {:ok, _token} = Sessions.create(name, signed_in)

      secrets = [signed_in.refresh_token, signed_in.id_token, signed_in.credential.token]
      refute Enum.any?(dump(), &String.contains?(&1, secrets))
    end

    test "is inspected without any token", %{name: name} do
      signed_in = signed_in()
      {:ok, token} = Sessions.create(name, signed_in)
      {:ok, session} = Sessions.fetch(name, token)

      inspected = inspect(session)
      assert inspected =~ "u-anna"
      refute inspected =~ signed_in.refresh_token
      refute inspected =~ signed_in.id_token
      refute inspected =~ signed_in.credential.token
    end

    test "is not found for a token this package did not make", %{name: name} do
      {:ok, _token} = Sessions.create(name, signed_in())

      for token <- [nil, "", "not base64!", Base.url_encode64("short"), random_token()] do
        assert Sessions.fetch(name, token) == {:error, :signed_out}, inspect(token)
      end
    end

    # What a crash report would print: the message, and the stacktrace with any arguments it holds.
    test "a malformed one is refused without the key or any token in what is raised",
         %{name: name} do
      signed_in = signed_in()
      secrets = [signed_in.id_token, signed_in.credential.token, signed_in.sid]
      key = SignIn.config(name).cipher_key

      for broken <- [
            %{signed_in | refresh_token: nil},
            Map.delete(signed_in, :subject),
            Map.delete(signed_in, :credential),
            put_in(signed_in, [:credential, :token], :none),
            :not_a_map
          ] do
        report =
          try do
            Sessions.create(name, broken)
            flunk("created #{inspect(Map.keys(broken))}")
          rescue
            exception ->
              assert %ArgumentError{} = exception
              Exception.format(:error, exception, __STACKTRACE__)
          end

        refute String.contains?(report, secrets), report
        refute report =~ inspect(key, limit: :infinity)
        refute report =~ inspect(:binary.bin_to_list(key))
      end

      assert count("eh_os_contract_auth_sessions") == 0
    end

    # `Plug.Crypto.MessageEncryptor.encrypt/4` guards on a binary, and its failed guard would print
    # the key as an argument.
    test "the cipher refuses what is not a string without printing the key" do
      key = :crypto.strong_rand_bytes(32)

      report =
        try do
          EhOsContract.Auth.SignIn.Cipher.encrypt(nil, key, "h/refresh_token")
        rescue
          exception ->
            assert %ArgumentError{} = exception
            Exception.format(:error, exception, __STACKTRACE__)
        end

      refute report =~ inspect(key, limit: :infinity)
    end

    test "deleted takes its credentials with it, and deleting it again is :ok", %{name: name} do
      {:ok, token} = Sessions.create(name, signed_in())

      assert Sessions.delete(token) == :ok
      assert Sessions.fetch(name, token) == {:error, :signed_out}
      assert count("eh_os_contract_auth_sessions") == 0
      assert count("eh_os_contract_auth_session_credentials") == 0
      assert Sessions.delete(token) == :ok
    end
  end

  describe "a ciphertext that does not decrypt signs the session out, and its row goes" do
    test "when it was moved to another row", %{name: name} do
      {:ok, anna} = Sessions.create(name, signed_in())
      {:ok, bartek} = Sessions.create(name, signed_in(subject: "u-bartek"))

      TestRepo.query!("""
      UPDATE eh_os_contract_auth_sessions
      SET refresh_token = (SELECT refresh_token FROM eh_os_contract_auth_sessions
                           WHERE subject = 'u-anna')
      WHERE subject = 'u-bartek'
      """)

      assert {:ok, _session} = Sessions.fetch(name, anna)
      assert Sessions.fetch(name, bartek) == {:error, :signed_out}
      assert column("subject") == ["u-anna"]
    end

    test "when it was moved to another column of its row", %{name: name} do
      {:ok, token} = Sessions.create(name, signed_in())
      TestRepo.query!("UPDATE eh_os_contract_auth_sessions SET id_token = refresh_token")

      assert Sessions.fetch(name, token) == {:error, :signed_out}
      assert count("eh_os_contract_auth_sessions") == 0
    end

    test "when a credential was moved to another application", %{name: name} do
      {:ok, token} = Sessions.create(name, signed_in())

      TestRepo.query!(
        "UPDATE eh_os_contract_auth_session_credentials SET resource = $1",
        [@ledger]
      )

      assert Sessions.fetch(name, token) == {:error, :signed_out}
      assert count("eh_os_contract_auth_sessions") == 0
    end

    test "when secret_key_base is not the one it was written under", %{name: name} do
      {:ok, token} = Sessions.create(name, signed_in())

      stop_supervised!(name)
      put_sign_in(secret_key_base: String.duplicate("t", 64))
      name = start!(FakeEhos.start())

      assert Sessions.fetch(name, token) == {:error, :signed_out}
      assert count("eh_os_contract_auth_sessions") == 0
    end
  end

  describe "the absolute limit from auth_time, twelve hours unless configured" do
    # Every step under `EhOsContract.Clock`, at a time the real clock has not reached, so the test
    # also shows which clock is read.
    @now ~U[2030-01-01 12:00:00.000000Z]

    test "a session past it is not read, though its row waits for the next sign-in",
         %{name: name} do
      {old, recent} =
        at(-3600, fn ->
          {:ok, old} = Sessions.create(name, signed_in(auth_time: at_offset(-12 * 3600 - 1)))
          {:ok, recent} = Sessions.create(name, signed_in(auth_time: at_offset(-11 * 3600)))
          {old, recent}
        end)

      at(0, fn ->
        assert Sessions.fetch(name, old) == {:error, :signed_out}
        assert {:ok, _session} = Sessions.fetch(name, recent)
      end)

      assert count("eh_os_contract_auth_sessions") == 2
    end

    # No job deletes them: the next sign-in does (S11).
    test "a new sign-in deletes the sessions past it, and only those", %{name: name} do
      at(-3600, fn ->
        {:ok, _old} = Sessions.create(name, signed_in(auth_time: at_offset(-12 * 3600 - 1)))

        {:ok, _recent} =
          Sessions.create(name, signed_in(subject: "u-bartek", auth_time: at_offset(-11 * 3600)))
      end)

      assert count("eh_os_contract_auth_sessions") == 2

      at(0, fn ->
        {:ok, _new} = Sessions.create(name, signed_in(subject: "u-celina", auth_time: @now))
      end)

      assert column("subject") == ["u-bartek", "u-celina"]
    end

    # The installation's limit, given as EHOS_SIGN_IN_ABSOLUTE, replaces twelve hours.
    test "is the configured absolute_limit when the installation sets one", %{name: name} do
      stop_supervised!(name)
      put_sign_in(absolute_limit: 30 * 86_400)
      name = start!(FakeEhos.start())

      {day_old, month_old} =
        at(-3600, fn ->
          {:ok, day_old} = Sessions.create(name, signed_in(auth_time: at_offset(-13 * 3600)))

          {:ok, month_old} =
            Sessions.create(name, signed_in(auth_time: at_offset(-30 * 86_400 - 1)))

          {day_old, month_old}
        end)

      at(0, fn ->
        assert {:ok, _session} = Sessions.fetch(name, day_old)
        assert Sessions.fetch(name, month_old) == {:error, :signed_out}
      end)

      # The next sign-in deletes by the configured limit too: the row a day old stays.
      at(0, fn ->
        {:ok, _new} = Sessions.create(name, signed_in(subject: "u-celina", auth_time: @now))
      end)

      assert count("eh_os_contract_auth_sessions") == 2
    end

    test "is a shorter configured absolute_limit as well", %{name: name} do
      stop_supervised!(name)
      put_sign_in(absolute_limit: 3600)
      name = start!(FakeEhos.start())

      {fresh, stale} =
        at(-60, fn ->
          {:ok, fresh} = Sessions.create(name, signed_in(auth_time: at_offset(-30 * 60)))
          {:ok, stale} = Sessions.create(name, signed_in(auth_time: at_offset(-2 * 3600)))
          {fresh, stale}
        end)

      at(0, fn ->
        assert {:ok, _session} = Sessions.fetch(name, fresh)
        assert Sessions.fetch(name, stale) == {:error, :signed_out}
      end)
    end
  end

  # S3 keeps a reader of the database out; these keep a writer from making a row someone else's.
  describe "a plain column changed in the table makes its session one that does not decrypt" do
    for {column, value} <- [
          {"subject", "'u-bartek'"},
          {"sid", "'sid-other'"},
          {"auth_time", "auth_time + interval '1 hour'"}
        ] do
      test "for #{column}", %{name: name} do
        {:ok, token} = Sessions.create(name, signed_in())

        TestRepo.query!(
          "UPDATE eh_os_contract_auth_sessions SET #{unquote(column)} = #{unquote(value)}"
        )

        assert Sessions.fetch(name, token) == {:error, :signed_out}
        assert count("eh_os_contract_auth_sessions") == 0
      end
    end
  end

  defp at(offset, fun), do: EhOsContract.Clock.at(DateTime.add(@now, offset), fun)
  defp at_offset(offset), do: DateTime.add(@now, offset)

  defp signed_in(overrides \\ []) do
    secret = fn -> Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false) end

    Map.merge(
      %{
        subject: "u-anna",
        sid: "sid-" <> secret.(),
        auth_time: DateTime.utc_now(),
        refresh_token: "rt-" <> secret.(),
        id_token: "id-" <> secret.(),
        credential: %{
          resource: @own,
          token: "cr-" <> secret.(),
          expires_at: DateTime.add(DateTime.utc_now(), 600) |> DateTime.truncate(:microsecond)
        }
      },
      Map.new(overrides)
    )
  end

  defp random_token, do: Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

  # Every value of both tables, as text: what a backup or a dump would hold.
  defp dump do
    for table <- ["eh_os_contract_auth_sessions", "eh_os_contract_auth_session_credentials"],
        row <- TestRepo.query!("SELECT * FROM #{table}").rows,
        value <- row,
        value != nil,
        do: if(is_binary(value), do: value, else: inspect(value))
  end

  defp column(name) do
    TestRepo.query!("SELECT #{name} FROM eh_os_contract_auth_sessions ORDER BY id").rows
    |> List.flatten()
  end

  defp count(table), do: TestRepo.query!("SELECT count(*) FROM #{table}").rows |> hd() |> hd()

  defp start!(ehos) do
    name = :"sign_in_#{System.unique_integer([:positive])}"
    start_supervised!({SignIn, [name: name, plug: FakeEhos.plug(ehos)]})
    :sys.get_state(name)
    name
  end

  defp put_sign_in(changes) do
    sign_in = Application.fetch_env!(:eh_os_contract_auth, :sign_in)
    Application.put_env(:eh_os_contract_auth, :sign_in, Keyword.merge(sign_in, changes))
  end

  defp restore(previous) do
    for {key, _value} <- Application.get_all_env(:eh_os_contract_auth),
        not Keyword.has_key?(previous, key),
        do: Application.delete_env(:eh_os_contract_auth, key)

    for {key, value} <- previous, do: Application.put_env(:eh_os_contract_auth, key, value)
  end
end

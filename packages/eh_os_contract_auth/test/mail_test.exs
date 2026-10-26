defmodule EhOsContract.Auth.MailTest do
  @moduledoc """
  #436: the application sends mail through EHOS as itself. The fake EHOS here
  answers as EHOS's `EhosWeb.MailController` does on its `main` of 24 October 2026: 200
  `{"messages": [...]}`, one per recipient, or a refusal `{"error", "message", "reasons"}`.
  The credential is `EhOsContract.Auth.Workload`'s, whose renewal `people_test.exs` covers.

  Not async: the tests change `config :eh_os_contract_auth`.
  """

  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias EhOsContract.Auth.{FakeEhos, Mail, People, Workload}
  alias EhOsContract.Auth.Mail.Result

  @moduletag :tmp_dir

  @ada "6f1c0a1e-0000-4000-8000-000000000001"

  setup %{tmp_dir: dir} do
    previous = Application.get_all_env(:eh_os_contract_auth)
    on_exit(fn -> restore(previous) end)

    {key_file, _key} = FakeEhos.client_key_file(dir)

    Application.put_env(:eh_os_contract_auth, :workload,
      client_id: "office/test",
      client_key_file: key_file
    )

    {:ok, ehos} =
      Agent.start_link(fn -> %{answer: :sent, tokens: [], bodies: [], expired_once: false} end)

    %{ehos: ehos, dir: dir, key_file: key_file}
  end

  defp start!(ehos) do
    name = :"workload_#{System.unique_integer([:positive])}"
    start_supervised!({Workload, name: name, plug: &serve(ehos, &1)})
    name
  end

  defp set(ehos, changes), do: Agent.update(ehos, &Map.merge(&1, changes))
  defp ehos(ehos, key), do: Agent.get(ehos, &Map.fetch!(&1, key))

  ## EHOS, as far as the mail client reaches it

  defp serve(ehos, %{request_path: "/oauth/token"} = conn) do
    if ehos(ehos, :answer) == :not_asked,
      do: answer(conn, 400, %{"error" => "unauthorized_client"}),
      else: token(ehos, conn)
  end

  defp serve(ehos, %{method: "POST", request_path: "/api/v1/mail"} = conn),
    do: mail_api(ehos, conn)

  defp serve(_ehos, conn), do: answer(conn, 404, %{"error" => "not_found"})

  defp token(ehos, conn) do
    token =
      Agent.get_and_update(ehos, fn state ->
        token = "credential-#{length(state.tokens) + 1}"
        {token, %{state | tokens: state.tokens ++ [token]}}
      end)

    Req.Test.json(conn, %{"access_token" => token, "token_type" => "Bearer", "expires_in" => 600})
  end

  defp mail_api(ehos, conn) do
    {:ok, body, conn} = Plug.Conn.read_body(conn, length: 20_000_000)
    state = Agent.get(ehos, & &1)
    token = conn |> Plug.Conn.get_req_header("authorization") |> List.first()

    cond do
      state.answer == :expired and not state.expired_once ->
        set(ehos, %{expired_once: true})
        answer(conn, 401, %{"error" => "unauthorized"})

      # As EHOS's parser answers, before the route, in Phoenix's own shape.
      state.answer in [413, 400] ->
        answer(conn, state.answer, %{"errors" => %{"detail" => "Bad Request"}})

      state.answer == :always_401 ->
        answer(conn, 401, %{"error" => "unauthorized"})

      # #451: an exception inside the request, holding its credential, as one may.
      state.answer == :raise ->
        raise "the request failed with authorization #{token}"

      # #451: the connection, refused before anything is written, or cut off after.
      match?({:transport, _reason}, state.answer) ->
        {:transport, reason} = state.answer
        Req.Test.transport_error(conn, reason)

      token != "Bearer " <> List.last(state.tokens) ->
        answer(conn, 401, %{"error" => "unauthorized"})

      true ->
        assert ["application/json" <> _] = Plug.Conn.get_req_header(conn, "content-type")
        Agent.update(ehos, &%{&1 | bodies: &1.bodies ++ [Jason.decode!(body)]})
        mail(conn, state.answer, Jason.decode!(body))
    end
  end

  defp mail(conn, answer, body) when answer in [:sent, :expired] do
    messages =
      body["to"]
      |> Enum.with_index()
      |> Enum.map(fn
        {to, 0} ->
          %{
            "to" => to,
            "sent" => true,
            "message_id" => "<a1@office.example.org>",
            "relay_response" => "2.0.0 OK queued as 4F2"
          }

        {to, _index} ->
          %{
            "to" => to,
            "sent" => false,
            "message_id" => "<a2@office.example.org>",
            "reason" => "the relay did not take it"
          }
      end)

    Req.Test.json(conn, %{"messages" => messages})
  end

  defp mail(conn, {status, error}, _body),
    do: answer(conn, status, %{"error" => error, "message" => "…", "reasons" => ["to[0]: no"]})

  defp mail(conn, :garbage, _body), do: Req.Test.json(conn, %{"messages" => [%{"sent" => 1}]})

  defp answer(conn, status, body),
    do: conn |> Plug.Conn.put_status(status) |> Req.Test.json(body)

  ## The tests

  describe "sending" do
    test "sends the message as EHOS's mail API reads it, and answers per recipient",
         %{ehos: ehos} do
      server = start!(ehos)
      pdf = <<"%PDF-1.7", 0, 255>>

      assert {:ok, [first, second]} =
               Mail.deliver(
                 server: server,
                 to: [{:person, @ada}, {:address, "client@example.org"}],
                 subject: "A document waits for your approval",
                 text: "Open it.",
                 html: "<p>Open it.<img src=\"cid:logo\"></p>",
                 verify_html: true,
                 reply_to: {:address, "t-42@reply.office.example.org"},
                 in_reply_to: ["<t-42-1@reply.office.example.org>"],
                 references: ["<t-42-1@reply.office.example.org>"],
                 attachments: [
                   %{filename: "approval.pdf", content_type: "application/pdf", content: pdf},
                   %{
                     filename: "logo.png",
                     content_type: "image/png",
                     content: "png",
                     inline: true,
                     content_id: "logo"
                   }
                 ]
               )

      assert first == %Result{
               to: {:person, @ada},
               sent?: true,
               message_id: "<a1@office.example.org>",
               relay_response: "2.0.0 OK queued as 4F2"
             }

      assert second == %Result{
               to: {:address, "client@example.org"},
               sent?: false,
               message_id: "<a2@office.example.org>",
               reason: "the relay did not take it"
             }

      assert ehos(ehos, :bodies) == [
               %{
                 "to" => [%{"person" => @ada}, %{"address" => "client@example.org"}],
                 "subject" => "A document waits for your approval",
                 "text" => "Open it.",
                 "html" => "<p>Open it.<img src=\"cid:logo\"></p>",
                 "verify_html" => true,
                 "reply_to" => %{"address" => "t-42@reply.office.example.org"},
                 "in_reply_to" => ["<t-42-1@reply.office.example.org>"],
                 "references" => ["<t-42-1@reply.office.example.org>"],
                 "attachments" => [
                   %{
                     "filename" => "approval.pdf",
                     "content_type" => "application/pdf",
                     "content" => Base.encode64(pdf)
                   },
                   %{
                     "filename" => "logo.png",
                     "content_type" => "image/png",
                     "content" => Base.encode64("png"),
                     "inline" => true,
                     "content_id" => "logo"
                   }
                 ]
               }
             ]
    end

    test "shares the credential with the people client", %{ehos: ehos} do
      server = start!(ehos)
      message = [server: server, to: [{:person, @ada}], subject: "s", text: "t"]

      assert {:ok, [_]} = Mail.deliver(message)
      assert {:ok, [_]} = Mail.deliver(message)
      assert ehos(ehos, :tokens) == ["credential-1"]

      # People's calls go to the same process; this EHOS answers them 404.
      capture_log(fn -> People.list(server: server) end)
      assert ehos(ehos, :tokens) == ["credential-1"]
    end

    test "takes a new credential once when EHOS answers 401", %{ehos: ehos} do
      set(ehos, %{answer: :expired})
      server = start!(ehos)

      assert {:ok, [_]} =
               Mail.deliver(server: server, to: [{:person, @ada}], subject: "s", text: "t")

      assert ehos(ehos, :tokens) == ["credential-1", "credential-2"]
      assert length(ehos(ehos, :bodies)) == 1
    end

    test "keeps its credential when EHOS answers 413, which the people's calls go on with",
         %{ehos: ehos} do
      server = start!(ehos)
      message = [server: server, to: [{:person, @ada}], subject: "s", text: "t"]
      assert {:ok, [_]} = Mail.deliver(message)

      set(ehos, %{answer: 413})
      assert {:error, {:invalid, [_]}} = Mail.deliver(message)
      assert ehos(ehos, :tokens) == ["credential-1"]
    end

    test "sends verify_html: as given, and nothing of it when it is left out", %{ehos: ehos} do
      server = start!(ehos)
      ok = [to: [{:person, @ada}], subject: "s", text: "t", html: "<p>t</p>"]

      assert {:ok, _} = Mail.deliver([server: server, verify_html: false] ++ ok)
      assert {:ok, _} = Mail.deliver([server: server] ++ ok)

      assert [%{"verify_html" => false}, without] = ehos(ehos, :bodies)
      refute Map.has_key?(without, "verify_html")
    end

    test "refuses, before asking EHOS, what is not a message", %{ehos: ehos} do
      server = start!(ehos)
      ok = [to: [{:person, @ada}], subject: "s", text: "t"]
      file = %{filename: "a.txt", content_type: "text/plain", content: "a"}

      for message <- [
            [subject: "s", text: "t"],
            Keyword.delete(ok, :subject),
            Keyword.delete(ok, :text),
            Keyword.put(ok, :to, []),
            Keyword.put(ok, :to, [@ada]),
            Keyword.put(ok, :to, [{:group, "x"}]),
            Keyword.put(ok, :subject, :s),
            Keyword.put(ok, :html, 1),
            Keyword.put(ok, :verify_html, "yes"),
            Keyword.put(ok, :reply_to, "a@b.c"),
            Keyword.put(ok, :in_reply_to, "<a@b>"),
            Keyword.put(ok, :references, [1]),
            Keyword.put(ok, :attachments, file),
            Keyword.put(ok, :attachments, [Map.delete(file, :content)]),
            Keyword.put(ok, :attachments, [Map.put(file, :inline, "yes")]),
            Keyword.put(ok, :attachments, [Map.put(file, :path, "/etc/passwd")]),
            Keyword.put(ok, :cc, [{:person, @ada}]),
            ok ++ [to: [{:person, @ada}]],
            [server: server] ++ ok,
            Keyword.put(ok, :to, [{:person, @ada} | {:address, "secret@example.org"}]),
            Keyword.put(ok, :references, ["<a@b>" | "<c@d>"]),
            Keyword.put(ok, :attachments, [Map.put(file, :filename, <<0xE9>>)])
          ] do
        assert_raise ArgumentError, fn -> Mail.deliver([server: server] ++ message) end
      end

      assert_raise ArgumentError, fn -> Mail.deliver(Map.new(ok)) end

      # A string JSON cannot carry is refused by its option's name: its value, a body or an
      # address, never reaches the message, nor a crash report.
      for {key, value} <- [text: "caf" <> <<0xE9>> <> " secret", to: [{:address, <<0xE9>>}]] do
        error =
          assert_raise ArgumentError, fn ->
            Mail.deliver([server: server] ++ Keyword.put(ok, key, value))
          end

        refute error.message =~ "secret"
        refute error.message =~ <<0xE9>>
      end

      assert ehos(ehos, :tokens) == []
    end
  end

  describe "refusals, each an error a page can say" do
    test "each of EHOS's refusals", %{ehos: ehos} do
      server = start!(ehos)
      message = [server: server, to: [{:person, @ada}], subject: "s", text: "t"]

      for {answer, reason} <- [
            {{403, "not_agreed"}, :not_agreed},
            {{403, "beyond_agreement"}, {:beyond_agreement, ["to[0]: no"]}},
            {{422, "invalid"}, {:invalid, ["to[0]: no"]}},
            {{429, "too_many_calls"}, :rate_limited},
            {{429, "too_many_messages"}, :too_many_messages},
            {{503, "mail_disabled"}, :mail_disabled},
            {413, {:invalid, ["the message is larger than EHOS reads"]}},
            {400, {:invalid, ["the message holds text EHOS does not take"]}}
          ] do
        set(ehos, %{answer: answer})
        assert Mail.deliver(message) == {:error, reason}
      end
    end

    # #451: EHOS refuses before it sends, so a refusal it never gives sent nothing.
    test "a refusal EHOS never gives is :unavailable, nothing sent, and logged", %{ehos: ehos} do
      server = start!(ehos)
      message = [server: server, to: [{:person, @ada}], subject: "s", text: "t"]

      for answer <- [{404, "not_found"}, {403, "forbidden"}, :always_401] do
        set(ehos, %{answer: answer})
        log = capture_log(fn -> assert Mail.deliver(message) == {:error, :unavailable} end)
        assert log =~ "EHOS's mail API answered"
        assert log =~ "nothing sent"
      end
    end

    # #451: a failure, a timeout a proxy answers, or a 200 EHOS never writes may come after EHOS
    # sent some messages: retrying could send them twice.
    test "a failure or an answer EHOS never writes is :outcome_unknown, and logged",
         %{ehos: ehos} do
      server = start!(ehos)
      message = [server: server, to: [{:person, @ada}], subject: "s", text: "t"]

      for answer <- [
            :garbage,
            {500, "oops"},
            {502, "bad_gateway"},
            {503, "unavailable"},
            {408, "timeout"}
          ] do
        set(ehos, %{answer: answer})
        log = capture_log(fn -> assert Mail.deliver(message) == {:error, :outcome_unknown} end)
        assert log =~ "some messages may have been sent"
      end
    end

    test "a name that does not resolve or a refused connection is :unavailable; the rest, :outcome_unknown",
         %{ehos: ehos} do
      server = start!(ehos)
      message = [server: server, to: [{:person, @ada}], subject: "s", text: "t"]

      for {reason, error} <- [
            {:econnrefused, :unavailable},
            {:nxdomain, :unavailable},
            {:eaddrnotavail, :unavailable},
            # A pooled connection, or a socket whose last acknowledgements were lost, reports these
            # after the request was written.
            {{:tls_alert, {:bad_record_mac, ~c"bad record mac"}}, :outcome_unknown},
            {:ehostunreach, :outcome_unknown},
            {:enetunreach, :outcome_unknown},
            {:closed, :outcome_unknown},
            {:timeout, :outcome_unknown},
            {:econnreset, :outcome_unknown}
          ] do
        set(ehos, %{answer: {:transport, reason}})

        log =
          capture_log(fn -> assert Mail.deliver(message) == {:error, error}, inspect(reason) end)

        tag = if is_tuple(reason), do: elem(reason, 0), else: reason
        assert log =~ Atom.to_string(tag)
      end
    end

    # #451: the log names what failed, never the request it failed in.
    test "an exception inside the request is :outcome_unknown, and logs no credential",
         %{ehos: ehos} do
      server = start!(ehos)
      set(ehos, %{answer: :raise})

      log =
        capture_log(fn ->
          assert Mail.deliver(server: server, to: [{:person, @ada}], subject: "s", text: "t") ==
                   {:error, :outcome_unknown}
        end)

      assert log =~ "RuntimeError"
      refute log =~ "credential-"
    end

    test "a deployment that asks for no mail is refused the credential, :not_asked", %{ehos: ehos} do
      set(ehos, %{answer: :not_asked})
      server = start!(ehos)

      capture_log(fn ->
        assert Mail.deliver(server: server, to: [{:person, @ada}], subject: "s", text: "t") ==
                 {:error, :not_asked}
      end)
    end

    test "a process that is not running is :unavailable, not an exit" do
      capture_log(fn ->
        assert Mail.deliver(
                 server: :"no_such_#{System.unique_integer([:positive])}",
                 to: [{:person, @ada}],
                 subject: "s",
                 text: "t"
               ) == {:error, :unavailable}
      end)
    end
  end

  describe "the configuration" do
    test ":people is the older name of :workload, and both at once is refused",
         %{key_file: key_file} do
      config = [client_id: "office/test", client_key_file: key_file]

      Application.delete_env(:eh_os_contract_auth, :workload)
      Application.put_env(:eh_os_contract_auth, :people, config)
      # The older child starts the same process, under the name People and Mail call.
      assert %{id: Workload} = People.child_spec([])

      Application.put_env(:eh_os_contract_auth, :workload, config)

      assert_raise ArgumentError, ~r/both :workload and :people/, fn ->
        Workload.child_spec([])
      end

      Application.delete_env(:eh_os_contract_auth, :people)
      assert %{id: Workload} = Workload.child_spec([])

      Application.delete_env(:eh_os_contract_auth, :workload)
      assert_raise ArgumentError, ~r/:workload is missing/, fn -> Workload.child_spec([]) end
    end
  end

  defp restore(previous) do
    for {key, _value} <- Application.get_all_env(:eh_os_contract_auth),
        not Keyword.has_key?(previous, key),
        do: Application.delete_env(:eh_os_contract_auth, key)

    for {key, value} <- previous, do: Application.put_env(:eh_os_contract_auth, key, value)
  end
end

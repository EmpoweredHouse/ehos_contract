defmodule EhosContract.Auth.Mail do
  # As agreed with EHOS: the application sends mail through EHOS as itself, over the company's
  # relay, as far as a mail agreement for its environment allows. The mail API is
  # EHOS's `docs/mail-api.md`. Issue #436.
  @moduledoc """
  Mail the application sends through EHOS, as itself, to the company's people or to any
  address, as far as someone has agreed for its environment.

      # ehos.yaml
      schema: ehos.yaml/v6
      needs:
        mail:
          level: internal        # or external, to any address as well
          reply_domains: [reply.office.example.org]

      # anywhere, with EhosContract.Auth.Workload in the supervision tree
      {:ok, [%EhosContract.Auth.Mail.Result{sent?: true, message_id: id}]} =
        EhosContract.Auth.Mail.deliver(
          to: [{:person, person_id}],
          subject: "A document waits for your approval",
          text: "Open it at https://office.example.org/d/42.",
          html: ~s(<p>Open it <a href="https://office.example.org/d/42">here</a>.</p>),
          attachments: [
            %{filename: "approval.pdf", content_type: "application/pdf", content: pdf}
          ]
        )

  The credential is the workload's, which `EhosContract.Auth.Workload` takes, as for
  reading the people. Asking for mail grants nothing: EHOS sends only once someone who
  holds `ehos.mail.manage` agrees for that environment, and refuses the next message
  after they withdraw.

  **The levels.** At `internal` a recipient is a person in EHOS's directory, by the id
  `EhosContract.Auth.People` and sign-in give; EHOS looks up the address and never
  returns it. At `external` a recipient may also be any address.

  **What `deliver/1` takes,** as EHOS's mail API names it:

    * `to:`, 1 to 50 recipients, each `{:person, id}` or `{:address, address}`. Each gets
      a message of its own;
    * `subject:` and `text:`, required; `html:`, which EHOS sends as given. Escape every
      value the application puts into it, a name or a title, as HEEx or
      `Phoenix.HTML.html_escape/1` does: EHOS does not;
    * `verify_html:`, `true` to have EHOS refuse the HTML, as `{:invalid, reasons}`, when
      it holds a script, a form, a frame, an event attribute, or an address whose scheme
      is not `http`, `https`, `mailto`, `tel` or `cid`. It is a backstop, not a sanitiser:
      EHOS never changes the HTML, and a link or an image the application did not mean to
      write passes it. Left out or `false`, EHOS sends the HTML unread. EHOS 0.21.0 or
      later reads it; an earlier one ignores it and cleans the HTML itself;
    * `reply_to:`, a recipient: a person, an address in a reply domain the agreement
      covers, or, at `external`, any address;
    * `in_reply_to:` and `references:`, message ids such as `"<t-42@reply.example.org>"`,
      so a mail program threads the messages;
    * `attachments:`, maps with `filename`, `content_type` and `content`, the file's
      bytes, which this module encodes; with `inline: true` and a `content_id`, an image
      the HTML shows as `<img src="cid:…">`. At most 20, 10 MB together.

  **Trying a call again.** `idempotency_key:` names the call, with 1 to 255 visible
  ASCII characters, such as a new `Ecto.UUID.generate()` for each message. Keep it with
  the message, and after `:outcome_unknown` call again with the same key and the same
  message: for 24 hours EHOS sends nothing again for it and answers what the first call
  sent. EHOS 0.23.0 or later reads it; an earlier one ignores it and sends again.

  An option this module does not take, a value of the wrong type, or a string that is
  not UTF-8 raises `ArgumentError` before EHOS is asked, naming the option and never its
  value. What EHOS checks of the content, the limits above included, comes back as
  `{:error, {:invalid, reasons}}`, a body larger than EHOS reads too.

  **The answer** is one `EhosContract.Auth.Mail.Result` per recipient, in the order
  given: whether the company's relay took the message, its `message_id`, and the relay's
  answer or why it was not sent. Taken is not delivered: a bounce goes to the
  installation's sending address, which EHOS does not read. Keep `message_id` to tie
  what you learn later to the message.

  **What a call answers when it sends nothing,** each an `{:error, reason}`:

    * `:not_agreed`: no mail agreement is in force for this environment, or the
      deployment no longer asks for mail;
    * `{:beyond_agreement, reasons}`: a recipient or the reply address the agreement
      does not allow, a person disabled, or an id that names no one;
    * `{:invalid, reasons}`: EHOS does not send the message as it is;
    * `:not_asked`: EHOS refuses the client the grant: its deployment asks for neither
      mail nor people;
    * `:rate_limited`: EHOS's limit on calls a minute, or on the token endpoint;
    * `:too_many_messages`: the application has sent the messages it may send today;
    * `:mail_disabled`: the installation sends no mail;
    * `:idempotency_key_reused`: the key named another message in the last 24 hours;
    * `:idempotency_key_in_progress`: the call that used the key first is still sending;
      call again shortly;
    * `:idempotency_key_abandoned`: the call that used the key first never ended, and
      EHOS does not know which of its messages were sent. A new key sends them all again;
    * `:unavailable`: nothing was sent, and the call may be made again: there is no
      credential, EHOS's name does not resolve, the connection was refused, its address
      is not https, or EHOS answered a refusal it never gives.

  **`:outcome_unknown`** is the one error after which some messages may have been sent:
  any other failure of the transport, a timeout even while connecting, a failed TLS
  handshake and an unreachable host included, since the client cannot tell them from one
  after EHOS took the call; EHOS failing (a 5xx); or a 200 with what it never writes. EHOS
  sends each recipient's message before it answers, so a call made again without its
  `idempotency_key:` may send a message twice: retry it with the same key.

  Each reason in `reasons` is EHOS's sentence, naming the value it is about, such as
  `"to[1]: …"`.

  A call is never retried but once with a new credential when EHOS refuses the one it
  sent, before it sends anything. Retrying is the application's choice: after
  `:unavailable` nothing was sent, after `:outcome_unknown` something may have been, and
  the same `idempotency_key:` sends it once.
  Both attempts share two minutes and a half, EHOS's two for the relay and a margin, and each may first wait up to twelve seconds for a credential: a
  call answers within three minutes. It never raises or exits for what EHOS does, the
  process not running included.

  **Another answer where EHOS gives none.** This module is EHOS's
  `EhosContract.Auth.Mail.Sender`. An application that asks `sender/0` instead gets the
  one the configuration names, so development, a release started without EHOS and tests
  send nothing:

      # config/dev.exs
      config :ehos_contract_auth, mail_sender: EhosContract.Auth.Mail.Local

      # anywhere
      EhosContract.Auth.Mail.sender().deliver(to: [{:person, id}], subject: "…", text: "…")
  """

  @behaviour EhosContract.Auth.Mail.Sender

  require Logger

  alias EhosContract.Auth.Choice
  alias EhosContract.Auth.Mail.{Local, Result, Unconfigured}
  alias EhosContract.Auth.SignIn.Http
  alias EhosContract.Auth.Workload

  # EHOS gives the relay two minutes for a call's messages; the answer comes after them.
  @deadline 150_000
  @keys [
    :to,
    :subject,
    :text,
    :html,
    :verify_html,
    :reply_to,
    :in_reply_to,
    :references,
    :attachments
  ]
  @attachment_keys [:filename, :content_type, :content, :inline, :content_id]
  @refusals %{
    {403, "not_agreed"} => :not_agreed,
    {429, "too_many_messages"} => :too_many_messages,
    {503, "mail_disabled"} => :mail_disabled,
    {422, "idempotency_key_reused"} => :idempotency_key_reused,
    {409, "idempotency_key_in_progress"} => :idempotency_key_in_progress,
    {409, "idempotency_key_abandoned"} => :idempotency_key_abandoned
  }

  @typedoc "A recipient: a person in EHOS's directory by id, or, at `external`, an address."
  @type recipient :: {:person, String.t()} | {:address, String.t()}

  @typedoc "A file sent with the message; `content` is its bytes."
  @type attachment :: %{
          required(:filename) => String.t(),
          required(:content_type) => String.t(),
          required(:content) => binary(),
          optional(:inline) => boolean(),
          optional(:content_id) => String.t()
        }

  @typedoc "Why a call sent nothing, or, as `:outcome_unknown`, may have sent some messages."
  @type reason ::
          :not_agreed
          | {:beyond_agreement, [String.t()]}
          | {:invalid, [String.t()]}
          | :not_asked
          | :rate_limited
          | :too_many_messages
          | :mail_disabled
          | :idempotency_key_reused
          | :idempotency_key_in_progress
          | :idempotency_key_abandoned
          | :unavailable
          | :outcome_unknown

  @typedoc "What `deliver/1` takes; `to:`, `subject:` and `text:` are required."
  @type option ::
          {:to, [recipient()]}
          | {:subject, String.t()}
          | {:text, String.t()}
          | {:html, String.t()}
          | {:verify_html, boolean()}
          | {:reply_to, recipient()}
          | {:in_reply_to, [String.t()]}
          | {:references, [String.t()]}
          | {:attachments, [attachment()]}
          | {:idempotency_key, String.t()}
          | {:server, GenServer.server()}

  @doc """
  Sends the message to each recipient, through EHOS. Raises `ArgumentError` for an
  option it does not take, as documented in `t:option/0`.
  """
  @impl true
  @spec deliver([option()]) :: {:ok, [Result.t()]} | {:error, reason()}
  def deliver(message) do
    body = message |> message!() |> Jason.encode_to_iodata!()
    server = Keyword.get(message, :server, Workload)

    headers =
      case Keyword.get(message, :idempotency_key) do
        nil -> []
        key -> [{"idempotency-key", key}]
      end

    case Workload.request(server, :post, "/api/v1/mail", body, @deadline,
           shared: true,
           headers: headers
         ) do
      {:ok, {200, _headers, body}} ->
        results(body)

      {:ok, {status, _headers, body}} ->
        refusal(status, body)

      {:error, {:unreachable, reason}} ->
        unreachable(reason)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  The `EhosContract.Auth.Mail.Sender` the application asks, read at each call:
  `config :ehos_contract_auth, mail_sender:` when it is set. Otherwise this module when
  the workload is configured (`workload:`, or `people:`), whose credential mail goes out
  on, and `EhosContract.Auth.Mail.Unconfigured` when it is not, so a release started
  without EHOS's credentials answers `:unavailable` and never says it sent.

  Raises `ArgumentError` when it names `EhosContract.Auth.Mail.Local` or
  `EhosContract.Auth.Testing.Mail` while the workload is configured, which is a release
  answering for EHOS, and when `mail_sender:` names anything but a module that implements
  `EhosContract.Auth.Mail.Sender`.
  """
  @spec sender() :: module()
  def sender do
    Choice.choose!(%{
      key: :mail_sender,
      behaviour: EhosContract.Auth.Mail.Sender,
      callbacks: [deliver: 1],
      ehos?: Choice.workload?(),
      ehos: __MODULE__,
      unconfigured: Unconfigured,
      stand_ins: [Local, EhosContract.Auth.Testing.Mail],
      configured: "`workload:` (or `people:`)"
    })
  end

  ## The request

  # The body EHOS is sent, or `ArgumentError` as `deliver/1` raises it: also how
  # `EhosContract.Auth.Mail.Local` and `EhosContract.Auth.Testing.Mail` hold a host's call to
  # what EHOS takes, so development and tests fail where a release would.
  @doc false
  @spec message!(term()) :: %{String.t() => term()}
  def message!(message) do
    unless Keyword.keyword?(message), do: bad!("a keyword list")
    keys = Keyword.keys(message)
    if length(keys) != length(Enum.uniq(keys)), do: bad!("each option once")

    # A key given as nil is a key the host lost, not none: sent without it, a retry could mail
    # someone twice.
    if Keyword.has_key?(message, :idempotency_key),
      do: key!(Keyword.fetch!(message, :idempotency_key))

    message |> Keyword.drop([:server, :idempotency_key]) |> body!()
  end

  # What EHOS takes as a key: 1 to 255 visible ASCII characters, as given.
  defp key!(key) do
    unless is_binary(key) and key =~ ~r/\A[\x21-\x7E]{1,255}\z/,
      do: bad!("idempotency_key: as 1 to 255 visible ASCII characters")

    :ok
  end

  defp body!(message) do
    case Keyword.keys(message) -- @keys do
      [] -> :ok
      extra -> bad!("no #{inspect(extra)}")
    end

    for key <- [:to, :subject, :text], not Keyword.has_key?(message, key) do
      bad!("#{key}:")
    end

    Map.new(message, fn
      {:to, to} when to != [] -> {"to", to |> list!(:to) |> Enum.map(&recipient!/1)}
      {:reply_to, reply_to} -> {"reply_to", recipient!(reply_to)}
      {key, value} when key in [:subject, :text, :html] -> {to_string(key), string!(key, value)}
      {:verify_html, verify} when is_boolean(verify) -> {"verify_html", verify}
      {key, ids} when key in [:in_reply_to, :references] -> {to_string(key), ids!(key, ids)}
      {:attachments, files} -> {"attachments", files |> list!(:attachments) |> Enum.map(&file!/1)}
      {key, _value} -> bad!("#{key}: as documented")
    end)
  end

  defp recipient!({kind, value}) when kind in [:person, :address] do
    if text?(value),
      do: %{to_string(kind) => value},
      else: bad!("recipients as {:person, id} or {:address, address}")
  end

  defp recipient!(_other), do: bad!("recipients as {:person, id} or {:address, address}")

  defp string!(key, value), do: if(text?(value), do: value, else: bad!("#{key}: as a string"))

  defp ids!(key, ids) do
    if Enum.all?(list!(ids, key), &text?/1),
      do: ids,
      else: bad!("#{key}: as a list of message ids")
  end

  # A proper list: `Enum` would raise on an improper one with its tail, a recipient perhaps, in the
  # stack trace's arguments.
  defp list!(list, key) do
    if is_list(list) and not List.improper?(list), do: list, else: bad!("#{key}: as a list")
  end

  defp file!(%{filename: name, content_type: type, content: content} = file)
       when is_binary(content) do
    unless text?(name) and text?(type),
      do: bad!("an attachment's filename: and content_type: as strings")

    case Map.keys(file) -- @attachment_keys do
      [] -> :ok
      extra -> bad!("no #{inspect(extra)} in an attachment")
    end

    inline = Map.get(file, :inline, false)
    content_id = Map.get(file, :content_id)

    unless is_boolean(inline) and (is_nil(content_id) or text?(content_id)),
      do: bad!("an attachment's inline: as a boolean and content_id: as a string")

    %{"filename" => name, "content_type" => type, "content" => Base.encode64(content)}
    |> then(&if inline, do: Map.put(&1, "inline", true), else: &1)
    |> then(&if content_id, do: Map.put(&1, "content_id", content_id), else: &1)
  end

  defp file!(_other),
    do: bad!("attachments as maps with filename:, content_type: and content:")

  # A string JSON can carry: anything else would raise in the encoder, with the value in its
  # message, which may be a person's address or a message's body.
  defp text?(value), do: is_binary(value) and String.valid?(value)

  defp bad!(what) do
    raise ArgumentError,
          "deliver/1 takes #{what}: to: (recipients), subject:, text:, and optionally html:, " <>
            "verify_html:, reply_to:, in_reply_to:, references:, attachments: and idempotency_key:"
  end

  ## The answer

  # #451: a name that does not resolve or a connection refused wrote nothing to EHOS. Anything
  # else may have come after EHOS took the request and sent some messages: a timeout, which Req
  # names the same while connecting; a reset or a close; a TLS alert or an unreachable host,
  # which a pooled connection, or a socket whose last acknowledgements were lost, reports after
  # the request was written.
  @not_written [:econnrefused, :nxdomain, :eaddrnotavail]

  defp unreachable(reason) do
    if not_written?(reason) do
      Logger.warning(
        "EHOS's mail API could not be reached, nothing sent: #{Http.describe(reason)}"
      )

      {:error, :unavailable}
    else
      Logger.warning(
        "EHOS's mail API was cut off, some messages may have been sent: #{Http.describe(reason)}"
      )

      {:error, :outcome_unknown}
    end
  end

  defp not_written?(%Req.TransportError{reason: reason}) when reason in @not_written, do: true
  defp not_written?({:not_https, _url}), do: true
  defp not_written?(_reason), do: false

  defp results(body) do
    with {:ok, %{"messages" => messages}} when is_list(messages) <- Jason.decode(body),
         results = Enum.map(messages, &Result.from_map/1),
         false <- Enum.member?(results, :error) do
      {:ok, Enum.map(results, fn {:ok, result} -> result end)}
    else
      _other -> unknown("a result it never writes")
    end
  end

  defp refusal(status, body) do
    {error, reasons} =
      case Jason.decode(body) do
        {:ok, %{"error" => error} = refusal} when is_binary(error) ->
          {error, reasons(refusal["reasons"])}

        _other ->
          {nil, []}
      end

    cond do
      status == 403 and error == "beyond_agreement" -> {:error, {:beyond_agreement, reasons}}
      status == 422 and error == "invalid" -> {:error, {:invalid, reasons}}
      # Answered before the route: a body past what EHOS reads, or text it does not store.
      # A 413 is also EHOS's answer to a large body under a credential it no longer accepts, as
      # after its keys rotate, before it can answer 401: EHOS's to answer 401 there, as #436
      # says.
      status == 413 -> {:error, {:invalid, ["the message is larger than EHOS reads"]}}
      status == 400 -> {:error, {:invalid, ["the message holds text EHOS does not take"]}}
      reason = @refusals[{status, error}] -> {:error, reason}
      status == 429 -> {:error, :rate_limited}
      # EHOS refuses before it sends; a timeout a proxy answers, or a failure, may come after.
      status in 400..499 and status != 408 -> unexpected("status #{status}")
      true -> unknown("status #{status}")
    end
  end

  defp reasons(reasons) when is_list(reasons), do: Enum.filter(reasons, &is_binary/1)
  defp reasons(_reasons), do: []

  defp unexpected(what) do
    Logger.warning("EHOS's mail API answered #{what}, nothing sent")
    {:error, :unavailable}
  end

  defp unknown(what) do
    Logger.warning("EHOS's mail API answered #{what}, some messages may have been sent")
    {:error, :outcome_unknown}
  end
end

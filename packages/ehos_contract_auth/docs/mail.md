# Send mail

This page tells a developer how the application sends mail through EHOS. For example, the
application tells a person that a document waits for their approval. EHOS sends the mail as the
application, over the relay of the company.

## Prerequisites

- The application has the credential of [Read the people of the company](people.md), step 2: the
  `workload:` configuration and the child `EhosContract.Auth.Workload`. Mail uses the same
  credential.
- Someone who holds `ehos.mail.manage` in EHOS agrees that the application sends mail, for each
  environment. The agreement has a level no wider than the level that the application asks for. Until then, EHOS
  refuses each message.

## 1. Ask for mail in `ehos.yaml`

Add `needs.mail` to the `ehos.yaml` of the application, at `ehos.yaml/v6` or later:

```yaml
schema: ehos.yaml/v6
needs:
  mail:
    level: internal
    reply_domains: [reply.office.example.org]
```

| Level | Recipients |
| --- | --- |
| `internal` | the people in the directory of EHOS, by their id; EHOS finds the address of each person |
| `external` | any address too |

`reply_domains` is optional. It names the domains where the application receives the answers.

**Result:** EHOS gives the workload `EHOS_CLIENT_ID` and `EHOS_CLIENT_KEY_FILE`. The request grants
nothing. EHOS sends only after someone agrees.

## 2. Send a message

Ask `EhosContract.Auth.Mail.sender/0` for the module that sends, and give it the message:

```elixir
{:ok, results} =
  EhosContract.Auth.Mail.sender().deliver(
    to: [{:person, person_id}],
    subject: "A document waits for your approval",
    text: "Open it at https://office.example.org/d/42.",
    html: ~s(<p>Open it <a href="https://office.example.org/d/42">here</a>.</p>),
    verify_html: true,
    reply_to: {:address, "t-42@reply.office.example.org"},
    attachments: [%{filename: "approval.pdf", content_type: "application/pdf", content: pdf}],
    idempotency_key: key
  )
# [%EhosContract.Auth.Mail.Result{to: {:person, "6f1c…"}, sent?: true,
#   message_id: "<…@office.example.org>", relay_response: "2.0.0 OK …", reason: nil}]
```

`sender/0` gives `EhosContract.Auth.Mail` where `workload:` is configured. Elsewhere, it gives a
module that sends nothing: [Use people, grants and
mail where EHOS does not answer](without-ehos.md).

| Option | Value |
| --- | --- |
| `to:` | 1 to 50 recipients, each `{:person, id}` or `{:address, address}`; `{:address, …}` only at `external` |
| `subject:`, `text:` | required |
| `html:` | the HTML part, which EHOS sends as it is |
| `verify_html:` | `true` to make EHOS refuse unsafe HTML, as below |
| `reply_to:` | one recipient: a person, an address in a reply domain, or, at `external`, any address |
| `in_reply_to:`, `references:` | lists of message ids, such as `["<t-42@reply.example.org>"]`, so that a mail program threads the messages |
| `attachments:` | maps with `filename`, `content_type` and `content`, the bytes of the file; 20 or fewer, 10 MB or less together |
| `idempotency_key:` | the name of the message for a second call, as below |

An attachment with `inline: true` and a `content_id:` is an image that the HTML shows as
`<img src="cid:…">`.

**Escape each value that the application puts into the HTML**, such as a name or a title, as HEEx
or `Phoenix.HTML.html_escape/1` does. EHOS does not escape it.

With `verify_html: true`, EHOS refuses HTML that has a script, a form, a frame or an event attribute.
It also refuses an address with a scheme other than `http`, `https`, `mailto`, `tel` or `cid`. This is a second
check, not a sanitizer. EHOS 0.21.0 or later reads this option, and never changes the HTML. An
earlier EHOS ignores it, and cleans the HTML itself.

EHOS always refuses an attachment that is an executable, a script or an encrypted archive. The mail
API of EHOS, `docs/mail-api.md` in eh-os, gives each limit.

**Result:** each recipient gets a message of their own, from the sending address of the
installation, with the name of the application. The call gives one `EhosContract.Auth.Mail.Result`
for each recipient, in the order that EHOS gives: the order of `to:`.

- `sent?: true` tells that the relay took the message, not that the recipient got it. A bounce goes
  to the sending address of the installation, which EHOS does not read.
- `message_id` is there also when the relay did not take the message. Keep it to connect what you
  learn later to the message.
- `reason` is the sentence of EHOS when the relay did not take the message. EHOS still tried the
  other recipients.

EHOS receives no mail. The answers to a reply domain go to the mailbox of the application there,
which the application reads itself.

## 3. Send again safely

Give each message an `idempotency_key:` before the first call, and keep it with the message:

```elixir
key = Ecto.UUID.generate()
```

The key has 1 to 255 visible ASCII characters. The package sends it in the `Idempotency-Key` header.

EHOS sends the message to each recipient before it answers. So after `:outcome_unknown`, a second
call can send a message to a person two times, unless it has the same key. For 24 hours, EHOS sends
nothing again for a key, and answers what the first call sent. EHOS 0.23.0 or later reads the key.
An earlier EHOS ignores it and sends again.

- After `:outcome_unknown`, call again with the same key and the same message.
- After `:unavailable`, call again. Nothing was sent.

**Result:** a second call with the same key sends no message two times.

## How long does a call take?

The package tries a call one more time only when EHOS refuses the credential, before EHOS sends
anything. The second try gets a new credential and sends the same key. A call answers in 3 minutes
or less.

A call never raises for what EHOS does, also when the workload process does not run. Before it asks EHOS,
it raises `ArgumentError` for:

- an option that it does not take;
- a value of the wrong type, or a string that is not UTF-8;
- `idempotency_key: nil`.

The error names the option, never its value.

## What can go wrong

A call that sends nothing tells why. A call that may have sent some messages tells that too.

| Error | When |
| --- | --- |
| `:not_agreed` | No mail agreement is in force for this environment, or the deployment does not ask for mail now |
| `{:beyond_agreement, reasons}` | The agreement does not allow a recipient or the reply address, a person is disabled, or an id names nobody |
| `{:invalid, reasons}` | EHOS does not send the message as it is. Each reason names the value, such as `to[1]`. Also when the message is larger than EHOS reads, or holds text that EHOS does not take. |
| `:not_asked` | The deployment asks for neither mail nor the people |
| `:rate_limited` | The limits of EHOS: 60 credentials a minute, 60 calls a minute |
| `:too_many_messages` | The application sent the 1000 messages of the day |
| `:mail_disabled` | The installation sends no mail |
| `:idempotency_key_reused` | The `idempotency_key:` named another message in the last 24 hours |
| `:idempotency_key_in_progress` | The first call with the key is still sending. Call again soon. |
| `:idempotency_key_abandoned` | The first call with the key never ended, and EHOS does not know which messages it sent. A new key sends all of them again. |
| `:unavailable` | Nothing was sent. You can call again. See the list below. |
| `:outcome_unknown` | Some messages may have been sent. Call again with the same key. See the list below. |

The package answers `:unavailable` when:

- it has no credential: the workload process does not run, or gives none in 12 seconds;
- the name of EHOS does not resolve, or EHOS refuses the connection;
- the address of EHOS is not https;
- EHOS gives a refusal that it never gives, or refuses the credential two times.

The package answers `:outcome_unknown` when:

- the transport fails in another way: a timeout, also while it connects, a failed TLS handshake, or
  a host that it cannot reach;
- EHOS answers 408, fails with 5xx other than `mail_disabled`, or gives a status that is not 200 or
  4xx;
- EHOS answers 200 with what it never writes, or with a body larger than 1 MiB.

## Next steps

- [Read the people of the company](people.md): find the id of a person to send mail to.
- [Use people, grants and mail where EHOS does not answer](without-ehos.md): the stand-ins for
  development and tests.

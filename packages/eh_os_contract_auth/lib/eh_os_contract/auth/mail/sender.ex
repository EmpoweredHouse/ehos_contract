defmodule EhOsContract.Auth.Mail.Sender do
  # Issue #477: the seam #475 gave the people and grants, for mail.
  @moduledoc """
  Who sends the application's mail: EHOS in a release that may send it, someone else in
  development, in a release started without EHOS, and in tests.

  `EhOsContract.Auth.Mail.sender/0` names the one configured, and the application asks it:

      EhOsContract.Auth.Mail.sender().deliver(
        to: [{:person, person_id}],
        subject: "A document waits for your approval",
        text: "Open it at https://office.example.org/d/42."
      )

  The package ships four:

    * `EhOsContract.Auth.Mail`, EHOS's mail API;
    * `EhOsContract.Auth.Mail.Local`, which sends nothing and answers every message as
      taken, for development;
    * `EhOsContract.Auth.Mail.Unconfigured`, which answers `:unavailable`, so a release
      without EHOS never says it sent;
    * `EhOsContract.Auth.Testing.Mail`, which tells the test what it was asked to send and
      answers as the test asked.

  An implementation of its own takes the options and answers the reasons
  `EhOsContract.Auth.Mail` documents.
  """

  alias EhOsContract.Auth.Mail
  alias EhOsContract.Auth.Mail.Result

  @doc "Sends the message to each recipient, as `EhOsContract.Auth.Mail.deliver/1` does."
  @callback deliver([Mail.option()]) :: {:ok, [Result.t()]} | {:error, Mail.reason()}
end

defmodule EhosContract.Auth.People.Directory do
  # Issue #475: TaxVision and Rehmed each wrote this seam, with the same two callbacks.
  @moduledoc """
  Who answers about the company's people: EHOS in a release that reads them, someone
  else in development, in a release started without EHOS, and in tests.

  `EhosContract.Auth.People.directory/0` names the one configured, and a page asks it:

      {:ok, %{people: people, next: next}} = EhosContract.Auth.People.directory().list(q: "ad")

  The package ships four:

    * `EhosContract.Auth.People`, EHOS's people API;
    * `EhosContract.Auth.People.Directory.Static`, the people the configuration lists,
      for development;
    * `EhosContract.Auth.People.Directory.Unconfigured`, which answers `:unavailable`, so a
      release without EHOS knows nobody and says why;
    * `EhosContract.Auth.Testing.People`, the people a test gave.

  An implementation of its own takes the options and answers the reasons
  `EhosContract.Auth.People` documents.
  """

  alias EhosContract.Auth.People
  alias EhosContract.Auth.People.Person

  @doc "One page of the people, as `EhosContract.Auth.People.list/1` answers it."
  @callback list([People.list_option()]) ::
              {:ok, %{people: [Person.t()], next: String.t() | nil}} | {:error, People.reason()}

  @doc "The person `id` names, as `EhosContract.Auth.People.get/2` answers it."
  @callback get(String.t()) :: {:ok, Person.t()} | {:error, People.reason()}
end

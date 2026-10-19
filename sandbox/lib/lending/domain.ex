defmodule Lending.Domain do
  @moduledoc """
  The vocabulary of the library's lending: circulation, where copies are lent, held
  and returned, and membership, where the people who borrow them are registered.

  The terms carry a German translation each, so that the glossary has a real domain
  to print in another language (`mix eh_os_contract.glossary --language de`).
  """

  use EhOsContract.Domain, name: :lending, language: :en, time_zone: "Europe/London"
  use Boundary, deps: [EhOsContract], exports: [{Values, []}]

  subdomain :core, "Lending", type: :core
  subdomain :supporting, "Membership", type: :supporting

  context :circulation, "Circulation", subdomain: :core do
    term "Copy", definition: "One physical item of a title, with its own barcode" do
      translation :de, "Exemplar", definition: "Ein einzelnes Stück eines Titels"
    end

    term "Loan", definition: "A copy lent to a member until it comes back" do
      translation :de, "Ausleihe", definition: "Ein Exemplar, das bis zur Rückgabe verliehen ist"
    end

    term "Member", definition: "Whom a copy is lent to, by the card they show"

    term "Fee", definition: "What a copy back after its due date costs, by the desk's tariff"

    term "Hold", definition: "A copy kept for one member when it comes back" do
      translation :de, "Vormerkung",
        definition: "Ein Exemplar, das bei Rückgabe für ein Mitglied zurückgelegt wird"
    end
  end

  context :membership, "Membership", subdomain: :supporting do
    term "Membership", definition: "A member's registration, with how to reach them"

    term "Member", definition: "A person registered to borrow" do
      translation :de, "Mitglied", definition: "Eine Person, die ausleihen darf"
    end

    term "Card", definition: "What a member shows to borrow; the card system may suspend it"
  end

  # Circulation lends to whom membership registered, and reads the card it issued.
  relation :customer_supplier, upstream: :membership, downstream: :circulation

  actor :librarian, :human, "Librarian"
  actor :patron, :human, "Patron"

  subject :member, "Member"

  # Membership issues the cards and the library's card system keeps them, outside the
  # log; a loan reads whether one is suspended.
  entity :card, "Membership card", context: :membership, identity: :card_id do
    field :suspended, :boolean, label: "Suspended"
  end

  value :money, :integer, unit: :pence, label: "Amount"
end

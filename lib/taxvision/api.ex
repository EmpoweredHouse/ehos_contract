defmodule Taxvision.Api do
  @moduledoc """
  The request edge. **Three IAM levels** pass through here, each giving a
  different answer — and that is the whole test of whether the seam is in the
  right place.

  | Level | Who owns it | Answer on refusal |
  |---|---|---|
  | Authentication — who is this | bought | `:unauthenticated` |
  | Entitlement — can they reach the accounting API | bought, a claim from the token | `:forbidden`, **before** any domain code |
  | Domain rule — may they open **this** month | ours, a rule in the contract | a rejection with a reason, a recorded case |

  The third row is what the game is about. If it could be satisfied by a
  provider's configuration, the levels would not be separated and the whole value
  would be bought.

  This is the equivalent of a Phoenix pipeline, written without Phoenix. The web
  layer shows nothing contentious in this slice, and REST versus GraphQL is still
  open in decision 009 — building the API would settle an open decision. The swap
  is mechanical: `authenticate` and `entitle` are two plugs, `open_month` is a
  controller action.

  Note what is **not** here: access to `Taxvision.Tasks`,
  `Taxvision.Notifications` or `Taxvision.AccountingMonth`. The edge emits an
  event, and that is where its knowledge of what happens next ends. If it called
  those modules directly, `boundary` would stop it — and that is the difference
  between an event-driven architecture and calling something event-driven.
  """

  use Boundary,
    deps: [
      PNS,
      Taxvision.Contracts,
      Taxvision.Authorization,
      Taxvision.RegistryCheck,
      Taxvision.Adapters,
      # The request edge resolves a period name to its identifier, so it depends on the
      # module that owns periods. One function call, not a join.
      Taxvision.Periods
    ],
    exports: []

  alias Taxvision.Contracts.AccountingMonth

  @doc "Opens an accounting month. Returns `{:ok, correlation_id}` or a reason for refusal."
  @spec open_month(String.t(), %{company_id: String.t(), period: String.t()}) ::
          {:ok, Ecto.UUID.t()} | {:error, term()}
  def open_month(token, %{company_id: company_id, period: period}) do
    with {:ok, actor} <- authenticate(token),
         :ok <- entitle(actor),
         {:ok, registries} <- Taxvision.Adapters.RegistryLookup.lookup(company_id),
         input = build_input(actor, company_id, period, registries),
         :ok <- Taxvision.Authorization.authorize_open_month(input),
         emissions when is_list(emissions) <- Taxvision.RegistryCheck.decide(input),
         {:ok, events} <- PNS.emit_all(AccountingMonth, emissions, %{actor: actor.subject}) do
      {:ok, List.first(events).correlation_id}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp authenticate(token) do
    case PNS.Auth.verify(token) do
      {:ok, actor} -> {:ok, actor}
      {:error, _} -> {:error, :unauthenticated}
    end
  end

  defp entitle(actor) do
    # One claim, no network. The cut-off happens here, so no event reaches the
    # log — and that is checkable by the absence of a row rather than by the
    # content of a response.
    if PNS.Auth.entitled?(actor, :accounting), do: :ok, else: {:error, :forbidden}
  end

  # **The one place a period name becomes an identifier.** A name is what arrives from
  # outside — someone typed or selected "2026-07" — and an identifier is what a fact
  # carries. Resolving here rather than in a handler is what makes the canonicalisation
  # complete: past this line nothing in the domain sees the string again, so `"2026-7"`
  # beside `"2026-07"` stops being possible instead of merely being discouraged.
  defp build_input(actor, company_id, period, registries) do
    %{
      command: :open_month,
      company_id: company_id,
      period_id: Taxvision.Periods.fetch!(period).id,
      actor: actor.subject,
      actor_roles: actor.roles,
      # The tenant is read from a claim by **domain code**, not from an engine
      # struct: "whose company is this" is a TaxVision question, not a PNS one.
      actor_company: actor.claims["company_id"],
      completeness_confirmed: true,
      # A `DateTime`, not text. It used to be serialised here by hand, because the
      # engine passed payload values through untouched and a point in time came back
      # from the queue as a string — so the field was declared `:timestamp` and held
      # text to keep both handlers seeing one shape. `PNS.Payload` restores it now, so
      # the workaround is gone and the declaration means what it says.
      checked_at: DateTime.utc_now(),
      abilia: %{legal_form: "JDG", vat_status: "czynny"},
      registries: registries
    }
  end
end

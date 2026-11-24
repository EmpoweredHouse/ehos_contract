defmodule EhosContract.TestRepo do
  @moduledoc """
  The repo the package's own suite runs against.

  It exists so the engine can be tested without a client application. Until
  2026-08-21 the only repo in the repository was a client's, so every engine
  test ran inside the client's tree — `boundary` had enforced the seam in `lib/`
  since the first commit and never covered `test/`, which is the half of the
  extraction that had not been paid for.

  Its schema comes from `EhosContract.Migrations`, which makes this suite the package's
  first consumer of its own migration and the cheapest available proof that the
  migration works.
  """

  use Ecto.Repo, otp_app: :ehos_contract, adapter: Ecto.Adapters.Postgres
end

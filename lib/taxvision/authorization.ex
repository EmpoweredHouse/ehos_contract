defmodule Taxvision.Authorization do
  @moduledoc """
  **Trzeci poziom IAM: reguła domenowa. Nasza, nie kupiona.**

  Provider tożsamości odpowiada, kto to jest (poziom 1), i czy ta osoba dosięga
  API księgowego w ogóle (poziom 2, grant roli jako claim). Tego niżej nie
  wyrazi żadną konfiguracją, bo nie wie, czym jest miesiąc księgowy ani czyja
  jest firma.

  Dlatego reguła siedzi w kontrakcie jako `rule` z przykładami, dokładnie jak
  każda inna reguła biznesowa — i tak samo jest testowana. Gdyby dała się
  zapisać jako polityka w panelu providera, szew byłby postawiony w złym
  miejscu.

  Czysta funkcja, zero dostępu do bazy, zero wiedzy o tokenach.
  """

  use Boundary, deps: [], exports: []

  @doc "Miesiąc otwiera księgowa przypisana do tej firmy."
  def authorize_open_month(%{command: :open_month} = input) do
    roles = input[:actor_roles] || []

    cond do
      "accounting" not in roles -> {:error, :not_accounting}
      input[:actor_company] != input[:company_id] -> {:error, :not_this_company}
      true -> :ok
    end
  end
end

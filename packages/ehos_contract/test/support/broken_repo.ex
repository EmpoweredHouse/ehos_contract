defmodule EhosContract.BrokenRepo do
  @moduledoc """
  `EhosContract.TestRepo` in every function but one: writing a command's `failed`
  row raises, as a lost connection would. For the test that dispatch's own failure
  record cannot hide the exception it records (plan E7a, finding 5 of E6's review).
  """

  for {name, arity} <- EhosContract.TestRepo.__info__(:functions), name != :insert! do
    args = Macro.generate_arguments(arity, __MODULE__)

    @doc false
    def unquote(name)(unquote_splicing(args)),
      do: EhosContract.TestRepo.unquote(name)(unquote_splicing(args))
  end

  @doc false
  def insert!(struct, opts \\ [])

  def insert!(%EhosContract.CommandRecord{outcome: "failed"}, _opts),
    do: raise(DBConnection.ConnectionError, "connection lost while writing the failed row")

  def insert!(struct, opts), do: EhosContract.TestRepo.insert!(struct, opts)
end

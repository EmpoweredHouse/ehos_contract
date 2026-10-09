defmodule EhOsContract.Auth.People.Person do
  # The people API's person: `eh-os` D-80.
  @moduledoc """
  A person as EHOS's people API answers them: `id`, which never changes
  and is the `sub` sign-in gives; `email`, which can; `name`, optional, which two people
  can share, so show the email beside it; and `state`, `:invited`, `:joined` or
  `:disabled`.
  """

  @enforce_keys [:id, :email, :name, :state]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          id: String.t(),
          email: String.t(),
          name: String.t() | nil,
          state: :invited | :joined | :disabled
        }

  @states %{"invited" => :invited, "joined" => :joined, "disabled" => :disabled}

  @doc false
  # A person as EHOS writes one, or `:error` for anything else: an answer EHOS never gives is
  # not read as a person.
  @spec from_map(term()) :: {:ok, t()} | :error
  def from_map(%{"id" => id, "email" => email, "state" => state} = person)
      when is_binary(id) and is_binary(email) and is_map_key(@states, state) do
    case Map.get(person, "name") do
      name when is_binary(name) or is_nil(name) ->
        {:ok, %__MODULE__{id: id, email: email, name: name, state: Map.fetch!(@states, state)}}

      _other ->
        :error
    end
  end

  def from_map(_other), do: :error
end

defmodule EhosContract.Auth.Grants.Grant do
  # The grant route's answer, as EHOS's grants API gives it for granting a role.
  @moduledoc """
  What EHOS answered a grant, for the page to say: who was granted the role, and what
  became of it.

    * `person_id`: the person's id at EHOS, which never changes. Keep it to revoke the
      role later, with `EhosContract.Auth.Grants.revoke/4`;
    * `email`, as EHOS holds it;
    * `state`: `:invited` while the person has not signed in yet, `:joined` once they
      have. An application learns it only of the people it grants a role to;
    * `role`, `<application>.<name>`, and `role_binding_id`, its binding's id;
    * `bound`: `:now`, or `:before` when the person held the role already and it was
      left as it was;
    * `delivery`: `:mailed`, the person was sent a sign-in link; `:held`, too many links
      went to them from this application in the last hour, so none was made and the last
      one sent still signs them in; `:none`, they have joined, and sign in as before.
  """

  @enforce_keys [:person_id, :email, :state, :role, :role_binding_id, :bound, :delivery]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          person_id: String.t(),
          email: String.t(),
          state: :invited | :joined,
          role: String.t(),
          role_binding_id: String.t(),
          bound: :now | :before,
          delivery: :mailed | :held | :none
        }

  @states %{"invited" => :invited, "joined" => :joined}
  @bound %{"now" => :now, "before" => :before}
  @deliveries %{"mailed" => :mailed, "held" => :held, "none" => :none}

  @doc false
  # The answer as EHOS writes it, or `:error` for anything else: an answer EHOS never gives is
  # not read as a grant.
  @spec from_map(term()) :: {:ok, t()} | :error
  def from_map(%{
        "person" => %{"id" => id, "email" => email, "state" => state},
        "role_binding" => %{"id" => binding_id, "role" => role, "bound" => bound},
        "delivery" => delivery
      })
      when is_binary(id) and is_binary(email) and is_map_key(@states, state) and
             is_binary(binding_id) and is_binary(role) and is_map_key(@bound, bound) and
             is_map_key(@deliveries, delivery) do
    {:ok,
     %__MODULE__{
       person_id: id,
       email: email,
       state: Map.fetch!(@states, state),
       role: role,
       role_binding_id: binding_id,
       bound: Map.fetch!(@bound, bound),
       delivery: Map.fetch!(@deliveries, delivery)
     }}
  end

  def from_map(_other), do: :error
end

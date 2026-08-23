defmodule PNS.Web.Live.Accounts do
  @moduledoc """
  Screen 2 of 2: the accounts screen `docs/adr/identity-seam.md` decided on 9
  August calls the engine's own API, never the sidecar directly. Every
  action here is exactly one call into `PNS.Auth` — list, grant, revoke,
  invite — because the seam is thin by design: a company-specific rule on
  top of a grant is code, and it belongs in the contract, not here.

  `:read_only` finally means something different from `:all`: everyone with
  access sees the roster, only `:all` can change it. Enforced twice, the
  same shape `PNS.Web.Authentication` already uses for the dashboard as a
  whole — hidden in the markup so a `:read_only` user is not shown a button
  that will refuse them, and checked again in every `handle_event`, because
  a LiveView event is a message a client can send regardless of what is
  rendered.
  """

  use Phoenix.LiveView

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign_users(socket)}
  end

  @impl true
  def handle_event("invite", %{"name" => name, "email" => email}, socket) do
    with_write_access(socket, fn ->
      case PNS.Auth.invite_user(email, name) do
        {:ok, _user} -> assign_users(socket)
        {:error, _reason} -> socket
      end
    end)
  end

  def handle_event("grant_role", %{"user_id" => user_id, "role" => role}, socket) do
    with_write_access(socket, fn ->
      PNS.Auth.grant_role(user_id, role)
      assign_users(socket)
    end)
  end

  def handle_event("revoke_role", %{"user_id" => user_id, "role" => role}, socket) do
    with_write_access(socket, fn ->
      PNS.Auth.revoke_role(user_id, role)
      assign_users(socket)
    end)
  end

  # The UI hides these actions from a :read_only user; this is the check
  # that matters, because hiding a button does not stop a client from
  # sending the event it would have triggered.
  @spec with_write_access(Phoenix.LiveView.Socket.t(), (-> Phoenix.LiveView.Socket.t())) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  defp with_write_access(socket, fun) do
    if socket.assigns.pns_web_access == :all do
      {:noreply, fun.()}
    else
      {:noreply, socket}
    end
  end

  @spec assign_users(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp assign_users(socket), do: assign(socket, :users, PNS.Auth.list_users())

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <PNS.Web.Layouts.nav base_path={@pns_web_base_path} current={:accounts} />
      <p>Access: {access_label(@pns_web_access)}</p>

      <table>
        <thead>
          <tr>
            <th>Name</th>
            <th>Email</th>
            <th>Roles</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={user <- @users}>
            <td>{user.name}</td>
            <td>{user.email}</td>
            <td>
              <span :for={role <- user.roles}>
                {role}
                <button
                  :if={@pns_web_access == :all}
                  phx-click="revoke_role"
                  phx-value-user_id={user.id}
                  phx-value-role={role}
                >
                  Revoke
                </button>
              </span>
              <p :if={user.roles == []}>No roles granted.</p>

              <form :if={@pns_web_access == :all} phx-submit="grant_role">
                <input type="hidden" name="user_id" value={user.id} />
                <input type="text" name="role" placeholder="role to grant" required />
                <button type="submit">Grant</button>
              </form>
            </td>
          </tr>
        </tbody>
      </table>

      <p :if={@users == []}>No users yet.</p>

      <form :if={@pns_web_access == :all} phx-submit="invite">
        <h3>Invite someone</h3>
        <input type="text" name="name" placeholder="name" required />
        <input type="email" name="email" placeholder="email" required />
        <button type="submit">Invite</button>
      </form>
    </div>
    """
  end

  @spec access_label(:all | :read_only) :: String.t()
  defp access_label(:all), do: "all"
  defp access_label(:read_only), do: "read only"
end

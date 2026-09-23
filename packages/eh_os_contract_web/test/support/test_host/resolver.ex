defmodule EhOsContract.Web.TestHost.Resolver do
  @moduledoc """
  The test host's own answer to "who may see the dashboard" — what every host
  now writes for itself, since `eh_os_contract_web` ships no default. Two invented roles
  map to the two access levels; anything else is sent to `/`, a path that is
  the host's to choose because the package has no login screen to send it to.
  """

  @behaviour EhOsContract.Web.Resolver

  @impl true
  def resolve_user(conn) do
    case Plug.Conn.get_req_header(conn, "x-test-roles") do
      [roles] -> String.split(roles, ",", trim: true)
      [] -> nil
    end
  end

  @impl true
  def resolve_access(roles, _base_path) when is_list(roles) do
    cond do
      "eh_os_contract_admin" in roles -> :all
      "eh_os_contract_read" in roles -> :read_only
      true -> {:forbidden, "/"}
    end
  end

  def resolve_access(nil, _base_path), do: {:forbidden, "/"}
end

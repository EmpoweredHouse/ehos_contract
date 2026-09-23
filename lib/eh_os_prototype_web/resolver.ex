defmodule EhOsPrototypeWeb.Resolver do
  @moduledoc """
  Everyone gets `:read_only`. This host has no login and is not meant to have
  one: it runs on a developer's own machine, and `eh_os_contract_web` requires a host to
  state its access rule rather than inheriting one. Nothing here belongs
  pointed at anything but localhost.
  """

  @behaviour EhOsContract.Web.Resolver

  @impl true
  def resolve_user(_conn), do: nil

  @impl true
  def resolve_access(_user, _base_path), do: :read_only
end

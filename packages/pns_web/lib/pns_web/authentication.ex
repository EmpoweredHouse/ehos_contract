defmodule PNS.Web.Authentication do
  @moduledoc """
  The `on_mount` hook `pns_dashboard/2` always installs first. Recomputes
  `resolve_access/1` on every mount *and* reconnect — the same shape as
  `Oban.Web.Authentication`, not a decision cached once in the session — so a
  permission change between the first render and a LiveView reconnect takes
  effect immediately rather than on the next full page load.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [redirect: 2]

  @spec on_mount(:default, map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:cont, Phoenix.LiveView.Socket.t()} | {:halt, Phoenix.LiveView.Socket.t()}
  def on_mount(:default, _params, %{"user" => user, "resolver" => resolver}, socket) do
    case resolver.resolve_access(user) do
      {:forbidden, path} -> {:halt, redirect(socket, to: path)}
      access -> {:cont, assign(socket, :pns_web_access, access)}
    end
  end
end

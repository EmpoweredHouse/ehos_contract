defmodule EhosContract.Web.Authentication do
  # The `on_mount` hook `ehos_contract_dashboard/2` always installs first. Recomputes
  # `resolve_access/2` on every mount *and* reconnect — the same shape as
  # `Oban.Web.Authentication`, not a decision cached once in the session. The user it is
  # given is the one `resolve_user/1` returned on the page load, signed into the page, so
  # a permission takes effect on reconnect only when `resolve_access/2` looks it up.
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [redirect: 2]

  @spec on_mount(:default, map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:cont, Phoenix.LiveView.Socket.t()} | {:halt, Phoenix.LiveView.Socket.t()}
  def on_mount(
        :default,
        _params,
        %{"user" => user, "resolver" => resolver, "base_path" => base_path},
        socket
      ) do
    case resolver.resolve_access(user, base_path) do
      {:forbidden, path} ->
        {:halt, redirect(socket, to: path)}

      access ->
        {:cont,
         socket
         |> assign(:ehos_contract_web_access, access)
         |> assign(:ehos_contract_web_base_path, base_path)}
    end
  end
end

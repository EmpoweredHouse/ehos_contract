defmodule EhOsContract.Auth.ReturnTo do
  @moduledoc false
  # Where a sign-in sends the browser back to: a path of this application, never a URL or a
  # path a browser reads as another host's (`//host`, `/\host`, or `/<tab>/host`, since a
  # browser drops a tab or a newline). One rule for `EhOsContract.Auth.SignIn.Router` and
  # `EhOsContract.Auth.Development.Router`, so neither is an open redirect.

  @spec local_path(term()) :: String.t()
  def local_path(path) when is_binary(path) do
    with true <- String.valid?(path),
         "/" <> rest <- path,
         false <- String.starts_with?(rest, "/"),
         false <- String.match?(path, ~r/[\x00-\x1f\x7f\\]/u),
         %URI{scheme: nil, host: nil} <- URI.parse(path) do
      path
    else
      _other -> "/"
    end
  end

  def local_path(_path), do: "/"
end

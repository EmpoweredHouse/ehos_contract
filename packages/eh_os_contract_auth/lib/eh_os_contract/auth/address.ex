defmodule EhOsContract.Auth.Address do
  @moduledoc false

  # Whether an address of EHOS's, the issuer or the key set's, is one every parser reads alike:
  # EHOS's own rule (`Ehos.Credentials.check_issuer/1`, eh-os#118), with a path, since the key
  # set's has one (#89). `URI.parse/1` reads `http://evil.example\@localhost` as `localhost`,
  # where a browser or Node's `URL` reads `evil.example`; so the address must read back as it was
  # written, its scheme's own port aside, with no user, query or fragment, and a host that is a
  # lowercase DNS name, an IPv4 address in its one dotted form, or `::1`. Plain http only on
  # `localhost`, `127.0.0.1` and `::1`, and only with `plain_on_loopback: true`.

  @loopback ["localhost", "127.0.0.1", "::1"]
  @dns_name ~r/\A[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*\z/

  @doc false
  @spec check(term(), keyword()) :: :ok | :error
  def check(address, opts) when is_binary(address) do
    with {:ok, %URI{userinfo: nil, query: nil, fragment: nil} = uri} <- URI.new(address),
         true <- uri.port in 1..65_535 and address in written(uri),
         true <- served?(uri.scheme, uri.host, Keyword.fetch!(opts, :plain_on_loopback)) do
      :ok
    else
      _refused -> :error
    end
  end

  def check(_address, _opts), do: :error

  defp served?("https", host, _plain) when is_binary(host),
    do: host == "::1" or (host =~ @dns_name and (not numeric?(host) or dotted_quad?(host)))

  defp served?("http", host, true), do: host in @loopback
  defp served?(_scheme, _host, _plain), do: false

  # As `URI.to_string/1` writes it, or with its scheme's own port written out.
  defp written(uri) do
    authority = URI.to_string(%{uri | path: nil})
    path = uri.path || ""
    [authority <> path, authority <> ":#{uri.port}" <> path]
  end

  # A host a browser reads as an IPv4 address (WHATWG URL): its last label is a number.
  defp numeric?(host),
    do: host |> String.split(".") |> List.last() =~ ~r/\A(0x[0-9a-f]*|[0-9]+)\z/

  defp dotted_quad?(host) do
    case :inet.parse_ipv4strict_address(String.to_charlist(host)) do
      {:ok, address} -> to_string(:inet.ntoa(address)) == host
      {:error, _not} -> false
    end
  end
end

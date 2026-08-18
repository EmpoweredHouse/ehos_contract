# Manual PoC space for docs/adr/identity-seam.md — not part of `mix check`,
# not run by anything automatically. Exercises PNS.Auth.OidcVerifier against a
# real sidecar so conclusions can be written back into that document instead
# of guessed from vendor docs.
#
# Usage:
#
#   docker compose -f docker-compose.identity.yml up -d
#
#   # One-time: create a machine user's client credentials via the Management
#   # API, using the PAT the sidecar wrote to tmp/identity-poc/admin.pat (see
#   # the compose file's FirstInstance.* comments for how that PAT exists
#   # without a human clicking through the console first). There is no script
#   # for this step — it is one `curl` against
#   # `/management/v1/users/{id}/secret`, deliberately manual so it stays a
#   # decision each time rather than a fixture that quietly goes stale.
#
#   ZITADEL_CLIENT_ID=... ZITADEL_CLIENT_SECRET=... \
#     MIX_ENV=dev mix run priv/poc/identity_smoke_test.exs
#
# With no ZITADEL_TOKEN given, this script requests one itself via
# client_credentials and verifies that. Pass ZITADEL_TOKEN to check a token
# from somewhere else instead (an id_token copied out of a manual login, for
# example).

# Same fix as `Mix.Tasks.Pns.Check` needs, and for the same reason (CLAUDE.md):
# stdout defaults to latin1 when it is not a terminal, which mangles every
# non-ASCII byte in the messages below.
:io.setopts(:standard_io, encoding: :unicode)

issuer = System.get_env("ZITADEL_ISSUER", "http://localhost:8080")
client_id = System.fetch_env!("ZITADEL_CLIENT_ID")
client_secret = System.fetch_env!("ZITADEL_CLIENT_SECRET")

{:ok, _pid} =
  Oidcc.ProviderConfiguration.Worker.start_link(%{
    issuer: issuer,
    name: __MODULE__.Provider,
    # The sidecar runs without TLS on purpose (docker-compose.identity.yml —
    # `--tlsMode disabled`), which is fine for a local PoC and would not be
    # for anything this seam actually points a client at.
    provider_configuration_opts: %{quirks: %{allow_unsafe_http: true}}
  })

# The worker loads configuration and JWKS lazily on first use — give it a
# moment rather than racing the first request against an empty cache.
Process.sleep(500)

token =
  case System.get_env("ZITADEL_TOKEN") do
    nil ->
      IO.puts("No ZITADEL_TOKEN given — requesting one via client_credentials...")

      {:ok, oidcc_token} =
        Oidcc.client_credentials_token(__MODULE__.Provider, client_id, client_secret, %{
          scope: ["openid"]
        })

      IO.puts("""
      Got a token pair. Zitadel's default access_token here is an encrypted \
      JWE (5 dot-separated segments), not the plain signed JWT the seam \
      wants — see the finding logged in docs/adr/identity-seam.md. Verifying \
      the id_token instead, which is always a signed JWT under OIDC:
      """)

      oidcc_token.id.token

    token ->
      token
  end

Application.put_env(:pns_prototype, PNS.Auth.OidcVerifier,
  provider: __MODULE__.Provider,
  client_id: client_id,
  client_secret: client_secret
)

case PNS.Auth.OidcVerifier.verify(token) do
  {:ok, actor} -> IO.inspect(actor, label: "verified")
  {:error, reason} -> IO.inspect(reason, label: "rejected")
end

# Call a host outside the installation

This page tells a developer how the application calls a host outside the installation of EHOS, for
example a public registry of companies. EHOS lets the application out only through a proxy of the
application, and the HTTP client of the application must use that proxy.

## Prerequisites

- The application calls the host with Req. Another client uses the variables of step 1 itself.

## 1. Name the host in `ehos.yaml`

Add the host to `needs.egress` in the `ehos.yaml` of the application, at `ehos.yaml/v5` or later:

```yaml
schema: ehos.yaml/v5
needs:
  egress:
    - host: registry.example.org      # port 443 when not given
```

Each host is a DNS name in lower case, never an address or a pattern. A deployment that adds,
removes or changes a host needs `ehos.application.register` at EHOS.

**Result:** EHOS gives the workload these variables. EHOS refuses each other way out of the
installation.

| Variable | What it holds |
| --- | --- |
| `EHOS_EGRESS_PROXY` | the proxy of the application, `host:port` |
| `HTTPS_PROXY` | the same proxy, for clients that read this variable |
| `NO_PROXY` | the hosts that the application calls directly, such as EHOS and the other applications of the installation |

## 2. Attach the proxy to the client

Req reads none of these variables. Attach `EhosContract.Auth.Egress` to the client that calls the
host:

```elixir
Req.new(base_url: "https://registry.example.org", redirect: false, retry: false)
|> EhosContract.Auth.Egress.attach()
|> Req.get!(url: "/companies/123")
```

The host outside the installation is not under your control. Req has defaults that let it decide
too much:

- **Req follows redirects.** A redirect to a plain `http` address, or to a host that `NO_PROXY`
  names, goes directly, not through the proxy. So it can reach a service inside the installation.
  Give `redirect: false` unless the host needs redirects.
- **Req tries a `GET` 3 more times**, and `receive_timeout` limits each wait for data, not the whole
  call. Give `retry: false`, and run the call in a task with a deadline if a person waits for it.
- **Req reads the whole answer into memory**, and decompresses it, before it gives it to you. It
  has no size limit. To stop at a size, read the body with an `into:` function that halts past the
  limit, and give `decode_body: false`.

Attach it after each step of your own that changes the URL of a request. The plugin then decides on
the URL that the client sends.

Attach the plugin only to the clients that call outside. You cannot make it a default of Req. The
defaults of Req hold options, not steps, and only a step can send a host of `NO_PROXY` directly.

**Result:** an `https` request goes through a `CONNECT` tunnel to the proxy. The client verifies TLS
against the name of the host, as it does without a proxy.

## Which requests go through the proxy?

The plugin reads `EHOS_EGRESS_PROXY` and `NO_PROXY` for each request, not when you attach it. It
decides again for each redirect and each retry, for the host that the request goes to.

A request goes directly, without the proxy, in each of these cases:

- `NO_PROXY` names the host.
- The URL is plain `http`. The proxy refuses it, and the plugin does not send its headers and body
  to the proxy without encryption. EHOS refuses a direct call out of the installation, so a host
  outside it needs `https`.
- `EHOS_EGRESS_PROXY` is not set or is empty: in development, in tests, or when the application
  names no host.

The plugin reads `NO_PROXY` as EHOS writes it, or `no_proxy` when `NO_PROXY` is not set:

- An entry names a host and each name under it. A dot at the start changes nothing.
- The port of an entry is not compared.
- `*` names each host.
- A range of addresses, such as `10.0.0.0/8`, names nothing.

A proxy that the caller sets in `connect_options` is the proxy of the caller. The plugin keeps it on
each hop, also on a plain `http` hop, which then goes to that proxy without encryption.

Each request through the proxy starts the Finch pool of Req for its options. This costs nothing
beside a call out of the installation. It matters only for many calls each second.

## What can go wrong

The plugin raises `ArgumentError`:

- for a request with its own Finch pool (`:finch`), when you attach it or when the request gets one
  later. Req cannot give a proxy to such a pool, so give the proxy to the pool;
- for an `https` request that uses only HTTP/2 (`connect_options: [protocols: [:http2]]`), also
  without `EHOS_EGRESS_PROXY`. Mint goes through a proxy only with HTTP/1, so allow `:http1`;
- when `EHOS_EGRESS_PROXY` is not `host:port`, at the request. EHOS never writes such a value.

A client that is not Req uses `EHOS_EGRESS_PROXY` as an HTTP proxy that it tunnels through, or reads
`HTTPS_PROXY` and `NO_PROXY` itself. `EhosContract.Auth.Egress.proxy/2` gives the proxy for a host
from these variables, or `nil` when the call goes directly.

## Next steps

- [Get started](getting-started.md): the configuration that each application needs.
- [Read the people of the company](people.md): call EHOS itself, which needs no proxy.

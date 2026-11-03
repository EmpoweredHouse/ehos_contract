# Where do the keys come from?

The application must know that a credential comes from EHOS. It checks the signature of the
credential against the public keys of EHOS. This page tells where those keys come from, why the
application can trust them, and how the key process keeps them. It is for a developer who connects
an application to EHOS, and for a reviewer of its security.

Nothing about the keys is configured in the application, except the address of EHOS and, sometimes,
its certificate authority: [Configure the package](configuration.md).

## Who holds what?

![EHOS issues each credential, the key process of the application fetches the public keys of EHOS over HTTPS and keeps them in its table, and verify/2 checks each credential against them.](img/keys.svg)

1. EHOS issues a credential, signed with the private key from its Kubernetes Secret.
2. The key process fetches the public keys of EHOS over HTTPS, as a JWKS from
   `<issuer>/.well-known/jwks.json`. It checks the TLS certificate of EHOS.
3. The key process writes the keys to its table, `eh_os_contract_auth_keys`.
4. At start, the key process loads the last keys from its table.
5. The caller sends the credential to the application.
6. `verify/2` checks the signature against a key in the memory of the key process.

| What | Who makes it | Where it is | Who sees it |
| --- | --- | --- | --- |
| The Ed25519 key pair that signs credentials | the Helm chart of EHOS (`genPrivateKey "ed25519"`) when the Secret is missing, or the operator through `governance.signingKeys.existingSecret` | a Kubernetes Secret: `current.pem`, and `previous.pem` during a rotation | only the governance plane of EHOS, which mounts it read-only. It is never in a database, and no application sees it. |
| The public keys (JWKS) | EHOS, from the Secret | `GET <issuer>/.well-known/jwks.json` | anyone. The key process fetches them and keeps a copy in its table. |
| The `kid` in the header of a credential | nobody: it is the RFC 7638 thumbprint of the key | computed by EHOS when it signs, and by the key process from the JWKS | nobody configures it. The key process ignores a `kid` that the JWKS writes beside a key. |
| The TLS certificate of the address of EHOS | the operator of the cluster: cert-manager, a public authority or an internal one | the ingress of EHOS | each fetch of the JWKS checks it |

## Why is the TLS certificate the trust anchor?

The application trusts a credential because its signature agrees with a key from the JWKS. It trusts
the JWKS because the JWKS came over HTTPS from the configured issuer. A person who can answer for
that address can publish keys of their own. So the certificate of the address of EHOS is the one
thing that an integration must get right.

The fetch checks the certificate against the certificate authorities of the system. If EHOS uses an
internal authority, give it to the child with `cacertfile:` or `cacerts:`. EHOS gives its file as
`EHOS_CA_FILE`.

The package cannot turn off the check of the certificate. So you cannot make a first integration
work without the check: the keys would then come from anyone who answers. For the same reason, the
package fetches the keys only over `https`. It allows plain `http` only on `localhost`,
`127.0.0.1` and `::1`. This holds also when the application starts `EhOsContract.Auth.Keys` itself.

## How does the key process keep the keys?

The table of the key process is the source of the keys, and its memory is a copy.

- **At start**, the process loads the last good keys from its table. Then it fetches the JWKS.
- **Every 5 minutes**, it fetches the JWKS again. If EHOS removes a key, a compromised key for
  example, the application stops trusting it within 5 minutes. Nobody restarts anything.
- **A credential with an unknown `kid`** starts an early fetch. The process fetches early at most
  one time in 30 seconds. Each fetch starts these 30 seconds again, a scheduled or a failed fetch
  too.
- **A failed fetch changes nothing.** The process logs it, and the last good keys stay in force.
- **A successful fetch** puts the new keys in memory first, then writes them to the table.

These answers are failed fetches:

- a JWKS without an Ed25519 key;
- a JWKS with more than 16 keys. A rotation has 2;
- an answer of more than 64 KB;
- a redirect;
- an answer that is not complete after 5 seconds.

If a migration or `VACUUM FULL` locks the table, the process waits 1 second or less. Then it logs
the write as failed, and the next fetch writes the table again.

### When does nobody get in?

An application that has never had a key refuses each credential with `:no_keys`, and logs it at
start. This is the one case in which "EHOS is down" becomes "nobody gets in". The application also
refuses with `:no_keys` while the key process does not run.

`EhOsContract.Auth.ready?/0` returns `false` in both cases. Use it in the health check of the
application.

After one fetch succeeds, the keys are in the table. Then the application accepts credentials while
EHOS is down, also after a restart.

## How does EHOS rotate its key?

The rotation is manual, and the operator of EHOS does it:

1. The operator moves `current` to `previous`, and adds a new `current`.
2. The operator rolls out EHOS. EHOS signs with the new key, and the JWKS publishes both keys.
3. After 10 minutes, the life of one credential, the operator removes `previous`.

The application does nothing:

- A credential signed with the new key has a `kid` that the application does not know. This starts
  an early fetch.
- The fetch every 5 minutes removes `previous` from memory and from the table after the JWKS drops
  it.

## Limits

- The fetch cannot go through a proxy, and cannot send a client certificate.
- After EHOS removes a key, the application trusts it until the next scheduled fetch: 5 minutes or
  less.

## Next steps

- [Configure the package](configuration.md): the address of EHOS, its certificate authority, and
  the limits of the fetch.
- [The credential](credential.md): what `verify/2` checks with the key.
- [Test the application without EHOS](testing.md): a test key, with no EHOS and no network.

<!-- Decisions behind this page:
EHOS's decisions this package follows:
- the credential, a ten-minute Ed25519 JWT with the key's thumbprint as kid; manual key rotation;
- keys kept in the application's own table.
#89: the issuer and every address read alike by every parser.
-->

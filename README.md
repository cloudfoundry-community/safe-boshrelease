# safe-boshrelease - A Better Vault BOSH Release

Vault is a secure credentials storage system from Hashicorp.

It stands up a multi-homed Vault with Consul as a storage backend.

## But Why Not Use The Vault BOSH Release?

I have, and I do.  But it provides way more option than the
typical set up needs.  If that works for you and it makes you
happy, great.  I wanted something simpler and more opinionated.

## How Does This Relate To The `safe` CLI for Vault?

[safe][safe] has some built-in support for this particular BOSH
release, by way of a thing called [`strongbox`][strongbox].  Primarily, the
extra handy `safe unseal` and `safe seal` commands work _only_
with this BOSH release.

## How Do I Deploy It?

A sample manifest is available at `manifests/safe.yml`; it has
everything you need to run a 3-node Vault.

```
bosh -e your-bosh-director -d safe deploy manifests/safe.yml
```

Once Vault is running, you can use `safe` to initialize it:

```
$ safe target https://your.vault.ip some-alias -k
$ safe init
Unseal Key #1: G55lL0iDddspbNxthYPh0RtZb7cWENfJqm6ZhL9LrnkH
Unseal Key #2: 7aGZ4af/dfnJBriYhDftcR6u6ck2iRW8VwY2Aooo4sAR
Unseal Key #3: jcTn71H70++Uq9pkdSLNgoUVeq+h/rakHjzdBgBheTJx
Unseal Key #4: 9SsFAO8nC7xGuL1nf+a1dK1+nsnkqJeHiCEeHgYcpP4L
Unseal Key #5: J8hRCkXnWCx00kC8tyCiyKRxfULDhEGHd/fuO5bKuvxI
Initial Root Token: fa6fc1dd-f70b-dbaf-165f-a95500523454

Vault initialized with 5 keys and a key threshold of 3. Please
securely distribute the above keys. When the Vault is re-sealed,
restarted, or stopped, you must provide at least 3 of these keys
to unseal it again.

Vault does not store the master key. Without at least 3 keys,
your Vault will remain permanently sealed.

safe has unsealed the Vault for you, and written a test value
at secret/handshake.

You have been automatically authenticated to the Vault with the
initial root token.  Be safe out there!
```

**Note**: You will need safe v1.0.0 or higher, since this BOSH
release now ships with Vault 1.0.2, and `safe init` from earlier
versions are known to not work.

That's all there is to it!

## Vault 2 and Consul 2

This release ships Vault 2.2.0 and Consul 2.0.4. Both are released under the Business Source License 1.1 rather than the Mozilla Public License that covered the versions this release shipped before (Vault 1.14.7 and Consul 1.16.4). Review the BUSL terms for your use before you deploy.

The job templates no longer use `chpst`, so the release runs on stemcells that do not ship runit, such as Ubuntu 26.04 (`resolute`). The vault, consul, strongbox, and broker control scripts drop privileges with `setpriv`, which comes from `util-linux` on the stemcell.

Vault stores its data in Consul, so the order of an upgrade matters.

- Take a Consul snapshot (`consul snapshot save`) and keep a copy of the Vault unseal keys before you deploy. A Vault that a 2.x server has unsealed cannot be rolled back to 1.14.x.

- Consul documents that a standard upgrade should jump at most two major versions, and that a cluster far behind should step through intermediate releases. Going from 1.16 to 2.0 is well outside that guidance, so plan the upgrade either as a series of deployments through intermediate Consul releases (1.18, 1.20, 1.22, and then 2.0) or as a fresh cluster that you restore from a snapshot.

- Update one node at a time and wait for `consul operator raft list-peers` to show a leader and three voters before you continue. The release deploys serially, and `bootstrap_expect` stays at the cluster size.

- Consul servers that already have a `raft.db` file keep the BoltDB log store. Only new servers start on the WAL log store, which became the default in Consul 1.20.

The Consul agent configuration now uses the `tls.defaults` block in place of the top-level `ca_file`, `cert_file`, `key_file`, `verify_incoming`, and `verify_outgoing` settings, and no longer sets `start_join` because `retry_join` already covers it. The Vault configuration uses the `storage` stanza in place of the older `backend` name.

## Using the Vault Service Broker

If you want to deploy the [Vault Service Broker][sb] via BOSH, you
can add the BOSH ops file to your deploy:

```
bosh -e your-bosh-director -d safe deploy \
     manifests/safe.yml \
  -o manifests/ops/broker.yml \
  -v cf-api-url="..." \
  -v cf-username="..." \
  -v cf-password="..." \
  -v cf-skip-ssl-validation=no \
  -v vault-token="..." \
  -v vault-broker-guid="..." \
  -v vault-broker-password="..."
```

The following variables must be specified:

- **cf-api-url** - The full URL of the Cloud Foundry API.
- **cf-username** - What username to sign into CF with.
- **cf-password** - Password to use for authentication to CF.
- **cf-skip-ssl-validation** - Whether or not to ignore SSL/TLS
  certificate validation errors (expiration, subject mismatch,
  etc.)  You probably want to set this to `no`.
- **vault-token** - A root token for the broker to authenticate.
- **vault-broker-guid** - Unique ID for the service broker to use
  in its plan and service metadata.  Once the broker has been
  registered with the CF marketplace, this should not change.
- **vault-broker-password** - The password to require for
  communication between CF and the Vault broker.

Once deployed, you can register the Vault service broker with
Cloud Foundry, and enable marketplace access to plans, via the
register-broker errand:

```
bosh -e your-bosh-director -d safe run-errand register-broker
```

Note: since you **must** supply a Vault token to the broker, you
will always have to deploy Vault without the broker component,
initialize and unseal, and _then_ re-deploy with the broker
enabled.  Otherwise, the broker BOSH (monit) jobs will fail to
start up properly, and the deployment as a whole will fail.

[safe]: https://github.com/starkandwayne/safe
[sb]:   https://github.com/cloudfoundry-community/vault-broker
[strongbox]: https://github.com/jhunt/go-strongbox

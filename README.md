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

- **Snapshot first**
  Take a Consul snapshot and keep a copy of the Vault unseal keys before you deploy, because a Vault that a 2.x server has unsealed can't be rolled back to 1.14.x.  Consul serves HTTPS only, so run the snapshot on one of the vault instances with `CONSUL_HTTP_ADDR=https://127.0.0.1:8500 CONSUL_CACERT=/var/vcap/jobs/vault/tls/peer/ca.pem /var/vcap/packages/consul/bin/consul snapshot save /var/vcap/store/vault/pre-upgrade.snap`, and copy the file off the VM.  When the peer certificates are not self-signed, also set `CONSUL_CLIENT_CERT` and `CONSUL_CLIENT_KEY` to the `cert.pem` and `key.pem` files in the same directory.

- **The upgrade is a direct jump**
  Consul's guidance is to move at most two major versions at a time, and going from 1.16 to 2.0 is well outside it.  No release ships the 1.18, 1.20, or 1.22 servers in between, so this release takes the jump in one step.  When we tested it on a three-node cluster, the first two nodes came up as voters.  The third failed with "is not running after update", because its Consul `raft.db` was corrupt.  The other two nodes still held quorum, so we recovered it by hand and the next deploy finished, with every secret intact.

- **Recovering a node with a corrupt raft.db**
  Do this only while the other servers hold quorum, and on one node at a time.  On the failed node, run `sudo /var/vcap/bosh/bin/monit stop consul`, move `/var/vcap/store/vault/consul/raft` aside, and run `sudo /var/vcap/bosh/bin/monit start consul`.  The server rejoins with its node ID and copies the raft log from the leader.  Check that `consul operator raft list-peers` shows it as a voter before you deploy again.  If quorum is lost, this won't work, so follow Consul's `peers.json` outage recovery instead.

- **Each node waits for the cluster**
  The job's post-start script holds BOSH on each instance until the local Consul server is a healthy voter, there is a leader, the voter count equals the number of vault instances, and autopilot reports the whole cluster healthy.  It needs three passes in a row and gives up after `safe.peer.post_start.timeout` seconds, which defaults to 600, and it polls every `safe.peer.post_start.interval` seconds, which defaults to 5.  BOSH therefore can't stop the next Consul server before the last one has rejoined, whatever the deployment's `update` block says about serial updates.  The script logs each change of state to `post-start.stdout.log`.

- **A brand-new cluster still bootstraps**
  On a first deploy, BOSH starts the servers one at a time and none of them can elect a leader until `bootstrap_expect` servers are up.  The gate lets a server through when it holds no raft data and fewer than the expected number of servers are alive, so the deploy can go on to the next node.  A server that holds raft data never gets this exemption.

- **Starting a stopped cluster**
  If every node is stopped, the first one to start can't find a leader, so a one-at-a-time start times out on it.  Start them together with `bosh start --canaries=0 --max-in-flight=100%`.

- **Deploying with a node already down**
  The gate fails on the first node it updates while another server is dead, because autopilot reports the cluster unhealthy.  Recreate the dead instance on its own first with `bosh recreate vault/<id>`, and then deploy.

- **Stopping keeps a server in raft**
  The consul stop sends SIGINT and waits up to 30 seconds for the server to exit, then sends SIGKILL and waits up to 10 seconds more.  The agent sets `skip_leave_on_interrupt` to true and `leave_on_terminate` to false, so a stopping server stays in the raft configuration and rejoins as the same voter, and the quorum size never changes during a rolling update.  Removing a server for good, as on a scale-down, therefore needs `consul force-leave`, or autopilot's dead-server cleanup.

- **Log store**
  Consul servers that already have a `raft.db` file keep the BoltDB log store.  Only new servers start on the WAL log store, which became the default in Consul 1.20.

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

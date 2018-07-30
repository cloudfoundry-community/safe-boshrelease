# safe-boshrelease - A Better Vault BOSH Release

Vault is a secure credentials storage system from Hashicorp.

It stands up a multi-homed Vault with Consul as a storage backend.

## But Why Not Use The Vault BOSH Release?

I have, and I do.  But it provides way more option than the
typical set up needs.  If that works for you and it makes you
happy, great.  I wanted something simpler and more opinionated.

## How Does This Relate To The `safe` CLI for Vault?

[safe][safe] has some built-in support for this particular BOSH
release, by way of a thing called `strongbox`.  Primarily, the
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

## How do I backup and restore it ?

* Use the [BOSH Backup and Restore][bbr] tool
  * Be careful, running the "restore" script will restart Vault, requiring an **unseal** operation.
  * After unsealing the vault for the first time after a restore, the vault will return HTTP 500 errors for about 15 seconds.

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
[bbr]:  https://docs.cloudfoundry.org/bbr/

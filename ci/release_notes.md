# Licence change

This release ships Vault 2.2.0 and Consul 2.0.4, which HashiCorp publishes under the Business Source License 1.1.  Earlier releases shipped Vault 1.14.7 and Consul 1.16.4 under the Mozilla Public License 2.0.  Review the BUSL terms for your use before you deploy this release.

# Resolute support

- The vault, consul, strongbox, and broker control scripts drop privileges with `setpriv` instead of `chpst`, so the release runs on stemcells without runit, such as Ubuntu 26.04 (`resolute`).

# Vault and Consul

- Bumped Vault to 2.2.0 and Consul to 2.0.4.  The upgrade from Consul 1.16 is a direct jump, so read the "Vault 2 and Consul 2" section of the README before you deploy, and take a Consul snapshot first.

- The Consul configuration moved to the `tls.defaults` block and dropped `start_join`, and the Vault configuration uses the `storage` stanza.

- Vault reaches Consul on 127.0.0.1, which the peer certificate names, instead of `localhost`.

# Safer rolling updates

- A new post-start script holds each instance until its Consul server is a healthy voter in a full, healthy cluster, so BOSH can't take the cluster below quorum.  The new `safe.peer.post_start.timeout` and `safe.peer.post_start.interval` properties set how long it waits and how often it checks.

- Stopping Consul now waits for the server to exit before monit reports it stopped, and a stopping server stays in raft instead of leaving it, so the quorum size stays the same through a rolling update.

# Improvement

- Now ships with a bosh2 manifest, if you're into that.

- The `vault` process now runs as the vcap:vcap user.

- Upgraded from (ancient) Vault 0.6.2 to 0.9.0 (most current)

- The Consul Cluster IPs are now detected automagically via an
  implicit self-link, making the deployment manifest even more
  hands-off than before.

- The README is actually useful now.

- This release now works on the warden CPI, by dynamically
  detecting whether or not the platform supports mlock(2).

- The release internals got cleane dup quite a bit to pull out
  some cruft and cargo-culting that was cluttering up logs.

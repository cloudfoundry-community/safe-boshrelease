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


[safe]: https://github.com/starkandwayne/safe

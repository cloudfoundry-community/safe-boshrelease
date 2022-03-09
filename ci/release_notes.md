## Changes

1. Self signed certificates generation was moved to a pre-start script.

## Features

1. Added the beginnings for spec testing manifests.
2. Added a temporary fix to deal with consul not allowing self signed certificates to be fully specificied in the consul.config file.

## Bugfixes

1. Consul did not work with self signed certiticates when you explicitly specified the certificates and keys.

## Upgrades

| Package | Version |
| --- | --- |
| strongbox | 0.0.4 |
| vault | 1.9.3 |
| consul | 1.11.3 |

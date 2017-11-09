#Improvements

Handle Non RFC1918 compliant ip address for Cousul.

A handful of very large organizations allocate public ip space for use
in their private environments. Consul refuses to bind to a Non RFC1918
address by default and bind_addr needs to be set in the config.

# Development

Update Concourse Templates

#!/bin/bash

METADATA_IP=$(nslookup 'rancher-metadata' 2>/dev/null | grep -vEi "127.0.0.1|localhost|NXDOMAIN" | grep "Address" | sed -e 's/\(.*\):\s+//g')

if [[ -z $METADATA_IP ]]; then
    echo "No Rancher metadata, starting in local mode..."
    env MIX_ENV=prod REPLACE_OS_VARS=true COOKIE="test_cookie" PORT="4000" \
    NODE_NAME="sigil_gateway" \
    mix phx.server
    #./_build/prod/rel/sigil_gateway/bin/sigil_gateway foreground
else
    echo "Rancher metadata, starting in Rancher mode..."
    env MIX_ENV=prod REPLACE_OS_VARS=true \
    NODE_NAME="sigil_gateway" \
    PORT="4000" ./_build/prod/rel/sigil_gateway/bin/sigil_gateway foreground
fi
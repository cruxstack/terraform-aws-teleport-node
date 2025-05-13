#!/bin/bash
# shellcheck disable=SC2034,2154

# --------------------------------------------------------- terraform inputs ---

TELEPORT_EDITION=${tp_edition}
TELEPORT_DOMAIN=${tp_domain}
TELEPORT_CONFIG_ENCODED=${tp_config_encoded}

# ------------------------------------------------------------------- script ---

echo "AWS_DEFAULT_REGION=us-east-1" >>/etc/default/teleport

TELEPORT_VERSION="$(curl "https://$TELEPORT_DOMAIN/v1/webapi/automaticupgrades/channel/stable/cloud/version" | sed 's/v//')"

echo "$TELEPORT_CONFIG_ENCODED" | base64 -d >/etc/teleport.yaml
curl https://cdn.teleport.dev/install.sh | bash -s $TELEPORT_VERSION $TELEPORT_EDITION

sudo systemctl enable teleport
sudo systemctl start teleport

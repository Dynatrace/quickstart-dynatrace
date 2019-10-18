#!/bin/bash -e

PROPERTY_FILE=$1

function getProperty() {
	sed -n -e "/^#\?\s*${1}\s*=.*$/p" $PROPERTY_FILE | cut -d= -f2-
}

REGION=`curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone | sed 's/[a-z]$//'`
SEED_IP_NAME=`getProperty SeedIpName`
SEED_IP=`aws ssm get-parameter --region $REGION --name "$SEED_IP_NAME" | grep -Po 'Value": "\K[^"]*'`
API_TOKEN_NAME=`getProperty SeedTokenName`
API_TOKEN=`aws ssm get-parameter --region $REGION --name "$API_TOKEN_NAME" | grep -Po 'Value": "\K[^"]*'`

function installSeed() {
    local LICENSE_KEY=`getProperty LicenseKey`
    local ADMIN_EMAIL=`getProperty AdminEmail`
    local ADMIN_PASS=`getProperty AdminPassword`
    local SEED_IP_NAME=`getProperty SeedIpName`
    local API_TOKEN_NAME=`getProperty SeedTokenName`

    echo "Run the installer in silent mode, assuming the defaults. Note: license key must be valid and not used by any other cluster"
    cd /tmp
    /bin/sh dynatrace-managed.sh --install-silent --license "$LICENSE_KEY" \
     --initial-environment test \
     --initial-first-name Admin \
     --initial-last-name Admin \
     --initial-email "$ADMIN_EMAIL" \
     --initial-pass "$ADMIN_PASS" | tee /tmp/installer.out

    if [[ "$?" != 0 ]]
    then
        echo "Dynatrace Managed installation failed"
        return 1
    fi

    echo "Dynatrace Managed installation complete"

    local SEED_IP=`curl -s http://169.254.169.254/latest/meta-data/local-ipv4`
    local API_TOKEN=`grep "Your API token for Server communication" /tmp/installer.out | cut -d":" -f 2 | xargs`

    rm /tmp/installer.out

    echo "Storing API token"
    aws ssm put-parameter --region=$REGION --name="$API_TOKEN_NAME" --value="$API_TOKEN" --type=String --overwrite
    echo "Storing seed IP address"
    aws ssm put-parameter --region=$REGION --name="$SEED_IP_NAME" --value="$SEED_IP" --type=String --overwrite

    echo "Done installing seed node"

    return 0
}

function addNode() {
    local SEED_IP=$1
    local API_TOKEN=$2

    echo "Add node"
    cd /tmp
    /bin/sh dynatrace-managed.sh --install-silent --seed-ip "$SEED_IP" --seed-auth "$API_TOKEN"
    return $?
}


if [[ "$API_TOKEN" == "null" ]]
then
    installSeed
else
    addNode "$SEED_IP" "$API_TOKEN"
fi

exit $?


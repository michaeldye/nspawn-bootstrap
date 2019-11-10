#!/bin/bash -e

BASEDIR=$(dirname $0)

DOMAIN='demo-cheeseforce'

GENDIR=$BASEDIR/generated

# how to rem
if [[ $(ls $GENDIR) ]]; then
  (>&2 echo "[ERROR] $GENDIR exists, please remove it before continuing. You might use these instructions:")
  cat <<EOF
    1. Given <domain>, execute: $(realpath $GENDIR)/<domain>-ca-rem.bash
    2. Execute: rm $(realpath $GENDIR)/*
EOF
  exit 1
else
  mkdir -p $GENDIR
fi

echo "**** Creating demo SSH keypair for root ****"
RKEY=$GENDIR/root-$DOMAIN-rsa
ssh-keygen -f $RKEY -C "key for root in $DOMAIN" -t rsa -b 4096 -N ''

echo "**** Creating $GENDIR/askpass with $BASEDIR/bin/generate-askpass ****"
printf 'guarddatcheeze' | $BASEDIR/bin/generate-askpass

echo "**** Creating $DOMAIN CA with $BASEDIR/bin/generate-ca ****"
$BASEDIR/bin/generate-ca $DOMAIN

echo "**** Signing root user's key with $DOMAIN CA using $BASEDIR/bin/sign-user ****"
$BASEDIR/bin/sign-user $DOMAIN root "$RKEY"

FHOSTS="gouda feta manchego"
echo "**** Generating and signing SSH host keys for hosts: $FHOSTS with $DOMAIN CA using $BASEDIR/bin/sign-user ****"
for hh in $FHOSTS; do
  $BASEDIR/bin/generate-and-sign-host $DOMAIN $hh
done

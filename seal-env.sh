#!/bin/bash

NAMESPACE=$1
SECRET_NAME=$2
CERT_PATH=$3

ENV_FILE=".env"
WHITELIST="secrets.whitelist"

if [ ! -f "$ENV_FILE" ]; then echo ".env not found"; exit 1; fi
if [ ! -f "$WHITELIST" ]; then echo "secrets.whitelist not found"; exit 1; fi

grep -v '^#' .env | grep -v '^$' > all.env

> secret.env
> config.env

while IFS='=' read -r key value; do
  if grep -qx "$key" $WHITELIST; then
    echo "$key=$value" >> secret.env
  else
    echo "$key=$value" >> config.env
  fi
done < all.env

kubectl create configmap app-config \
  --from-env-file=config.env \
  -n $NAMESPACE \
  --dry-run=client -o yaml > configmap.yaml

kubectl create secret generic $SECRET_NAME \
  --from-env-file=secret.env \
  -n $NAMESPACE \
  --dry-run=client -o yaml > secret.yaml

kubeseal --cert $CERT_PATH --namespace $NAMESPACE --format yaml < secret.yaml > sealed-secret.yaml

rm -f all.env secret.env secret.yaml

if ! grep -q "sealed-secret.yaml" kustomization.yaml; then
cat <<EOF >> kustomization.yaml

resources:
  - configmap.yaml
  - sealed-secret.yaml
EOF
fi

echo "Done. Generated configmap.yaml and sealed-secret.yaml"

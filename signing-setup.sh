#!/bin/bash
# One-time: creates a private, self-signed code-signing certificate ("Lotus Local Signing") in your
# login keychain. build.sh signs Lotus with it, so macOS keeps Lotus's permissions across rebuilds.
# Remove it any time in Keychain Access.
set -euo pipefail
NAME="Lotus Local Signing"
for existing in "$NAME" "Ember Local Signing"; do  # Ember = this app's earlier name; keep its permissions
  if security find-certificate -c "$existing" >/dev/null 2>&1; then echo "Already set up ($existing)."; exit 0; fi
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/cert.cnf" \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
PASS="$(openssl rand -hex 16)"  # only protects the temporary .p12 file below
openssl pkcs12 -export -legacy -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" \
  -out "$TMP/ember.p12" -passout "pass:$PASS" 2>/dev/null \
  || openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" -out "$TMP/ember.p12" -passout "pass:$PASS"
security import "$TMP/ember.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P "$PASS" -T /usr/bin/codesign
echo "Created \"$NAME\". Rebuild Lotus with ./build.sh --install"

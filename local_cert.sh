#!/bin/bash

# Create a local Certificate Authority for trusted local certificates
# This gives you the benefits of trusted certs without internet dependency

CA_DIR="$HOME/.local-ca"
CA_KEY="$CA_DIR/cert.key"
CA_CERT="$CA_DIR/cert.crt"
DOMAIN="${1:-localhost}"

# Create CA directory
mkdir -p "$CA_DIR"

# Step 1: Create Certificate Authority (one time only)
if [ ! -f "$CA_KEY" ]; then
    echo "=== Creating Local Certificate Authority ==="

    # Generate CA private key
    openssl genrsa -out "$CA_KEY" 4096

    # Generate CA certificate
    openssl req -x509 -new -nodes \
        -key "$CA_KEY" \
        -sha256 -days 3650 \
        -out "$CA_CERT" \
        -subj "/C=US/ST=State/L=City/O=Local CA/CN=Local Development CA"

    echo "CA created at: $CA_DIR"
    echo
    echo "To trust this CA on your system:"
    echo "  Ubuntu/Debian:"
    echo "    sudo cp $CA_CERT /usr/local/share/ca-certificates/"
    echo "    sudo update-ca-certificates"
    echo
    echo "  macOS:"
    echo "    sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain $CA_CERT"
    echo
    echo "  Windows (PowerShell as Admin):"
    echo "    Import-Certificate -FilePath $CA_CERT -CertStoreLocation Cert:\LocalMachine\Root"
    echo
fi

# Step 2: Generate server certificate signed by our CA
echo "=== Generating Server Certificate for $DOMAIN ==="

# Create key
openssl genrsa -out "$DOMAIN.key" 2048

# Create certificate signing request
cat > "$DOMAIN.conf" << EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C = US
ST = State
L = City
O = Local
CN = $DOMAIN

[v3_req]
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = $DOMAIN
DNS.2 = *.$DOMAIN
IP.1 = 127.0.0.1
IP.2 = ::1
EOF

# Generate CSR
openssl req -new -key "$DOMAIN.key" -out "$DOMAIN.csr" -config "$DOMAIN.conf"

# Sign with our CA
openssl x509 -req \
    -in "$DOMAIN.csr" \
    -CA "$CA_CERT" \
    -CAkey "$CA_KEY" \
    -CAcreateserial \
    -out "$DOMAIN.crt" \
    -days 365 \
    -sha256 \
    -extfile "$DOMAIN.conf" \
    -extensions v3_req

# Cleanup
rm "$DOMAIN.csr" "$DOMAIN.conf"

echo
echo "=== Certificate Generated ==="
echo "  Key:  $DOMAIN.key"
echo "  Cert: $DOMAIN.crt"
echo
echo "This certificate is signed by your local CA and will be trusted"
echo "by your system once you install the CA certificate (see above)."
echo
echo "To use with most servers:"
echo "  python server.py --tls-keyfile $DOMAIN.key --tls-certfile $DOMAIN.crt"

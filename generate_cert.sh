#!/bin/bash

# SSL Certificate Generator
# Generates self-signed certificates with CLI options

# Default values
HOSTNAME="localhost"
DAYS=365
KEY_FILE="cert.key"
CERT_FILE="cert.crt"
KEY_SIZE=2048
COUNTRY="IS"
STATE="State"
CITY="City"
ORG="Local"

# Help function
show_help() {
    cat << EOF
SSL Certificate Generator

Usage: $0 [OPTIONS]

OPTIONS:
    -h, --hostname      Hostname for the certificate (default: localhost)
    -d, --days         Days until expiration (default: 365)
    -k, --key          Private key filename (default: cert.key)
    -c, --cert         Certificate filename (default: cert.crt)
    -s, --size         Key size in bits (default: 2048)
    --country          Country code (default: IS)
    --state            State/Province (default: State)
    --city             City/Locality (default: City)
    --org              Organization (default: Local)
    --san              Additional Subject Alternative Names (can be used multiple times)
    --help             Show this help message

EXAMPLES:
    # Basic usage with defaults
    $0

    # Custom hostname and additional SANs
    $0 -h myserver.local --san "*.myserver.local" --san "192.168.1.100"

    # Custom output files and 2-year validity
    $0 -k server.key -c server.crt -d 730

EOF
}

# Parse arguments
SANS=()
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--hostname)
            HOSTNAME="$2"
            shift 2
            ;;
        -d|--days)
            DAYS="$2"
            shift 2
            ;;
        -k|--key)
            KEY_FILE="$2"
            shift 2
            ;;
        -c|--cert)
            CERT_FILE="$2"
            shift 2
            ;;
        -s|--size)
            KEY_SIZE="$2"
            shift 2
            ;;
        --country)
            COUNTRY="$2"
            shift 2
            ;;
        --state)
            STATE="$2"
            shift 2
            ;;
        --city)
            CITY="$2"
            shift 2
            ;;
        --org)
            ORG="$2"
            shift 2
            ;;
        --san)
            SANS+=("$2")
            shift 2
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Build Subject Alternative Names
SAN_STRING="DNS:${HOSTNAME}"
for san in "${SANS[@]}"; do
    if [[ "$san" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        SAN_STRING="${SAN_STRING},IP:${san}"
    else
        SAN_STRING="${SAN_STRING},DNS:${san}"
    fi
done

# Create config file
CONFIG_FILE=$(mktemp)
cat > "$CONFIG_FILE" << EOF
[req]
default_bits = ${KEY_SIZE}
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = v3_req

[dn]
C = ${COUNTRY}
ST = ${STATE}
L = ${CITY}
O = ${ORG}
CN = ${HOSTNAME}

[v3_req]
subjectAltName = ${SAN_STRING}
EOF

echo "Generating certificate..."
echo "  Hostname: ${HOSTNAME}"
echo "  Validity: ${DAYS} days"
echo "  Key size: ${KEY_SIZE} bits"
echo "  SANs: ${SAN_STRING}"

# Generate certificate
openssl req -x509 \
    -newkey rsa:${KEY_SIZE} \
    -keyout "${KEY_FILE}" \
    -out "${CERT_FILE}" \
    -days ${DAYS} \
    -nodes \
    -config "${CONFIG_FILE}" \
    -extensions v3_req

# Clean up
rm -f "${CONFIG_FILE}"

if [ $? -eq 0 ]; then
    echo
    echo "Certificate generated successfully!"
    echo "  Private key: ${KEY_FILE}"
    echo "  Certificate: ${CERT_FILE}"
    echo
    echo "To run server with TLS:"
    echo "  python server.py --tls-keyfile ${KEY_FILE} --tls-certfile ${CERT_FILE}"

    # Show certificate details
    echo
    echo "Certificate details:"
    openssl x509 -in "${CERT_FILE}" -text -noout | grep -E "(Subject:|Not|DNS:|IP:)"
else
    echo "Error generating certificate"
    exit 1
fi

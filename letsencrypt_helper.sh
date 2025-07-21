#!/bin/bash

# Let's Encrypt DNS Challenge Helper
# Helps automate certificate generation without exposing server

DOMAIN=""
EMAIL=""
CERT_DIR="/etc/letsencrypt/live"
SERVER_DIR="$HOME/server"

show_help() {
    cat << EOF
Let's Encrypt DNS Challenge Helper

Usage: $0 [OPTIONS]

OPTIONS:
    -d, --domain       Domain name (required)
    -e, --email        Email for Let's Encrypt notifications (required)
    -o, --output       Output directory for certs (default: ~/server)
    --staging          Use Let's Encrypt staging server (for testing)
    --help             Show this help message

EXAMPLES:
    # Production certificate
    $0 -d server.yourdomain.com -e you@email.com

    # Test with staging server
    $0 -d server.yourdomain.com -e you@email.com --staging

This script will:
1. Request a certificate using DNS-01 challenge
2. Guide you through adding DNS TXT records
3. Copy certificates to your server directory
4. Show you how to configure server

EOF
}

# Parse arguments
STAGING=""
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--domain)
            DOMAIN="$2"
            shift 2
            ;;
        -e|--email)
            EMAIL="$2"
            shift 2
            ;;
        -o|--output)
            SERVER_DIR="$2"
            shift 2
            ;;
        --staging)
            STAGING="--staging"
            shift
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

# Validate required arguments
if [ -z "$DOMAIN" ] || [ -z "$EMAIL" ]; then
    echo "Error: Domain and email are required"
    show_help
    exit 1
fi

# Check for certbot
if ! command -v certbot &> /dev/null; then
    echo "Error: certbot not found. Install with:"
    echo "  sudo apt install certbot  # Debian/Ubuntu"
    echo "  sudo yum install certbot  # RHEL/CentOS"
    exit 1
fi

echo "=== Let's Encrypt DNS Challenge for server ==="
echo "Domain: $DOMAIN"
echo "Email: $EMAIL"
echo "Output: $SERVER_DIR"
[ -n "$STAGING" ] && echo "Mode: STAGING (testing)"
echo

# Create output directory
mkdir -p "$SERVER_DIR"

# Run certbot with manual DNS challenge
echo "Starting certificate request..."
echo "You will need to add TXT records to your DNS."
echo

sudo certbot certonly \
    --manual \
    --preferred-challenges dns \
    -d "$DOMAIN" \
    --email "$EMAIL" \
    --agree-tos \
    --no-eff-email \
    $STAGING

if [ $? -eq 0 ]; then
    echo
    echo "Certificate obtained successfully!"

    # Copy certificates to server directory
    CERT_PATH="$CERT_DIR/$DOMAIN"

    if [ -d "$CERT_PATH" ]; then
        echo "Copying certificates to server directory..."

        # Create safe copies (certbot files are symlinks)
        sudo cp -L "$CERT_PATH/privkey.pem" "$SERVER_DIR/cert.key"
        sudo cp -L "$CERT_PATH/fullchain.pem" "$SERVER_DIR/cert.crt"

        # Fix permissions
        sudo chown $USER:$USER "$SERVER_DIR/cert.key" "$SERVER_DIR/cert.crt"
        chmod 600 "$SERVER_DIR/cert.key"
        chmod 644 "$SERVER_DIR/cert.crt"

        echo
        echo "=== Setup Complete ==="
        echo "Certificates copied to: $SERVER_DIR"
        echo
        echo "To run server with HTTPS:"
        echo "  python server.py --tls-keyfile $SERVER_DIR/cert.key --tls-certfile $SERVER_DIR/cert.crt"
        echo
        echo "Certificate expires in 90 days. To renew:"
        echo "  sudo certbot renew"
        echo
        echo "For automatic renewal, add to crontab:"
        echo "  0 0 * * 0 certbot renew --quiet --post-hook 'cp -L $CERT_PATH/privkey.pem $SERVER_DIR/cert.key && cp -L $CERT_PATH/fullchain.pem $SERVER_DIR/cert.crt'"
    else
        echo "Error: Certificate directory not found at $CERT_PATH"
        exit 1
    fi
else
    echo "Certificate generation failed"
    exit 1
fi

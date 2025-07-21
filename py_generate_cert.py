#!/usr/bin/env python3
"""
Local SSL Certificate Generator
Generates self-signed certificates with CLI options
Requires: cryptography (pip install cryptography)
"""

import argparse
import datetime
import ipaddress
import sys
from pathlib import Path
from cryptography import x509
from cryptography.x509.oid import NameOID
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives import serialization


def parse_args():
    """Parse command line arguments"""
    parser = argparse.ArgumentParser(
        description='Generate self-signed SSL certificates for local server',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
EXAMPLES:
    # Basic usage with defaults
    %(prog)s

    # Custom hostname and additional SANs
    %(prog)s -h myserver.local --san "*.myserver.local" --san 192.168.1.100

    # Custom output files and 2-year validity
    %(prog)s -k server.key -c server.crt -d 730
        """
    )

    parser.add_argument('-H', '--hostname', default='localhost',
                        help='Hostname for the certificate (default: localhost)')
    parser.add_argument('-d', '--days', type=int, default=365,
                        help='Days until expiration (default: 365)')
    parser.add_argument('-k', '--key', default='cert.key',
                        help='Private key filename (default: cert.key)')
    parser.add_argument('-c', '--cert', default='cert.crt',
                        help='Certificate filename (default: cert.crt)')
    parser.add_argument('-s', '--size', type=int, default=2048,
                        help='Key size in bits (default: 2048)')
    parser.add_argument('--country', default='US',
                        help='Country code (default: IS)')
    parser.add_argument('--state', default='State',
                        help='State/Province (default: State)')
    parser.add_argument('--city', default='City',
                        help='City/Locality (default: City)')
    parser.add_argument('--org', default='Local',
                        help='Organization (default: Local)')
    parser.add_argument('--san', action='append', dest='sans',
                        help='Additional Subject Alternative Names (can be used multiple times)')
    parser.add_argument('--overwrite', action='store_true',
                        help='Overwrite existing files without asking')
    parser.add_argument('-v', '--verbose', action='store_true',
                        help='Show certificate details after generation')

    return parser.parse_args()


def check_existing_files(key_file, cert_file, overwrite=False):
    """Check if files exist and confirm overwrite"""
    files_exist = []
    if Path(key_file).exists():
        files_exist.append(key_file)
    if Path(cert_file).exists():
        files_exist.append(cert_file)

    if files_exist and not overwrite:
        print(f"Warning: The following files already exist: {', '.join(files_exist)}")
        response = input("Overwrite? (y/N): ").lower()
        if response != 'y':
            print("Aborted.")
            sys.exit(0)


def parse_san(san_value):
    """Parse SAN value and return appropriate x509 object"""
    # Check if it's an IP address
    try:
        ip = ipaddress.ip_address(san_value)
        return x509.IPAddress(ip)
    except ValueError:
        # Not an IP, treat as DNS name
        return x509.DNSName(san_value)


def generate_certificate(args):
    """Generate the certificate based on arguments"""
    print(f"Generating certificate...")
    print(f"  Hostname: {args.hostname}")
    print(f"  Validity: {args.days} days")
    print(f"  Key size: {args.size} bits")

    # Generate private key
    key = rsa.generate_private_key(
        public_exponent=65537,
        key_size=args.size,
    )

    # Certificate subject and issuer
    subject = issuer = x509.Name([
        x509.NameAttribute(NameOID.COUNTRY_NAME, args.country),
        x509.NameAttribute(NameOID.STATE_OR_PROVINCE_NAME, args.state),
        x509.NameAttribute(NameOID.LOCALITY_NAME, args.city),
        x509.NameAttribute(NameOID.ORGANIZATION_NAME, args.org),
        x509.NameAttribute(NameOID.COMMON_NAME, args.hostname),
    ])

    # Build Subject Alternative Names
    san_list = [x509.DNSName(args.hostname)]

    # Add localhost variants if hostname is localhost
    if args.hostname == 'localhost':
        san_list.extend([
            x509.IPAddress(ipaddress.ip_address('127.0.0.1')),
            x509.IPAddress(ipaddress.ip_address('::1'))
        ])

    # Add additional SANs
    if args.sans:
        for san in args.sans:
            san_obj = parse_san(san)
            if san_obj not in san_list:
                san_list.append(san_obj)

    # Display SANs
    san_display = []
    for san in san_list:
        if isinstance(san, x509.DNSName):
            san_display.append(f"DNS:{san.value}")
        elif isinstance(san, x509.IPAddress):
            san_display.append(f"IP:{san.value}")
    print(f"  SANs: {', '.join(san_display)}")

    # Create certificate
    cert_builder = (
        x509.CertificateBuilder()
        .subject_name(subject)
        .issuer_name(issuer)
        .public_key(key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(datetime.datetime.utcnow())
        .not_valid_after(datetime.datetime.utcnow() + datetime.timedelta(days=args.days))
        .add_extension(
            x509.SubjectAlternativeName(san_list),
            critical=False,
        )
    )

    # Add key usage extensions for better compatibility
    cert_builder = cert_builder.add_extension(
        x509.KeyUsage(
            digital_signature=True,
            key_encipherment=True,
            content_commitment=False,
            data_encipherment=False,
            key_agreement=False,
            key_cert_sign=False,
            crl_sign=False,
            encipher_only=False,
            decipher_only=False,
        ),
        critical=True,
    )

    cert = cert_builder.sign(key, hashes.SHA256())

    # Write private key
    with open(args.key, "wb") as f:
        f.write(key.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.TraditionalOpenSSL,
            encryption_algorithm=serialization.NoEncryption()
        ))

    # Write certificate
    with open(args.cert, "wb") as f:
        f.write(cert.public_bytes(serialization.Encoding.PEM))

    print(f"\nCertificate generated successfully!")
    print(f"  Private key: {args.key}")
    print(f"  Certificate: {args.cert}")
    print(f"\nTo run server with TLS:")
    print(f"  python server.py --tls-keyfile {args.key} --tls-certfile {args.cert}")

    if args.verbose:
        print("\nCertificate details:")
        print(f"  Serial: {cert.serial_number}")
        print(f"  Not Before: {cert.not_valid_before}")
        print(f"  Not After: {cert.not_valid_after}")
        print(f"  Subject: {cert.subject.rfc4514_string()}")
        print(f"  Issuer: {cert.issuer.rfc4514_string()}")


def main():
    """Main entry point"""
    args = parse_args()

    # Check for existing files
    check_existing_files(args.key, args.cert, args.overwrite)

    try:
        generate_certificate(args)
    except Exception as e:
        print(f"Error generating certificate: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()

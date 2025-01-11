#!/usr/bin/env python3
#
# Copyright (C) 2024 Hasan CALISIR <hasan.calisir@psauxit.com> - PSAUXIT.COM
# Distributed under the GNU General Public License, version 2.0.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# What is doing this script exactly?
# -Create a DANE TLSA records (SMTP & HTTP) [Automatically for Let's Encrypt]

#####################################################################################
# 3 1 1 TLSA record requires no renewal on certificate renewal (unless key is changed)
#####################################################################################

#####################################################################################
# Let’s Encrypt Settings
#####################################################################################
# Remember to append the below two parameters to your certbot command
# --keep --reuse-key
# When checking your [renewalparams], make sure the following line is present:
# reuse_key = True
#####################################################################################

import argparse
import OpenSSL.crypto
import sys
import os
import re
import binascii
import hashlib

# ANSI color codes
CYAN = '\033[96m'
RED = '\033[91m'
GREEN = '\033[92m'
MAGENTA = '\033[95m'
YELLOW = '\033[93m'
ENDC = '\033[0m'

def format_as_hex(data):
    # Convert binary data to hexadecimal format with the specified format
    hex_data = binascii.hexlify(data)
    return ''.join([hex_data[i:i+2].decode() for i in range(0, len(hex_data), 2)])

def extract_tlsa_info(cert_file):
    # Extract TLSA information from the certificate file
    try:
        # Load certificate from file
        with open(cert_file, 'rb') as f:
            cert_data = f.read()
            cert = OpenSSL.crypto.load_certificate(OpenSSL.crypto.FILETYPE_PEM, cert_data)
        # Extract public key in DER format
        pubkey_der = OpenSSL.crypto.dump_publickey(OpenSSL.crypto.FILETYPE_ASN1, cert.get_pubkey())
        # Compute SHA-256 hash of the public key
        sha256_hash = hashlib.sha256(pubkey_der).digest()
        # Convert hash to hexadecimal format
        pubkey_hash_hex = format_as_hex(sha256_hash)

        cert_usage = 3  # Cert Usage: 3 for CA constraint
        selector = 1    # Selector: 1 for SubjectPublicKeyInfo
        matching_type = 1   # Matching Type: 1 for SHA-256

        return (cert_usage, selector, matching_type, pubkey_hash_hex)
    except OpenSSL.crypto.Error as e:
        print(RED + f"Error: {e}" + ENDC)
        sys.exit(1)

def generate_tlsa_records(cert_file, hostname, ports):
    # Generate TLSA records for the given certificate file, hostname, and ports
    tlsa_records = []
    tlsa_info = extract_tlsa_info(cert_file)
    cert_usage, selector, matching_type, pubkey_hash_hex = tlsa_info
    for port in ports:
        tlsa_record = f'_{port}._tcp.{hostname} IN TLSA {cert_usage} {selector} {matching_type} {pubkey_hash_hex}'
        tlsa_records.append(tlsa_record)
    return tlsa_records

def validate_hostname(hostname, service):
    # Map service numbers to their names
    service_name = {1: 'smtp', 2: 'http'}.get(service)
    if service_name is None:
        print(RED + 'Error: Invalid service type. Please provide either 1 for smtp or 2 for http.' + ENDC)
        sys.exit(1)

    # Validate hostname based on service type (SMTP or HTTP)
    if service_name == 'smtp':
        # Check if the hostname matches the MX hostname style (e.g., mx1.example.com)
        mx_pattern = re.compile(r'^\w*\.\w+\.\w+$')
        if not re.match(mx_pattern, hostname):
            print(YELLOW + 'Warning: Hostname should ideally follow MX hostname style (e.g., mx1.example.com) for SMTP service.' + ENDC)
            response = input('Do you want to continue anyway? (y/n): ')
            if response.lower() != 'y':
                print('Exiting script.')
                sys.exit(0)
    elif service_name == 'http':
        # Check if the hostname is a valid domain name
        if not re.match(r'^[a-zA-Z0-9.-]+$', hostname):
            print(RED + 'Error: Hostname should be a valid domain name for HTTP service.' + ENDC)
            sys.exit(1)

def validate_certificate(cert_file):
    # Validate if the certificate file is in correct PEM format
    try:
        with open(cert_file, 'rb') as f:
            cert_data = f.read()
            cert = OpenSSL.crypto.load_certificate(OpenSSL.crypto.FILETYPE_PEM, cert_data)
    except OpenSSL.crypto.Error:
        print(RED + f"Error: Invalid PEM format for the certificate file '{cert_file}'." + ENDC)
        sys.exit(1)

def get_cert_files_from_path(path):
    # Get hostnames and their corresponding certificate files from the specified path
    if not os.path.exists(path):
        print(RED + f"Error: Path '{path}' does not exist." + ENDC)
        sys.exit(1)

    hostnames_and_certs = {}
    for entry in os.scandir(path):
        if entry.is_dir():
            # Normalize the hostname by removing any appended characters
            hostname = re.sub(r'-\d+$', '', entry.name)
            cert_file = os.path.join(entry.path, 'cert.pem')
            if os.path.exists(cert_file):
                hostnames_and_certs[hostname] = cert_file

    return hostnames_and_certs

def main():
    # Help message with script usage and argument details
    help_message = CYAN + '''
    Script Usage:
    #############
    
    Let's Encrypt Auto Creation
    ---------------------------
    python lets_encrypt_dane_tlsa.py
    ./lets_encrypt_dane_tlsa.py
   
    Manual Creation:
    ----------------
    python lets_encrypt_dane_tlsa.py [certificate_file] [hostname] [service]
    ./lets_encrypt_dane_tlsa.py [certificate_file] [hostname] [service]
    
    Arguments:
    ----------
    1. certificate_file: Path to the certificate file (cert.pem)
    2. hostname: Hostname for the TLSA record. (example.com or MX mail.example.com)
    3. service: Service type (1 for SMTP, 2 for HTTP). [HTTP 80, 443 | SMTP 25, 465, 587] TCP
    ''' + ENDC

    # Parse command line arguments
    parser = argparse.ArgumentParser(description='Generate DANE TLSA records.')
    parser.add_argument('certificate_file', nargs='?', type=str, help='Path to the certificate file')
    parser.add_argument('hostname', nargs='?', type=str, help='Hostname for the TLSA record')
    parser.add_argument('service', nargs='?', type=int, choices=[1, 2], help='Service type (1 for smtp, 2 for http)')
    args = parser.parse_args()

    # Auto TLSA record generation for Let's Encrypt
    lets_encrypt_path_exists = os.path.exists('/etc/letsencrypt/live/')
    if not all((args.certificate_file, args.hostname, args.service)):
        if lets_encrypt_path_exists:
            # Existing code for listing available certificates and prompting user
            print(GREEN + "Available hostnames and their corresponding certificate files:" + ENDC)
            hostnames_and_certs = get_cert_files_from_path('/etc/letsencrypt/live/')
            for idx, (hostname, cert_file) in enumerate(hostnames_and_certs.items(), start=1):
                print(f"{idx}. {hostname} - {cert_file}")

            # Prompt user to select a hostname
            while True:
                try:
                    selection = int(input(CYAN + "Enter the number corresponding to the desired hostname: " + ENDC))
                    if selection < 1 or selection > len(hostnames_and_certs):
                        print(RED + "Invalid selection. Please enter a valid number." + ENDC)
                        continue
                    break
                except ValueError:
                    print(RED + "Invalid input. Please enter a number." + ENDC)

            # Set the selected hostname and certificate file
            args.certificate_file = list(hostnames_and_certs.values())[selection - 1]
            args.hostname = list(hostnames_and_certs.keys())[selection - 1]

            # Prompt user to select a service
            while True:
                try:
                    selection = int(input(CYAN + "Select the service type (1 for smtp, 2 for http): " + ENDC))
                    if selection not in [1, 2]:
                        print(RED + "Invalid selection. Please enter either 1 or 2." + ENDC)
                        continue
                    break
                except ValueError:
                    print(RED + "Invalid input. Please enter either 1 or 2." + ENDC)

            args.service = selection
        else:
            print(RED + "Error: Let's Encrypt not installed or not using common certificate folder paths." + ENDC)
            print(RED + "Please manually supply the hostname, service, and certificate file arguments." + ENDC)
            print(help_message)
            sys.exit(0)

    # Validate hostname based on service type
    validate_hostname(args.hostname, args.service)

    # Check if certificate file exists
    if not os.path.exists(args.certificate_file):
        print(RED + f"Error: Certificate file '{args.certificate_file}' not found.\n" + ENDC)
        print(help_message)
        sys.exit(1)

    # Validate certificate file format
    validate_certificate(args.certificate_file)

    # Determine ports based on service type
    # For SMTP, set smtp, smtps, submission ports (25, 465, 587)
    # For HTTP, set http, https ports (80, 443)
    if args.service == 1:
        ports = [25, 465, 587]  # SMTP
    elif args.service == 2:
        ports = [80, 443]  # HTTP

    # Generate TLSA records
    tlsa_records = generate_tlsa_records(args.certificate_file, args.hostname, ports)
    print(GREEN + "TLSA Records:" + ENDC)
    for record in tlsa_records:
        print(MAGENTA + record + ENDC)

if __name__ == '__main__':
    main()

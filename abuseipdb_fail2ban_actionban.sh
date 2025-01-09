#!/usr/bin/env bash
#
# Description:
#   This script serves as a Fail2Ban `actionban` to report offending IP addresses to AbuseIPDB.
#   Mainly whenever Fail2Ban restarts, it calls the actionban function for each IP stored in the database file.
#   If you restart your server often this script prevents duplicate reporting to AbuseIPDB by maintaining a local list of already reported IPs.
#   Before reporting, it checks both the local list and AbuseIPDB to ensure the IP hasn't
#   been reported previously, thereby avoiding redundant entries and potential API rate limiting.
#
# Integration with Fail2Ban:
#   - Place this script in the Fail2Ban `action.d` directory named 'abuseipdb_fail2ban_actionban.sh'
#   - Configure Fail2Ban to use this script as the `actionban` for relevant jails.
#   - First edit 'abuseipdb.conf' in '/etc/fail2ban/action.d/abuseipdb.conf' and add following rule,
#   - actionban = /etc/fail2ban/action.d/abuseipdb_fail2ban_actionban.sh \
#         "<abuseipdb_apikey>" "<matches>" "<ip>" "<abuseipdb_category>" "<bantime>"
#   - Adjust your jails accordingly. Check the below jail example to also reporting with custom comment via  'tp_comment'
#
#   Example jail in 'jail.local':
#     [nginx-botsearch]
#     enabled    = true
#     logpath    = /var/log/nginx/*.log
#     port       = http,https
#     backend    = polling
#     tp_comment = Fail2Ban - NGINX bad requests 400-401-403-404-444, high level vulnerability scanning, commonly xmlrpc_attack, wp-login brute force, excessive crawling/scraping
#     maxretry   = 3
#     findtime   = 1d
#     bantime    = 7200
#     action     = %(action_mwl)s
#                  %(action_abuseipdb)s[matches="%(tp_comment)s", abuseipdb_apikey="YOUR_API_KEY", abuseipdb_category="21,15", bantime="%(bantime)s"]
#
#   Start from scratch practise if you lost in space:
#     - Stop Fail2ban
#     - Clear all existing firewall reject rules from iptables
#     - Delete Fail2ban SQLite database and truncate fail2ban.log
#     - Force logrotate
#     - Follow above implementation steps and adjust all your jails accordingly
#     - Try to recover corrupted REPORTED_IP_LIST_FILE via dos2unix, "sed 's/\x0//g'" or "grep -P '\x00'" and remove duplicates via "awk '!seen[$1]++'" keep you local file always.
#     - Start Fail2ban
#
# Usage:
#   This script is intended to be called by Fail2Ban automatically (actionban) and accepts the following arguments:
#     1. <APIKEY>     - Your AbuseIPDB API key.
#     2. <COMMENT>    - A comment describing the reason for reporting the IP.
#     3. <IP>         - The IP address to report.
#     4. <CATEGORIES> - Comma-separated list of abuse categories as per AbuseIPDB's API.
#     5. <BANTIME>    - Duration for which the IP should be banned (e.g., 600 for 10 minutes).
#
#   Manual Usage:
#     For testing purpose before production;
#       /etc/fail2ban/action.d/abuseipdb_fail2ban_actionban.sh "your_api_key" "Failed SSH login attempts" "192.0.2.1" "18" "600"
#
# Arguments:
#   APIKEY      - Required.
#   COMMENT     - Required.
#   IP          - Required.
#   CATEGORIES  - Required.
#   BANTIME     - Required.
#
# Configurations (Need to set):
#   - REPORTED_IP_LIST_FILE: Path to the local file storing reported IPs and their ban times.
#   - LOG_FILE: Path to the log file where actions and outcomes are recorded.
#
# Dependencies:
#   - curl: For making API requests to AbuseIPDB.
#   - jq: For parsing JSON responses.
#   - grep: For searching within the local reported IP list.
#
# General Considerations:
#   - Since the script is triggered on every Fail2Ban ban action, it must be optimized for performance and designed to be as lightweight as possible so,
#   - not try to make it complex via adding redundant if statements for various checks like file existence, IP validation or API related validations,
#   - keep the logic straightforward and focused on the critical actions the script must perform.
#   - The script does not interact with or rely on Fail2Ban’s SQLite database, as the Fail2ban database setup can vary across different environments.
#   - The script performs two API calls to AbuseIPDB in every ban action in order to determine whether the banned IP should be reported,
#   - first call /v2/check and second to /v2/report endpoint. So your daily limits not affected check/report endpoints has seperate daily limits
#   - Ensure dependencies installed before you go production as mentioned before script is lightweight and not checking any dependency.
#   - When multiple instances of the script try to write to the REPORTED_IP_LIST_FILE concurrently we need to prevent data corruption. flock used for that reason.
#   - Never delete, truncate or try to sync REPORTED_IP_LIST_FILE with Fail2ban SQLite. Even you reset fail2ban SQLite, continue to keep REPORTED_IP_LIST_FILE same, we always rely on our local list.
#   - When you go production keep watching '/var/log/abuseipdb-report.log' for any abnormal fails.
#
# Return Codes:
#   0 - IP is reported
#   1 - IP is not reported
#
# Exit Codes:
#   1 - API-related failure
#
# Author:
#   Hasan ÇALIŞIR - PSAUXIT
#   hasan.calisir@psauxit.com
#   https://www.psauxit.com/


# Arguments
APIKEY="$1"
COMMENT="$2"
IP="$3"
CATEGORIES="$4"
BANTIME="$5"

# Configuration
REPORTED_IP_LIST_FILE="/etc/fail2ban/action.d/abuseipdb-reported-ip-list"
LOG_FILE="/var/log/abuseipdb-report.log"

# Set default to report IP to abuseipdb
# Set default to add IP to local ban list
is_found_local=0
shouldBanIP=1

# Function to log messages
log_message() {
    local message="$1"
    echo "$(date +"%Y-%m-%d %H:%M:%S") - ${message}" >> "${LOG_FILE}"
}

# Function to perform API call to check IP
check_ip_in_abuseipdb() {
    local response
    response=$(curl --fail -s -G https://api.abuseipdb.com/api/v2/check \
        --data-urlencode "ipAddress=${IP}" \
        -H "Key: ${APIKEY}" \
        -H "Accept: application/json" 2>&1)

    # API call fail
    if [[ $? -ne 0 ]]; then
        log_message "Aborting due to API failure when checking IP. Response: ${response}"
        exit 1
    fi

    # API response is empty or malformed
    if [[ -z "$response" ]] || ! echo "$response" | jq . >/dev/null 2>&1; then
        log_message "API response was empty or malformed when checking IP. Response: ${response}"
        exit 1
    fi

    # Extract totalReports
    total_reports=$(echo "$response" | jq '.data.totalReports')

    # Check the IP listed on AbuseIPDB
    if [[ "${total_reports}" -gt 0 ]]; then
        return 0 # IP is reported
    else
        return 1 # IP is not reported
    fi
}

# Function to perform API call to report IP
report_ip_to_abuseipdb() {
    local response
    response=$(curl --fail -s 'https://api.abuseipdb.com/api/v2/report' \
        -H 'Accept: application/json' \
        -H "Key: ${APIKEY}" \
        --data-urlencode "comment=${COMMENT}" \
        --data-urlencode "ip=${IP}" \
        --data "categories=${CATEGORIES}" 2>&1)

    # API call fail
    if [[ $? -ne 0 ]]; then
        log_message "Aborting due to API failure when reporting IP. Response: ${response}"
        exit 1
    else
        log_message "Reported IP ${IP} to AbuseIPDB."
    fi
}

# Ensure the reported IP list file exists, if not, create it
if [[ ! -f "${REPORTED_IP_LIST_FILE}" ]]; then
    touch "${REPORTED_IP_LIST_FILE}"
fi

# Check the IP existence locally and remotely
# Here we always trust the local list and don't interact with fail2ban SQLite
if grep -q -E "^IP=${IP} L=[0-9\-]+" "${REPORTED_IP_LIST_FILE}"; then
    # Found locally, we have already reported
    shouldBanIP=0

    # Check even found locally still listed on AbuseIPDB
    if ! check_ip_in_abuseipdb; then
        # Not listed on AbuseIPDB, we need to report IP but not include to local list
        is_found_local=1
        shouldBanIP=1
    fi

    if [[ "${shouldBanIP}" -eq 0 ]]; then
        log_message "IP ${IP} has already been reported locally and remains on AbuseIPDB. No duplicate report made."
    fi
fi

# Report to AbuseIpdb
if [[ "${shouldBanIP}" -eq 1 ]]; then
    # Add the new ban entry to local list
    if [[ "${is_found_local}" -eq 0 ]]; then
        {
            # Use flock to prevent race conditions when writing to the file
            flock -x 200
            echo "IP=${IP} L=${BANTIME}" >> "${REPORTED_IP_LIST_FILE}"
        } 200>"${REPORTED_IP_LIST_FILE}.lock"
    fi

    # Call the API to report the IP
    report_ip_to_abuseipdb
fi

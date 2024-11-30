#!/usr/bin/env bash
#
# Copyright (C) 2023 Hasan ÇALIŞIR <hasan.calisir@psauxit.com>
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
# ---------------------------------------------------------------------
# Written by  : (hsntgm) Hasan ÇALIŞIR - hasan.calisir@psauxit.com
#                                        https://www.psauxit.com/
# --------------------------------------------------------------------
#
# The aim of this script is spying OpenVPN client's HTTP traffic.
# - Visit https://www.psauxit.com/secured-openvpn-clients-dnscrypt/
# - blog post for detailed instructions.

# ADJUST USER DEFINED SETTINGS
####################################################
# set your ccd path that holds each client static IP
ccd="/etc/openvpn/server/ccd"

# set your bind queries log path
queries="/var/log/named/queries.log"

# set your openvpn clients IP Pool
# max 255.255.0.0
pool="10.8.0.0"
####################################################

# set color
red=$(tput setaf 1)
cyan=$(tput setaf 6)
magenta=$(tput setaf 5)
yellow=$(tput setaf 3)
TPUT_BOLD=$(tput bold)
TPUT_BGRED=$(tput setab 1)
TPUT_WHITE=$(tput setaf 7)
reset=$(tput sgr 0)
printf -v m_tab '%*s' 2 ''

# fatal
fatal () {
  printf >&2 "\n${m_tab}%s ABORTED %s %s \n\n" "${TPUT_BGRED}${TPUT_WHITE}${TPUT_BOLD}" "${reset}" "${@}"
  exit 1
}

# discover script path
this_script_full_path="${BASH_SOURCE[0]}"
if command -v dirname >/dev/null 2>&1 && command -v readlink >/dev/null 2>&1 && command -v basename >/dev/null 2>&1; then
  # Symlinks
  while [[ -h "${this_script_full_path}" ]]; do
    this_script_path="$( cd -P "$( dirname "${this_script_full_path}" )" >/dev/null 2>&1 && pwd )"
    this_script_full_path="$(readlink "${this_script_full_path}")"
    # Resolve
    if [[ "${this_script_full_path}" != /* ]] ; then
      this_script_full_path="${this_script_path}/${this_script_full_path}"
    fi
  done
  this_script_path="$( cd -P "$( dirname "${this_script_full_path}" )" >/dev/null 2>&1 && pwd )"
  this_script_name="$(basename "${this_script_full_path}")"
else
  fatal "Cannot find script path! Check you have dirname,readlink,basename tools"
fi

# populate array
# key-value --> client name-static ip
clients_name_ip () {
  # declare global associative array
  declare -gA clients

  printf "\n"
  for each in "${ccd}"/*; do
    if [[ ! -f ${each} ]]; then
      printf "$m_tab\e[33mWarn:\e[0m %s is not a file\n" "${each}" >&2
      continue
    fi

    client=${each##*/}

    if ! client_ip=$(awk -v pool="${pool%.*}" '
      BEGIN { exit_code = 1 }
      /^ifconfig-push\s+([0-9]{1,3}\.){3}[0-9]{1,3}/ {
        split($2, a, ".");
        if (a[1]<256 && a[2]<256 && a[3]<256 && a[4]<256 && $2 ~ pool) {
          print $2;
          exit_code = 0
        }
      }
      END { exit exit_code }' "${each}"); then
      printf "$m_tab\e[33mWarn:\e[0m failed to extract IP address from %s\n" "${each}" >&2
      continue
    fi
    clients[${client}]="${client_ip}"
  done
}

# list OpenVPN clients
list_clients () {
  printf '\n%s%s# OpenVPN Clients\n' "$m_tab" "$cyan"
  printf '%s --------------------------------%s\n' "$m_tab" "$reset"
  while read -r line
  do
    printf '%s%s%s\n' "$m_tab" "$magenta" "$(printf '  %s' "$line")$reset"
  done < <(find "$ccd" -type f -exec basename {} \; | paste - - -)
  printf '%s%s --------------------------------%s\n\n' "$cyan" "$m_tab" "$reset"
}

# check openvpn client existence
check_client () {
  if [[ -z "${clients["$1"]}" ]]; then
    fatal "Cannot find OpenVPN client --> $1! Use --list to show OpenVPN Clients."
  fi
}

main () {
  local my_file
  my_file=$(mktemp)

  # search openvpn client static IP (logrotated ones included), parse DNS queries, sort
  { find "${queries%/*}/" -name "*${queries##*/}*" -type f -print0 |
    xargs -0 zgrep -i -h -w "${ip}" |
    awk 'match($0, /query:[[:space:]]*([^[:space:]]+)/, a) {print $1" "$2" "a[1]}' |
    sort -s -k1.8n -k1.4M -k1.1n
  } 2>/dev/null > "${my_file}"

  # take immediate snapshot of pipestatus
  status=( "${PIPESTATUS[@]}" )

  # remove the sort command exit status from the PIPESTATUS array
  # that not cause any parse error
  if [ ${#status[@]} -ge 4 ]; then unset 'status[3]'; fi

  # check any piped commands fails
  if [[ "${status[*]}" =~ [^0\ ] ]]; then
    for i in "${!status[@]}"; do
      if [[ "${status[i]}" -ne 0 ]]; then
        case $i in
          0) { printf "%s\n" "${red}${m_tab}find command failed with exit status ${status[i]}, check the path is correct --> ${queries}${reset}"; return 1; } ;;
             #  error code 123 for zgrep means no http traffic at all for this client, so this is not a parse error and excluded
          1) [[ "${status[i]}" -eq 127 ]] && { printf "%s\n" "${red}${m_tab}zgrep command not found. Install zgrep and try again.${reset}"; return 1; } ;;
          2) { printf "%s\n" "${red}${m_tab}awk command failed with exit status ${status[i]}, please open a bug${reset}"; return 1; } ;;
        esac
      fi
    done
  fi

  # if parse error not found also check 'no HTTP traffic' for the client
  # save per openvpn client http traffic to file
  if ! [[ -s "${my_file}" ]]; then
    echo -ne "${cyan}${m_tab}Openvpn Client --> ${magenta}${client}${reset} "
    echo -e "${cyan}--> ${yellow}No HTTP traffic found${reset}"
  elif ! rsync -r --delete --remove-source-files "${my_file}" \
    "${this_script_path}/http_traffic_${client}" >/dev/null 2>&1; then
    trap 'rm -f "${my_file}"' ERR
    echo -ne "${red}${m_tab}Error: Failed to save HTTP traffic for "
    echo -e "client ${client} to file ${this_script_path}/http_traffic_${client}${reset}"
  else
    echo -ne "${cyan}${m_tab}Openvpn Client --> ${magenta}${client}${reset} "
    echo -e "${cyan}--> HTTP traffic saved in --> ${magenta}${this_script_path}/http_traffic_${client}${reset}"
  fi
  [[ $1 == single ]] && printf "\n"
}

# parse http traffic for all openvpn clients, this will be run in parallel for every client
# this can cause high cpu usage if you have many openvpn clients and heavy internet traffic
all_clients () {
  clients_name_ip
  list_clients
  num_cores=$(nproc)

  # main parsing function
  parse_traffic () {
    local client ip
    client="${1}"
    ip="${clients[$client]}"
    main
  }

  # Loop through the clients and parse their HTTP traffic in parallel
  # Limit the number of parallel processes to the number of CPU core
  for client in "${!clients[@]}"
  do
    parse_traffic "${client}" &
    if (( $(jobs -r -p | wc -l) >= num_cores )); then
      wait -n
    fi
  done

  # wait all parallel jobs complete
  wait
  printf "\n"
}

# parse http traffic for specific openvpn client
single_client () {
  local client ip
  clients_name_ip
  check_client "${1}"
  client="${1}"
  ip="${clients[${1}]}"
  main single
}

# live watch http traffic for specific OpenVPN client
watch_client () {
  clients_name_ip
  check_client "${1}"
    tail -f "${queries}" \
  | grep --line-buffered -w "${clients[${1}]}" \
  | awk -v space="${m_tab}" '{for(i=1; i<=NF; i++) if($i~/query:/ && $(i+1) !~ /addr\.arpa/) printf "%s\033[35m%s\033[39m \033[36m%s\033[39m\n", space, $1, $(i+1)}'
}

# help
help () {
  printf "\n%s\n" "${m_tab}${cyan}# Script Help"
  printf "%s\n" "${m_tab}# --------------------------------------------------------------------------------------------------------------------"
  printf "%s\n" "${m_tab}#${m_tab}  -a | --all-clients   get all OpenVPN clients http traffic to separate file e.g ./spy_vpn.sh --all-clients"
  printf "%s\n" "${m_tab}#${m_tab}  -c | --client        get specific OpenVPN client http traffic to file e.g ./spy_vpn.sh --client JohnDoe"
  printf "%s\n" "${m_tab}#${m_tab}  -l | --list          list OpenVPN clients e.g ./spy_vpn.sh --list"
  printf "%s\n" "${m_tab}#${m_tab}  -w | --watch         live watch specific OpenVPN client http traffic ./spy_vpn.sh --watch JohnDoe"
  printf "%s\n" "${m_tab}#${m_tab}  -h | --help          help screen"
  printf "%s\n\n" "${m_tab}# ----------------------------------------------------------------------------------------------------------------------${reset}"
}

# invalid script option
inv_opt () {
  printf "\n%s\\n" "${red}${m_tab}Invalid option${reset}"
  printf "%s\\n\n" "${cyan}${m_tab}Try './${this_script_name} --help' for more information.${reset}"
  exit 1
}

# script management
man () {
  if [[ "$#" -eq 0 || "$#" -gt 2 ]]; then
    printf "\n%s\\n" "${red}${m_tab}Argument required or too many argument${reset}"
    printf "%s\\n\n" "${cyan}${m_tab}Try './${this_script_name} --help' for more information.${reset}"
    exit 1
  fi

  # set script arguments
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      -a  | --all-clients ) all_clients        ;;
      -c  | --client      ) single_client "$2" ;;
      -w  | --watch       ) watch_client  "$2" ;;
      -l  | --list        ) list_clients       ;;
      -h  | --help        ) help               ;;
      *                   ) inv_opt            ;;
    esac
    break
  done
}

# Call man
man "${@}"

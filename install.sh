#!/bin/bash

# Copyright (C) 2021 Hasan CALISIR <hasan.calisir@psauxit.com>
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

# Wrapper script for Nginx FastCGI Cache Purge & Preload Plugin for Wordpress

# URL to download the script
URL="https://psaux-it.github.io/fastcgi_ops_root.sh"
MAIN_SCRIPT="fastcgi_ops_root.sh"

# Function to check for curl and wget, and download the main script using the available tool
download_and_execute_fastcgi_ops_root() {
    if command -v curl > /dev/null 2>&1; then
        curl -Ss "${URL}" -o "${MAIN_SCRIPT}" && chmod +x "${MAIN_SCRIPT}" && bash "${MAIN_SCRIPT}"
    elif command -v wget > /dev/null 2>&1; then
        wget -q "${URL}" -O "${MAIN_SCRIPT}" && chmod +x "${MAIN_SCRIPT}" && bash "${MAIN_SCRIPT}"
    else
        echo -e "\e[91mError:\e[0m \e[93mcurl\e[0m \e[96mor \e[93mwget\e[0m \e[96mis not installed or not found in PATH.\e[0m"
        exit 1
    fi
}

# Call the function to download and execute the main script
download_and_execute_fastcgi_ops_root

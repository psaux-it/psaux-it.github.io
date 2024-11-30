#!/bin/bash
#
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
#
# What is doing this script exactly?
# Proxy finder

# Clean start
rm -rf "$HOME/proxy/*"

# Get proxy lists
curl -sSf "https://raw.githubusercontent.com/clarketm/proxy-list/master/proxy-list.txt"                   > "$HOME/proxy/proxy-list-clark.txt"
curl -sSf "https://raw.githubusercontent.com/TheSpeedX/SOCKS-List/master/http.txt"                        > "$HOME/proxy/proxy-list-speedx.txt"
curl -sSf "https://raw.githubusercontent.com/jetkai/proxy-list/main/online-proxies/txt/proxies-https.txt" > "$HOME/proxy/proxy-list-jetkai_https.txt"
curl -sSf "https://raw.githubusercontent.com/jetkai/proxy-list/main/online-proxies/txt/proxies-http.txt"  > "$HOME/proxy/proxy-list-jetkai_http.txt"
curl -sSf "https://raw.githubusercontent.com/sunny9577/proxy-scraper/master/proxies.txt"                  > "$HOME/proxy/proxy-list-sunny9577.txt"
curl -sSf "https://raw.githubusercontent.com/saschazesiger/Free-Proxies/master/proxies/http.txt"          > "$HOME/proxy/proxy-list-saschazesiger.txt"
curl -sSf "https://raw.githubusercontent.com/saschazesiger/Free-Proxies/master/proxies/premium.txt"       > "$HOME/proxy/proxy-list-saschazesiger-premium.txt"

# Declare European Union (EU) Member States 2 letter codes
europa=("DE" "NL" "AT" "BE" "BG"
        "HR" "CY" "CZ" "DK" "EE"
        "FI" "FR" "GR" "HU" "IE"
        "IT" "LV" "LT" "LU" "MT"
        "NL" "PL" "PT" "RO" "SK"
        "SI" "ES" "SE" "NL" "EU")

# Get HTTP/HTTPS HIGH ANONMY EUROPA proxies from CLARK
for country in "${europa[@]}"
do
  while read -r proxye
  do
    if echo "${proxye}" | grep "${country}" | grep -q "A-S"; then
       echo "${proxye}" | awk '{print $1}' >> "$HOME/proxy/proxy-list-clark-europa.txt"
    fi
    if echo "${proxye}" | grep "${country}" | grep -q "H-S"; then
       echo "${proxye}" | awk '{print $1}' >> "$HOME/proxy/proxy-list-clark-europa.txt"
    fi
  done < "$HOME/proxy/proxy-list-clark.txt"
done


# Get HTTP/HTTPS HIGH ANONMY WORLD proxies from CLARK
while read -r proxya
do
  if echo "${proxya}" | grep -q "A-S"; then
     echo "${proxya}" | awk '{print $1}' >> "$HOME/proxy/proxy-list-clark-all.txt"
  fi
  if echo "${proxya}" | grep -q "H-S"; then
    echo "${proxya}" | awk '{print $1}' >> "$HOME/proxy/proxy-list-clark-all.txt"
  fi
done < "$HOME/proxy/proxy-list-clark.txt"


# Prepeare CLARK proxy list for mubeng
# Identify HTTP/HTTPS proxies
# Check live proxies for CLARK
sed -i -e 's/^/http:\/\//'  "$HOME/proxy/proxy-list-clark-europa.txt"
mubeng -f "$HOME/proxy/proxy-list-clark-europa.txt" --check --output "$HOME/proxy/clark-live-europa-http.txt" -t 3s

sed -i -e 's/^.\{7\}//g'    "$HOME/proxy/proxy-list-clark-europa.txt"
sed -i -e 's/^/https:\/\//' "$HOME/proxy/proxy-list-clark-europa.txt"
mubeng -f "$HOME/proxy/proxy-list-clark-europa.txt" --check --output "$HOME/proxy/clark-live-europa-https.txt" -t 3s

sed -i -e 's/^/http:\/\//'  "$HOME/proxy/proxy-list-clark-all.txt"
mubeng -f "$HOME/proxy/proxy-list-clark-all.txt" --check --output "$HOME/proxy/clark-live-all-http.txt" -t 3s

sed -i -e 's/^.\{7\}//g'    "$HOME/proxy/proxy-list-clark-all.txt"
sed -i -e 's/^/https:\/\//' "$HOME/proxy/proxy-list-clark-all.txt"
mubeng -f "$HOME/proxy/proxy-list-clark-all.txt" --check --output "$HOME/proxy/clark-live-all-https.txt" -t 3s

# Prepeare other proxy list for mubeng
sed -i -e 's/^/http:\/\//'  "$HOME/proxy/proxy-list-jetkai_http.txt"
sed -i -e 's/^/https:\/\//' "$HOME/proxy/proxy-list-jetkai_https.txt"
sed -i -e 's/^/http:\/\//'  "$HOME/proxy/proxy-list-speedx.txt"
sed -i -e 's/^/http:\/\//'  "$HOME/proxy/proxy-list-sunny9577.txt"
sed -i -e 's/^/http:\/\//'  "$HOME/proxy/proxy-list-saschazesiger.txt"
sed -i -e 's/^/http:\/\//'  "$HOME/proxy/proxy-list-saschazesiger-premium.txt"

# Check live proxies for other lists (speed 2s MEDIUM-FAST)
mubeng -f "$HOME/proxy/proxy-list-speedx.txt" --check --only-cc DE,NL,AT,BE,BG,HR,CY,CZ,DK,EE,FI,FR,GR,HU,IE,IT,LV,LT,LU,MT,NL,PL,PT,RO,SK,SI,ES,SE --output "$HOME/proxy/speedx-http-live.txt" -t 3s
mubeng -f "$HOME/proxy/proxy-list-jetkai_https.txt" --check --only-cc DE,NL,AT,BE,BG,HR,CY,CZ,DK,EE,FI,FR,GR,HU,IE,IT,LV,LT,LU,MT,NL,PL,PT,RO,SK,SI,ES,SE --output "$HOME/proxy/jetkai-https-live.txt" -t 3s
mubeng -f "$HOME/proxy/proxy-list-jetkai_http.txt" --check --only-cc DE,NL,AT,BE,BG,HR,CY,CZ,DK,EE,FI,FR,GR,HU,IE,IT,LV,LT,LU,MT,NL,PL,PT,RO,SK,SI,ES,SE --output "$HOME/proxy/jetkai-http-live.txt" -t 3s
mubeng -f "$HOME/proxy/proxy-list-sunny9577.txt" --check --only-cc DE,NL,AT,BE,BG,HR,CY,CZ,DK,EE,FI,FR,GR,HU,IE,IT,LV,LT,LU,MT,NL,PL,PT,RO,SK,SI,ES,SE --output "$HOME/proxy/sunny-http-live.txt" -t 3s
mubeng -f "$HOME/proxy/proxy-list-saschazesiger.txt" --check --only-cc DE,NL,AT,BE,BG,HR,CY,CZ,DK,EE,FI,FR,GR,HU,IE,IT,LV,LT,LU,MT,NL,PL,PT,RO,SK,SI,ES,SE --output "$HOME/proxy/saschazesiger-http-live.txt" -t 3s
mubeng -f "$HOME/proxy/proxy-list-saschazesiger.txt" --check --output "$HOME/proxy/saschazesiger-http-live-premium.txt" -t 2s

# Merge live http-httpsproxies
cat "$HOME/proxy/speedx-http-live.txt" "$HOME/proxy/jetkai-http-live.txt" "$HOME/proxy/sunny-http-live.txt" "$HOME/proxy/saschazesiger-http-live.txt" "$HOME/proxy/saschazesiger-http-live-premium.txt" > "$HOME/proxy/http-live-proxies.txt"
cat "$HOME/proxy/jetkai-https-live.txt" > "$HOME/proxy/https-live-proxies.txt"

# Drop duplicates
awk -i inplace '!seen[$0]++' "$HOME/proxy/http-live-proxies.txt"
awk -i inplace '!seen[$0]++' "$HOME/proxy/https-live-proxies.txt"

# Get HIGH ANONMY-LIVE from clark
clark_http=("$HOME/proxy/clark-live-europa-http.txt" "$HOME/proxy/clark-live-all-http.txt")
for anonhigh in "${clark_http[@]}"
do
  if [[ -s "${anonhigh}" ]]; then
   cat "${anonhigh}" >> "$HOME/proxy/http-premium-live.txt"
  fi
done

clark_https=("$HOME/proxy/clark-live-europa-https.txt" "$HOME/proxy/clark-live-all-https.txt")
for anonhigh in "${clark_https[@]}"
do
  if [[ -s "${anonhigh}" ]]; then
   cat "${anonhigh}" >> "$HOME/proxy/https-premium-live.txt"
  fi
done

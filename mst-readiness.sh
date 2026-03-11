#!/bin/bash
# -----------------------------------------------------------------------
# Copyright Microsoft Corporation. All rights reserved.
#
# mst-readiness - test network endpoints needed by Microsoft Tunnel Gateway.
# -----------------------------------------------------------------------
export TEXTDOMAIN=mstunnel

function CheckDependency_jq
{
    if ! jq --help > /dev/null; then
        echo "$(gettext "Missing dependency") 'jq'"
        exit 1
    fi
}

function CheckDependency_curl
{
    if ! curl --help > /dev/null; then
        echo "$(gettext "Missing dependency") 'curl'"
        exit 1
    fi
}

function CheckDependency_awk
{
    if ! awk --help > /dev/null; then
        echo "$(gettext "Missing dependency") 'awk'"
        exit 1
    fi
}

function CheckDependency_iptables
{
     if ! lsmod | grep -q ip_tables; then
         echo "$(gettext "Missing dependency") 'ip_tables'"
         echo "$(gettext "Please load ip_tables module into kernel and re-run mst-readiness. For help with loading ip_tables consult MS Tunnel documentation.")"
        exit 1
    fi
}

function CheckDependency_tun
{
     if ! lsmod | grep -q tun; then
         result=$(modprobe --first-time tun 2>&1)
         if [ -z "${result##*not found*}" ]; then
             echo "$(gettext "Missing dependency") 'tun'"
             echo "$(gettext "Please load tun module into kernel and re-run mst-readiness. For help with loading tun consult MS Tunnel documentation.")"
             exit 1
         fi
     fi
}

function CheckDependency_containerEngine
{
    # check for docker or podman and redirect stdout to /dev/null
    # suppress command line error by redirecting to stdout
    if docker --version > /dev/null 2>&1; then
            return;
    fi
    if podman --version > /dev/null 2>&1; then
            return;
    fi

    #if not found display required dependencies and exit
    echo "$(gettext "Missing dependency") 'podman or docker should be installed'"
    echo "$(gettext "Please consult online documentation for Microsoft Tunnel prerequisites")"
    exit 1
}

function CheckDependency_ipforwarding
{
    if ! sysctl -a | grep -q "ip_forward = 1"; then
         echo "$(gettext "Missing dependency") 'ip_forward must be enabled'"
         echo "$(gettext "Set net.ipv4.ip_forward flag to 1 and re-run mst-readiness.")"
        exit 1
    fi
}

function CheckUtils_selinux
{
    local osversion=$(cat /etc/os-release | awk -F '=' '/PRETTY_NAME/ {gsub("\"","",$2); print $2}')
    if [[ "$osversion" =~ .*"Red Hat".* ]]; then
        if getenforce | grep -q "Enforcing"; then
            echo "$(gettext "SELinux enabled")"
        else
            echo "$(gettext "SELinux not enabled. SELinux is recommended for better security, but is not a pre-requisite for Tunnel")"
        fi
    fi
}

function CheckUtils_auditd
{
    if ! command -v auditd >/dev/null 2>&1; then
        echo "$(gettext "Missing dependency") 'auditd'"
        echo "$(gettext "auditd is recommended for auditing any change on the Tunnel server, but is not a pre-requisite for Tunnel")"
    elif ! systemctl is-active auditd >/dev/null 2>&1; then
        echo "$(gettext "auditd is not running")"
        echo "$(gettext "auditd is recommended for auditing any change on the Tunnel server, but is not a pre-requisite for Tunnel")"
    fi
}

function SetupBaseAddresses
{
    case "$intune_env" in
        OneDF)
            intune_address="https://manage-dogfood.microsoft.com"
            aad_address="https://login.windows-ppe.net"
            sts_host="sts.windows-ppe.net"
        ;;
        SelfHost)
            intune_address="https://manage-selfhost.microsoft.com"
            aad_address="https://login.microsoftonline.com"
            sts_host="sts.windows.net"
        ;;
        CTIP)
            intune_address="https://manage-beta.microsoft.com"
            aad_address="https://login.microsoftonline.com"
            sts_host="sts.windows.net"
        ;;
        FXB)
            intune_address="https://manage-ppe.microsoft.us"
            aad_address="https://login.microsoftonline.us"
            sts_host="login.microsoftonline.us"
        ;;
        FXP)
            intune_address="https://manage.microsoft.us"
            aad_address="https://login.microsoftonline.us"
            sts_host="login.microsoftonline.us"
        ;;
        MCB)
            intune_address="https://manage.chinacloudapi.cn"
            aad_address="https://login.chinacloudapi.cn"
            sts_host="login.partner.microsoftonline.cn"
        ;;
        MCP)
            intune_address="https://manage.chinacloudapi.cn"
            aad_address="https://login.chinacloudapi.cn"
            sts_host="login.partner.microsoftonline.cn"
        ;;
        BF)
            intune_address="https://manage.cloudapi.de"
            aad_address="https://login.microsoftonline.de"
            sts_host="login.microsoftonline.de/common"
        ;;
        MIG)
            intune_address="https://manage-mig.microsoft.com"
            aad_address="https://login.microsoftonline.com"
            sts_host="sts.windows.net"
        ;;
    esac

    : "${aad_address:=https://login.microsoftonline.com}"
    : "${intune_address:=https://manage.microsoft.com}"
    : "${sts_host:=sts.windows.net}"
}

# Account Verification Functions
function VerifyAccount
{
    # modify display formatting when called with additional argument
    if [[ -n "$1" ]]; then
        DiagnosticFormatting
    fi
    CheckDependency_jq
    CheckDependency_curl
    client_id=256e3b6b-55ad-4469-83a2-3c26f4f00270
    SetupBaseAddresses
    authurl="${aad_address}/common/oauth2"
    echo "$(gettext "Request ID") = $request_id"
    response=$(curl -s -X POST -F client_id="$client_id" -F resource="${intune_address}/" "${authurl}/devicecode")
    if [ $? -eq 0 ]; then
        echo $(jq -e -r '.message' <<<$response)
        code=$(jq -e -r '.device_code' <<<$response)
        interval=$(jq -e -r '.interval' <<<$response)
        expires=$(jq -e -r '.expires_in' <<<$response)
        waited=0
        while true
        do
            sleep ${interval}s
            (( waited+=$interval ))
            response=$(curl -s -X POST -F client_id="$client_id" -F grant_type=device_code -F code=$code "${authurl}/token")
            token=$(jq -e -r '.access_token' <<<$response) && break
            if [ $waited -ge $expires ]; then
                echo -e "${error_txt}$(gettext "Error"): $(gettext "Device Code Expired")${normal_txt}"
                exit 1
            fi
        done

        if [ -z "$token" ]; then
            error="${error_txt}$(gettext "Error"): $(gettext "Unable to get AAD Token")${normal_txt}"
        else
            # do not print the token if called with argument
            if [[ -z "$1" ]]; then
                echo "------------------------- AAD Token -------------------------"
                # decode and print AAD token
                jq -R -r 'split(".") | .[1]' <<<"$token" | base64 -d 2> /dev/null | jq -M
            fi
            b64token=$(jq -R -r 'split(".") | .[1]' <<<"$token")
            aad_token=$(base64 -d 2> /dev/null <<<$b64token)
            # parse AAD token and check if wids: claim contains either Global or Intune admin
            role=$(jq -e -r '.wids[]' <<<$aad_token)
            failed=true;
            for str in ${role[@]}; do
                if grep -q -E '(62e90394-69f5-4237-9190-012177145e10){1}|(3a2c62db-5318-420d-8d74-23affee5d9d5){1}' <<<$str; then
                    failed=false;
                    break;
                fi
            done
            if [ "$failed" = true ] ; then
                error="${error_txt}$(gettext "Error"): $(gettext "You must be assigned to role 'Global administrator' or 'Intune administrator'")${normal_txt}"
            fi
        fi
        [ -z "$error" ] && echo -e "${success_txt}$(gettext "Success")${normal_txt}" || echo -e "$error"
    else
        local error=$(echo "$response")
    fi
}

# Verify container connectivity
# Called by mst-cli RunDiagnostic
function VerifyContainerConnectivity
{
    # modify display formatting when called with additional argument
    if [[ -n "$2" ]]; then
        DiagnosticFormatting
    else
        tabs 3
    fi

    : ${interactive:=0}
    expect_error=0

    CreateClientCert 2> /dev/null
    CheckAuthUrl # AAD
    CheckLocationUrl # Intune Location
    CheckServiceUrls # Tunnel Service
    CheckOidcUrl
    CheckMcrUrl
    CheckBlobStorageUrl "$1"
    CheckGraphUrl
    RemoveClientCert
}

# Network Verification Functions
function VerifyNetwork
{
    # modify display formatting when called with additional argument
    if [[ -n "$2" ]]; then
        DiagnosticFormatting
    else
        tabs 3
    fi

    : ${interactive:=0}
    expect_error=0

    echo "$(gettext "Checking access to Microsoft Tunnel Endpoints")"
    CreateClientCert 2> /dev/null
    CheckAuthUrl
    CheckLocationUrl
    CheckServiceUrls
    CheckOidcUrl
    CheckMcrUrl
    CheckBlobStorageUrl "$1"
    CheckGraphUrl
    CheckPowerliftUrl
    RemoveClientCert
}

# Verify required utils are present
function VerifyUtils
{
    CheckDependency_iptables
    CheckDependency_tun
    CheckDependency_containerEngine
    CheckDependency_ipforwarding
    CheckUtils_selinux
    CheckUtils_auditd
}

# Called by mst-cli RunDiagnostic
function PostInstallDiagnostics
{
    # Check Tunnel is installed
    if [ ! -d /etc/mstunnel ]; then
        echo "$(gettext "Tunnel is not installed. Cannot run post install diagnostics")"
        exit 1
    fi

    # Modify display formatting when called with argument
    if [[ -n "$1" ]]; then
        DiagnosticFormatting
    fi

    CheckOcspUrl
    CheckDNSServerReachable $1
    CheckAgentCertExpiry $2
    CheckProxyServerConfigured $2
}

function ParseResponse
{
   local response=$1
   awk '/^>\s*Host|^<\s*HTTP/ {print "\t\t"$0}' <<< "$response"
   local issuer=$(awk -F ': ' '/^\*\s*issuer:/ {if (++n == 1) print $2; exit}' <<< "$response")
   local subject=$(awk -F ': ' '/^\*\s*subject:/ {if (++n == 1) print $2; exit}' <<< "$response")
   [ ! -z "$https_proxy" ] && [ "$issuer" == "$subject" ] && {
      echo -e "${error_txt}\t\t$(gettext "Error")${normal_txt}: $(gettext "It appears that the proxy is performing TLS Break and Inspect")"
      echo "subject = $subject"
   }
}

function CheckResponseForError
{
   local response=$1
   awk '/^<\s*HTTP/{status=$3}END{if (status >= 400) exit (status - 300)}' <<<"$response"
   rcode=$?
   return $rcode
}

function CheckEndpointResolve
{
    local host=$1
    local path=$2
    [ $# -ge 3 ] && local cert=$3
    if host -V 2> /dev/null; then
        local ipaddr="$(host "$host" 2> /dev/null | awk '/has address/ { print $4 }')"
    elif dig -h > /dev/null; then
        local ipaddr="$(dig +short $host | awk '/^([0-9.]{1,3}){4}/ {print}')"
    elif getent --help > /dev/null; then
       local ipaddr="$(getent hosts $host | awk '{print $1}')"
    fi

    if [ ! -z "$ipaddr" ]; then
        readarray -t addresses < <(echo "$ipaddr")
        for ip in "${addresses[@]}"
        do
            CheckEndpoint "$host" "$path" "$ip" "$cert"
        done
    else
            CheckEndpoint "$host" "$path" "" "$cert"
    fi

   local res=$?
   expect_error=0
   unset expect_error_message
   return $res
}

function CheckEndpoint
{
   local host=$1
   local path=$2
   [ $# -ge 3 ] && [ ! -z "$3" ] && local ip=$3
   [ $# -ge 4 ] && local cert=$4
   [ ! -z "$ip" ] && local resolve="--resolve ${host}:443:${ip}"
   local url="https://$host$path"
   [ ! -z "$cert" ] && local client_cert="--cert $cert"

   while true; do
   echo ""
   if [[ $interactive -eq 1 ]]; then
      read -p "Check endpoint $host($ip)? (y/n/q): " answer
   case $answer in
      n|N) return;;
      y|Y) ;;
      q|Q) exit 0;;
   esac
   fi

   local error=0;
   echo -e "\t$(gettext "Checking connectivity"):"
   request="curl $url $resolve $client_cert -v -L -S -s -m 20"
   echo -e "$(gettext "Issuing Command"): $request 2>&1 > /dev/null" | awk '{print "\t\t" $0}'
   [ -z "$https_proxy" ] && echo -e "\t\tproxy: NA" || echo -e "\t\tproxy: $https_proxy"
   [ -z "$https_proxy" ] && echo -e "\t\t->$ip" || echo -e "\t\t->$https_proxy->$ip"
   local response=$($request 2>&1 > /dev/null | awk '{gsub(/\r/,""); print}')
   echo "$response" | awk '/^curl:/ {exit 1}'
   error=$?
   if [ $error -ne 0 ]
   then
      local curl_error=$(echo "$response" | awk '/^curl:/ {print "\033[41m\033[30m\t\tError\033[39m\033[22m\033[49m: "$0}')
      error=$(echo $curl_error | awk -F '\\(|\\)' '{print $2}')
      if [[ ! "$curl_error" =~ .*"($error)".* ]]; then
          echo "$curl_error"
      fi
      echo "$response" | awk '/^\*\s*issuer:/ {print "\t\t"$0}'
      error=$(echo $curl_error | awk -F '\\(|\\)' '{print $2}')
   else
      ParseResponse "$response"
      CheckResponseForError "$response"
      local error=$?
   fi

   if [[ $interactive -eq 1 ]] && [ $error -ne 0 ]; then
      read -p "Retry connection (y/n/c/q): " answer
      case $answer in
         n|N) break;;
         y|Y) continue;;
         c|C) interactive=0; break;;
         q|Q) exit 0;;
      esac
   fi
   [[ "$expect_error" =~ .*"$error".* ]] && echo -e "\t\t${success_txt}Success ${expect_error_message}${normal_txt}" || echo -e ${error_txt}"\t\tError: not expected"${normal_txt}
   break
   done
   return $error
}

certPath=/tmp/mst-test-cc.pem
function CreateClientCert
{
   openssl req -x509 -newkey rsa:4096 -sha256 -nodes -keyout "$certPath" -out "/tmp/mst-test-cc.crt" -days 10 -subj "/CN=${HOSTNAME}"
   cat /tmp/mst-test-cc.crt >> "$certPath"
}

function RemoveClientCert
{
   rm -f $certPath /tmp/mst-test-cc.crt 2> /dev/null
}

function CheckBlobStorageUrl
{
    if [ "$1" == "OneDF" ]; then
        expect_error=100
        expect_error_message="$(gettext "Expected error - query parameters specified in the request URI is invalid")"
        CheckEndpointResolve damsu01moaas.blob.core.windows.net

        expect_error=100
        expect_error_message="$(gettext "Expected error - query parameters specified in the request URI is invalid")"
        CheckEndpointResolve damsua0103moaas.blob.core.windows.net
        return
    fi

    if [ "$1" == "SelfHost" ]; then
        expect_error=100
        expect_error_message="$(gettext "Expected error - query parameters specified in the request URI is invalid")"
        CheckEndpointResolve shamsua05moaas.blob.core.windows.net

        expect_error=100
        expect_error_message="$(gettext "Expected error - query parameters specified in the request URI is invalid")"
        CheckEndpointResolve shamsua03moaas.blob.core.windows.net

        expect_error=100
        expect_error_message="$(gettext "Expected error - query parameters specified in the request URI is invalid")"
        CheckEndpointResolve shamsua01moaas.blob.core.windows.net
        return
    fi

    # verify connectivity to PE storage endpoints
    expect_error=100
    expect_error_message="$(gettext "Expected error - query parameters specified in the request URI is invalid")"
    CheckEndpointResolve amsub0102moaas.blob.core.windows.net

    expect_error=100
    expect_error_message="$(gettext "Expected error - query parameters specified in the request URI is invalid")"
    CheckEndpointResolve amsub0601moaas.blob.core.windows.net

    expect_error=100
    expect_error_message="$(gettext "Expected error - query parameters specified in the request URI is invalid")"
    CheckEndpointResolve amsub0501moaas.blob.core.windows.net

    expect_error=100
    expect_error_message="$(gettext "Expected error - query parameters specified in the request URI is invalid")"
    CheckEndpointResolve amsub0502moaas.blob.core.windows.net

    expect_error=100
    expect_error_message="$(gettext "Expected error - query parameters specified in the request URI is invalid")"
    CheckEndpointResolve amsua0702moaas.blob.core.windows.net

    expect_error=100
    expect_error_message="$(gettext "Expected error - query parameters specified in the request URI is invalid")"
    CheckEndpointResolve amsua0201moaas.blob.core.windows.net

    expect_error=100
    expect_error_message="$(gettext "Expected error - query parameters specified in the request URI is invalid")"
    CheckEndpointResolve amsua0602moaas.blob.core.windows.net

    expect_error=100
    expect_error_message="$(gettext "Expected error - query parameters specified in the request URI is invalid")"
    CheckEndpointResolve amsua0502moaas.blob.core.windows.net

    expect_error=100
    expect_error_message="$(gettext "Expected error - query parameters specified in the request URI is invalid")"
    CheckEndpointResolve amsua0402moaas.blob.core.windows.net

    expect_error=100
    expect_error_message="$(gettext "Expected error - query parameters specified in the request URI is invalid")"

    expect_error=100
    expect_error_message="$(gettext "Expected error - query parameters specified in the request URI is invalid")"
    CheckEndpointResolve amsua0202moaas.blob.core.windows.net

    expect_error=100
    expect_error_message="$(gettext "Expected error - query parameters specified in the request URI is invalid")"
    CheckEndpointResolve amsua0102moaas.blob.core.windows.net

    expect_error=100
    expect_error_message="$(gettext "Expected error - query parameters specified in the request URI is invalid")"
    CheckEndpointResolve amsua0801moaas.blob.core.windows.net

    expect_error=100
    expect_error_message="$(gettext "Expected error - query parameters specified in the request URI is invalid")"
    CheckEndpointResolve amsua0401moaas.blob.core.windows.net

    expect_error=100
    expect_error_message="$(gettext "Expected error - query parameters specified in the request URI is invalid")"
    CheckEndpointResolve amsub0101moaas.blob.core.windows.net

    expect_error=100
    expect_error_message="$(gettext "Expected error - query parameters specified in the request URI is invalid")"
    CheckEndpointResolve amsub0201moaas.blob.core.windows.net

    expect_error=100
    expect_error_message="$(gettext "Expected error - query parameters specified in the request URI is invalid")"
    CheckEndpointResolve amsub0202moaas.blob.core.windows.net

    expect_error=100
    expect_error_message="$(gettext "Expected error - query parameters specified in the request URI is invalid")"
    CheckEndpointResolve amsub0301moaas.blob.core.windows.net

    expect_error=100
    expect_error_message="$(gettext "Expected error - query parameters specified in the request URI is invalid")"

    expect_error=100
    expect_error_message="$(gettext "Expected error - query parameters specified in the request URI is invalid")"
    CheckEndpointResolve amsub0302moaas.blob.core.windows.net

    expect_error=100
    expect_error_message="$(gettext "Expected error - query parameters specified in the request URI is invalid")"
    CheckEndpointResolve amsub0701moaas.blob.core.windows.net

    expect_error=100
    expect_error_message="$(gettext "Expected error - query parameters specified in the request URI is invalid")"
    CheckEndpointResolve amsua0601moaas.blob.core.windows.net

    expect_error=100
    expect_error_message="$(gettext "Expected error - query parameters specified in the request URI is invalid")"

    expect_error=100
    expect_error_message="$(gettext "Expected error - query parameters specified in the request URI is invalid")"
    CheckEndpointResolve amsua0501moaas.blob.core.windows.net

    expect_error=100
    expect_error_message="$(gettext "Expected error - query parameters specified in the request URI is invalid")"
    CheckEndpointResolve amsua0701moaas.blob.core.windows.net

    expect_error=100
    expect_error_message="$(gettext "Expected error - query parameters specified in the request URI is invalid")"
    CheckEndpointResolve amsua0101moaas.blob.core.windows.net

    expect_error=100
    expect_error_message="$(gettext "Expected error - query parameters specified in the request URI is invalid")"
    CheckEndpointResolve amsua0901moaas.blob.core.windows.net

    expect_error=100
    expect_error_message="$(gettext "Expected error - query parameters specified in the request URI is invalid")"
    CheckEndpointResolve amsuc0201moaas.blob.core.windows.net

    expect_error=100
    expect_error_message="$(gettext "Expected error - query parameters specified in the request URI is invalid")"
    CheckEndpointResolve amsuc0101moaas.blob.core.windows.net

    expect_error=100
    expect_error_message="$(gettext "Expected error - query parameters specified in the request URI is invalid")"
    CheckEndpointResolve amsuc0301moaas.blob.core.windows.net

    expect_error=100
    expect_error_message="$(gettext "Expected error - query parameters specified in the request URI is invalid")"
    CheckEndpointResolve amsuc0501moaas.blob.core.windows.net

    expect_error=100
    expect_error_message="$(gettext "Expected error - query parameters specified in the request URI is invalid")"
    CheckEndpointResolve amsud0101moaas.blob.core.windows.net

    expect_error=100
    expect_error_message="$(gettext "Expected error - query parameters specified in the request URI is invalid")"
    CheckEndpointResolve amsuin01moaas.blob.core.windows.net
}

function CheckGraphUrl
{
    CheckEndpointResolve "graph.microsoft.com"
}

function CheckAuthUrl
{
    CheckEndpointResolve "login.microsoftonline.com" "/common/oauth2/deviceauth"
    CheckEndpointResolve "login.windows.net"
}

function CheckMcrUrl
{
   CheckEndpointResolve "mcr.microsoft.com" "/v2/"

   expect_error="104 109 100"
   expect_error_message="$(gettext "Expected error - Not Found")"
   CheckEndpointResolve "eastasia.data.mcr.microsoft.com" "/blobs/"

   expect_error="104 109 100"
   expect_error_message="$(gettext "Expected error - Not Found")"
   CheckEndpointResolve "southeastasia.data.mcr.microsoft.com" "/blobs/"

   expect_error="104 109 100"
   expect_error_message="$(gettext "Expected error - Not Found")"
   CheckEndpointResolve "centralus.data.mcr.microsoft.com" "/blobs/"

   expect_error="104 109 100"
   expect_error_message="$(gettext "Expected error - Not Found")"
   CheckEndpointResolve "eastus.data.mcr.microsoft.com" "/blobs/"

   expect_error="104 109 100"
   expect_error_message="$(gettext "Expected error - Not Found")"
   CheckEndpointResolve "westus.data.mcr.microsoft.com" "/blobs/"

   expect_error="104 109 100"
   expect_error_message="$(gettext "Expected error - Not Found")"
   CheckEndpointResolve "northeurope.data.mcr.microsoft.com" "/blobs/"

   expect_error="104 109 100"
   expect_error_message="$(gettext "Expected error - Not Found")"
   CheckEndpointResolve "westeurope.data.mcr.microsoft.com" "/blobs/"

   expect_error="104 109 100"
   expect_error_message="$(gettext "Expected error - Not Found")"
   CheckEndpointResolve "westcentralus.data.mcr.microsoft.com" "/blobs/"

   expect_error="104 109 100"
   expect_error_message="$(gettext "Expected error - Not Found")"
   CheckEndpointResolve "westus2.data.mcr.microsoft.com" "/blobs/"
}

function CheckOidcUrl
{
    SetupBaseAddresses
    CheckEndpointResolve "$sts_host" "/*/v2.0/.well-known/openid-configuration"

}

function CheckLocationUrl
{
   # HTTP errors are Error - 300, so 400 -> 100
   expect_error=100
   expect_error_message="$(gettext "Expected error - no client certificate")"
   CheckEndpointResolve "manage.microsoft.com" "/RestUserAuthLocationService/RestUserAuthLocationService/Certificate/ServiceAddresses"

   # HTTP errors are Error - 300, so 403 -> 103
   expect_error=103
   expect_error_message="$(gettext "Expected error - not enrolled")"
   CheckEndpointResolve "manage.microsoft.com" "/RestUserAuthLocationService/RestUserAuthLocationService/Certificate/ServiceAddresses" $certPath
}

function CheckService
{
   local metaPath='/TrafficGateway/TrafficRoutingService/MobileAccess/MobileAccessService/$metadata'
   local sitePath="/TrafficGateway/TrafficRoutingService/MobileAccess/MobileAccessService/Sites"
   CheckEndpointResolve "$1" $metaPath
   expect_error=101
   expect_error_message="Expected error - not enrolled"
   CheckEndpointResolve "$1" $sitePath $certPath
}

function CheckServiceUrls
{
   CheckService "agents.msua01.manage.microsoft.com"
   CheckService "agents.msua02.manage.microsoft.com"
   CheckService "agents.msua04.manage.microsoft.com"
   CheckService "agents.msua06.manage.microsoft.com"
   CheckService "agents.msub05.manage.microsoft.com"
   CheckService "agents.msuc03.manage.microsoft.com"
   CheckService "agents.amsua0502.manage.microsoft.com"
   CheckService "agents.amsua0602.manage.microsoft.com"
   CheckService "agents.amsua0102.manage.microsoft.com"
   CheckService "agents.amsua0702.manage.microsoft.com"
   CheckService "agents.amsub0502.manage.microsoft.com"
   CheckService "agents.msud01.manage.microsoft.com"
}

function CheckPowerliftUrl
{
    expect_error=105
    CheckEndpointResolve "powerlift-frontdesk.acompli.net" "/api/incidents"
}

function CheckOcspUrl
{
    echo -e "$(gettext "\n\nTitle: Check connectivity to OCSP url")"
    echo -e "$(gettext "Results:")"

    # Get ocsp url from server's TLS certificate
    if [ ! -f /etc/mstunnel/certs/site.crt ]; then
        echo "$(gettext "/etc/mstunnel/certs/site.crt does not exist. Cannot get OCSP urls")"
        return
    fi

    ocspurl=`openssl x509 -in /etc/mstunnel/certs/site.crt -noout -ocsp_uri`
    ocspurl=${ocspurl#*"//"}

    # check if OCSP urlis reachable
    expect_error=" 51 60"
    CheckEndpointResolve $ocspurl
}

function CheckAgentCertExpiry
{
    # Check if agent certificate exists
    if [ ! -f /etc/mstunnel/private/agent.p12 ]; then
        echo -e "$(gettext "\nTitle: Agent Certificate Validity: Number of Days until expiration")" >> $1
        echo "$(gettext "Results: /etc/mstunnel/private/agent.p12 does not exist. Cannot check Agent certificate expiry.")" >> $1
        return
    fi
    openssl pkcs12 -in /etc/mstunnel/private/agent.p12 -out /etc/mstunnel/diagnostic/agentcertificate.pem -password pass: -nodes
    expiryDate=`cat /etc/mstunnel/diagnostic/agentcertificate.pem | openssl x509 -noout -enddate`
    expiryDate=${expiryDate#*"="}
    expiryDate=`date -d "$expiryDate"`
    todaysDate=`date -d "today"`
    daysToExpiry="$((($(date -d "$expiryDate" +%s) - $(date -d "$todaysDate" +%s))/86400))"
    if [[ $daysToExpiry -le 0 ]]; then
        daysToExpiry="0 expired: $expiryDate"
    fi

    if [[ -n "$1" ]]; then
        echo -e "$(gettext "\nTitle: Agent Certificate Validity: Number of Days until expiration")" >> $1
        echo "$(gettext "Results: $daysToExpiry")" >> $1
    fi
}

function CheckDNSServerReachable
{
    echo -e "$(gettext "\n\nTitle: Check connectivity to DNS server")"
    echo -e "$(gettext "Results:")"

    # Check if ocserv.conf exists
    if [ ! -f /etc/mstunnel/ocserv.conf ]; then
        echo -e "$(gettext "\nTitle: Verify DNS Server Accessibility from Tunnel Server")" >> $1
        echo "$(gettext "Results: Fail: /etc/mstunnel/ocserv.conf does not exist. Cannot check DNS server is reachable.")" >> $1
        echo "$(gettext "/etc/mstunnel/ocserv.conf does not exist. Cannot check DNS server is reachable.")"
        return
    fi

    local dnsServerIP=$(cat /etc/mstunnel/ocserv.conf | awk -F ' = ' '/dns/ {gsub("\"","",$2); print $2}')

    if [ -z "$dnsServerIP" ]; then
        echo -e "$(gettext "\nTitle: Verify DNS Server Accessibility from Tunnel Server")" >> $1
        echo "$(gettext "Results: Fail: No DNS server configuration in ocserv.conf")" >> $1
        echo "$(gettext "/etc/mstunnel/ocserv.conf does not contain dns server configuration. Cannot check DNS server is reachable.")"
        return
    fi

    expect_error=" 51 60 "
    dnsServerIP=`printf $dnsServerIP | sed -n '1 p'` # get the first DNS IP, if there are multiple
    CheckEndpoint "dnsServer" "" $dnsServerIP

    local res=$?

    if [[ -n "$1" ]]; then
        echo -e "$(gettext "\nTitle: Verify DNS Server Accessibility from Tunnel Server")" >> $1
        if [[ "$expect_error" =~ .*" $res ".* ]]; then
            echo "$(gettext "Results: Pass: DNS Reachable")" >> $1
        else
            echo "$(gettext "Results: Fail: DNS Not Reachable")" >> $1
        fi
    fi
}

function CheckProxyServerConfigured
{
    echo -e "$(gettext "\n\nTitle: Check proxy server configuration")"
    echo -e "$(gettext "Results:")"
    echo -e "$(gettext "\nTitle: Proxy configuration in /etc/mstunnel/env.sh")" >> $1

    # Check if env.sh exists
    if [ ! -f /etc/mstunnel/env.sh ]; then
        echo "$(gettext "Results: Fail: /etc/mstunnel/env.sh does not exist. Cannot check proxy server configuration.")" >> $1
        echo "$(gettext "/etc/mstunnel/env.sh does not exist. Cannot check proxy server configuration.")"
        return
    fi

    local proxyServerIP=$(grep -v "#" /etc/mstunnel/env.sh | awk -F '=' '/HTTP_PROXY/ {gsub("\"","",$2); print $2}')

    if [ -z "$proxyServerIP" ]; then
        echo "$(gettext "Proxy configuration not found in /etc/mstunnel/env.sh")" >> $1
        echo "$(gettext "Proxy configuration not found in /etc/mstunnel/env.sh")"
        return
    else
        echo "$(gettext "Results: Proxy configuration $proxyServerIP found in /etc/mstunnel/env.sh")" >> $1
        echo "$(gettext "Proxy configuration $proxyServerIP found in /etc/mstunnel/env.sh")"
    fi
}

function ShowUsage
{
    script_name=${0##*/}
    echo "$(gettext "Usage"): $script_name $(gettext "[command]")"
    echo ""
    echo "$(gettext "Commands")"
    echo "  network [env]   $(gettext "Check network connectivity")"
    echo "  account         $(gettext "Check account access")"
    echo "  utils           $(gettext "Check utilities Tunnel depends on")"
}

function ProcessArgs
{
    (( $# < 1 )) && ShowUsage && return 0

    Command=${1}

    case "${Command}" in
        container) # Called by mst-cli RunDiagnostic
            VerifyContainerConnectivity $2 $3
        ;;
        network)
            VerifyNetwork $2 $3
        ;;
        account)
            VerifyAccount $2
        ;;
        utils)
            VerifyUtils
        ;;
        postinstall) # Called by mst-cli RunDiagnostic
            PostInstallDiagnostics $2 $3
        ;;
        *)
            ShowUsage
        ;;
    esac
}

function DiagnosticFormatting
{
    error_txt="\033[31m"
    success_txt="\033[32m"
}

request_id=$(uuidgen)
error_txt="\033[41m\033[30m"
success_txt="\033[40m\033[32m"
normal_txt="\033[39m\033[22m\033[49m"

ProcessArgs "$@"

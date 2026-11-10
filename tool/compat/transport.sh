# BMC Shell 2.0 - core/transport.sh

_bmc_curl_quote() {
    local +x value=$1
    value=${value//\\/\\\\}; value=${value//\"/\\\"}
    value=${value//$'\n'/\\n}; value=${value//$'\r'/\\r}; value=${value//$'\t'/\\t}
    printf '%s' "$value"
}

_bmc_curl_options() {
    local proxy_address
    proxy_address=$(_bmcshell_bridge proxy-address) || return
    opts=(--disable --silent --show-error --globoff --proto '=https' --connect-timeout "${BMC_CONNECT_TIMEOUT:-5}" --max-time "${BMC_HTTP_TIMEOUT:-15}" --max-filesize 2097152)
    if [[ -n $proxy_address ]]; then opts+=(--proxy "socks5h://$proxy_address" --noproxy '')
    else opts+=(--proxy '' --noproxy '*'); fi
    [[ $1 == insecure ]] && opts+=(-k)
    [[ -n ${BMC_CA_BUNDLE-} ]] && opts+=(--cacert "$BMC_CA_BUNDLE")
    return 0
}

_bmc_http() (
    umask 077
    local ip=$1 tls=$2 method=$3 path=$4 user=$5 kind=${7:-none} data=${8-} dir code rc bytes
    local +x password=$6
    local -a opts
    _bmc_curl_options "$tls" || return
    dir=$(mktemp -d "${TMPDIR:-/tmp}/bmc-shell.http.XXXXXX") || return
    trap 'rm -f -- "$dir/body"; rmdir -- "$dir"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' HUP TERM
    if code=$({
        if [[ -n $user ]]; then
            printf 'user = "%s:%s"\n' "$(_bmc_curl_quote "$user")" "$(_bmc_curl_quote "$password")"
            printf 'basic\n'
        fi
        printf 'header = "Accept: application/json"\n'
        if [[ $kind != none ]]; then
            printf 'header = "Content-Type: application/json"\n'
            if [[ $kind == file ]]; then printf 'data-binary = "@%s"\n' "$(_bmc_curl_quote "$data")"
            else printf 'data-binary = "%s"\n' "$(_bmc_curl_quote "$data")"; fi
        fi
    } | command curl "${opts[@]}" --config - --request "$method" --output "$dir/body" --write-out '%{http_code}' "https://$ip$path"); then
        [[ $code =~ ^[0-9]{3}$ ]] || { _bmc_error 'Invalid curl HTTP status.'; return 2; }
        bytes=$(wc -c < "$dir/body") || return
        (( bytes <= 2097152 )) || { _bmc_error 'HTTP response exceeds the 2 MiB limit.'; return 63; }
        printf '%s\n' "$code"
        cat -- "$dir/body"
    else
        rc=$?; _bmc_error "HTTPS transport failed (curl $rc). Check connectivity, TLS trust and timeouts; credentials were not classified as invalid."
        return "$rc"
    fi
)

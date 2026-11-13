# BMC Shell 2.0 - core/transport.sh

_bmc_curl_quote() {
    local +x value=$1
    value=${value//\\/\\\\}; value=${value//\"/\\\"}
    value=${value//$'\n'/\\n}; value=${value//$'\r'/\\r}; value=${value//$'\t'/\\t}
    printf '%s' "$value"
}

_bmc_curl_options() {
    local proxy_address
    local connect_timeout=${BMC_CONNECT_TIMEOUT:-${BMCSHELL_REDFISH_CONNECT_TIMEOUT:-5}}
    local request_timeout=${BMC_HTTP_TIMEOUT:-${BMCSHELL_REDFISH_REQUEST_TIMEOUT:-15}}
    local ca_bundle=${BMC_CA_BUNDLE:-${BMCSHELL_REDFISH_CA_BUNDLE-}}
    if [[ ! $connect_timeout =~ ^[1-9][0-9]{0,2}$ || ! $request_timeout =~ ^[1-9][0-9]{0,2}$ ]]; then
        _bmc_error '连接和请求超时必须为 1 至 999 秒的整数。'
        return 2
    fi
    if [[ -n $ca_bundle && ( $ca_bundle == *[[:cntrl:]]* || ! -f $ca_bundle || ! -r $ca_bundle ) ]]; then
        _bmc_error '无法读取设置中的 CA 证书文件。'
        return 2
    fi
    proxy_address=$(_bmcshell_bridge proxy-address) || return
    opts=(--disable --silent --show-error --globoff --proto '=https' --connect-timeout "$connect_timeout" --max-time "$request_timeout" --max-filesize 2097152)
    if [[ -n $proxy_address ]]; then opts+=(--proxy "socks5h://$proxy_address" --noproxy '')
    else opts+=(--proxy '' --noproxy '*'); fi
    [[ $1 == insecure ]] && opts+=(-k)
    [[ -n $ca_bundle ]] && opts+=(--cacert "$ca_bundle")
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
        [[ $code =~ ^[0-9]{3}$ ]] || { _bmc_error 'curl 返回的 HTTP 状态码无效。'; return 2; }
        bytes=$(wc -c < "$dir/body") || return
        (( bytes <= 2097152 )) || { _bmc_error 'HTTP 响应超过 2 MiB 上限。'; return 63; }
        printf '%s\n' "$code"
        cat -- "$dir/body"
    else
        rc=$?; _bmc_error "HTTPS 传输失败（curl 退出码 $rc），凭据验证结果未知。请检查网络连接、TLS 证书信任及超时设置。"
        return "$rc"
    fi
)

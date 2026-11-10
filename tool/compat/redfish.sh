# BMC Shell 2.0 - plugins/redfish.sh

_bmc_show_redfish_command() {
    _bmc_preview_enabled || return 0
    local method=$1 path=$2 kind=$3
    local +x data=$4
    local -a opts
    _bmc_curl_options "$_BMC_TLS"
    opts+=(--basic --user "$_BMC_USER:$_BMC_PASSWORD" --header 'Accept: application/json' --request "$method")
    if [[ $kind != none ]]; then
        opts+=(--header 'Content-Type: application/json')
        if [[ $kind == file ]]; then opts+=(--data-binary "@$data")
        else opts+=(--data-binary "$data"); fi
    fi
    _bmc_show_command command curl "${opts[@]}" "https://$_BMC_IP$path"
}
# Transport contract: stdout is HTTP-code + LF + response body. Return status is curl's status.
# Passwords/request payloads use curl config on stdin, never command-line arguments.

_bmc_tool_redfish() {
    _bmc_secret_guard && _bmc_require_active || return
    local method=${1-} path=${2-} payload=${3-} kind=none raw code
    (( $# >= 2 && $# <= 3 )) || { _bmc_error 'Use: redfish GET|POST|PATCH|DELETE /redfish/v1/... [JSON|@file]'; return 2; }
    case $method in GET|POST|PATCH|DELETE) ;; *) _bmc_error 'Supported methods: GET POST PATCH DELETE (uppercase).'; return 2;; esac
    case $path in /redfish/v1|/redfish/v1/|/redfish/v1/*) ;; *) _bmc_error 'Use a path within /redfish/v1/ on the active device.'; return 2;; esac
    [[ $path != *[[:space:][:cntrl:]]* && $path != *'#'* && $path != *'\'* && $path != *'/../'* && $path != */.. ]] || { _bmc_error 'Invalid Redfish path.'; return 2; }
    if (( $# == 3 )); then
        [[ $method != GET ]] || { _bmc_error 'GET requests cannot have a body.'; return 2; }
        if [[ $payload == @* ]]; then
            kind=file; payload=${payload#@}
            [[ -f $payload && -r $payload ]] || { _bmc_error 'Request body file is not readable.'; return 2; }
        else kind=inline; fi
    fi
    _bmc_settings_valid || return
    _bmc_show_redfish_command "$method" "$path" "$kind" "$payload"
    raw=$(_bmc_http "$_BMC_IP" "$_BMC_TLS" "$method" "$path" "$_BMC_USER" "$_BMC_PASSWORD" "$kind" "$payload") || return
    code=${raw%%$'\n'*}
    printf '%s\n' "${raw#*$'\n'}"
    case $code in 2??) return 0 ;; *) _bmc_error "Redfish HTTP $code (response printed above); request was not retried."; return 22 ;; esac
}


_bmc_verify_redfish() (
    # Local descriptors/jobs cannot overwrite the caller's descriptors or context.
    local ip=$1 tls=$2 backend=$3 user=$4 code body probe_pid anon_rc auth_rc read_rc
    local +x password=$5 raw='' authenticated=''
    # Both reads target the same device. Accept credentials only after BOTH checks.
    # The anonymous request overlaps the authenticated HTTPS request; it is always
    # drained and joined before this verifier evaluates a result or returns.
    exec 9< <(_bmc_http "$ip" "$tls" GET /redfish/v1/AccountService/Accounts '' '' none '')
    probe_pid=$!
    if authenticated=$(_bmc_http "$ip" "$tls" GET /redfish/v1/AccountService/Accounts "$user" "$password" none ''); then auth_rc=0
    else auth_rc=$?; fi
    if raw=$(command cat <&9); then read_rc=0; else read_rc=$?; fi
    exec 9<&-
    if wait "$probe_pid"; then anon_rc=0; else anon_rc=$?; fi
    (( anon_rc == 0 && read_rc == 0 )) || return 3
    code=${raw%%$'\n'*}
    case $code in
        401|403) ;;
        200) _bmc_error 'Accounts 可匿名访问，不能据此证明凭据有效。'; return 3 ;;
        404|405|501) _bmc_error '不支持受保护的 Redfish 验证；可显式选择 -v ipmi。'; return 3 ;;
        *) _bmc_error "匿名验证请求返回 HTTP $code，认证结果不接受。"; return 3 ;;
    esac
    (( auth_rc == 0 )) || return 3
    raw=$authenticated
    code=${raw%%$'\n'*}; body=${raw#*$'\n'}
    case $code in
        200)
            if printf '%s' "$body" | _bmc_json "$backend" accounts; then return 0; fi
            _bmc_error 'HTTP 200 did not contain the expected protected Accounts collection; verification failed.'; return 3
            ;;
        401) _bmc_error 'Redfish rejected authentication (401); account state is unknown.'; return 1 ;;
        403) _bmc_error 'Redfish denied access (403); privileges/account state are unknown.'; return 3 ;;
        404|405|501) _bmc_error 'Protected Redfish verification is unsupported here. If appropriate, retry explicitly with --verify ipmi.'; return 3 ;;
        *) _bmc_error "Redfish verification failed (HTTP $code); no automatic credential retries."; return 3 ;;
    esac
)

_bmc_register_plugin redfish 'Redfish GET/POST/PATCH/DELETE 与验证'
_bmc_register_verifier redfish _bmc_verify_redfish

_bmc_register_tool redfish _bmc_tool_redfish 'redfish 工具：bmc tool redfish' || return

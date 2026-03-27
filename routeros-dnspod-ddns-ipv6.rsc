# -----------------------------
# RouterOS DNSPod DDNS IPv6 Auto-Setup Script
# -----------------------------

# DNSPod 参数
:global DPToken "YOUR_DNSPOD_ID,YOUR_DNSPOD_TOKEN"
:global DPDomain "example.com"
:global DPSubDomain "home"

:log info "Debug: Token is $DPToken"
:log info "Debug: Domain is $DPDomain"
:log info "Debug: SubDomain is $DPSubDomain"

# 模拟 Header 避免 401 错误
:local httpHeader "User-Agent: Mikrotik-RouterOS/7.x; Content-Type: application/x-www-form-urlencoded"

# 自动获取当前公网 IPv6 (原始逻辑：排除非公网前缀)
:local PUB6 ""
:foreach i in=[/ipv6/address/find where global] do={
    :local addr [/ipv6/address get $i address]
    :local prefix4 [:pick $addr 0 4]
    :local prefix2 [:pick $addr 0 2]
    
    # 排除 fe80 (Link-local), fd00/fc00 (Unique Local)
    :if ($prefix4 != "fe80" && $prefix2 != "fd" && $prefix2 != "fc" && [:find $addr "/"] != -1) do={
        :set PUB6 [:pick $addr 0 [:find $addr "/"]]
    }
}

:if ($PUB6 = "") do={
    :log error "DNSPod-DDNS: No Global IPv6 address found!"
    :error "Stop."
}

# 获取 Record ID (Record.List)
:local recordId ""
:local cloudIp ""
:local commonData "login_token=$DPToken&format=json&domain=$DPDomain&sub_domain=$DPSubDomain"

:do {
    :local result [/tool fetch url="https://dnsapi.cn/Record.List" http-method=post http-header-field=$httpHeader \
        http-data="$commonData&record_type=AAAA" as-value output=user]
    :local resp ($result->"data")
    :log info "DNSPod Response is: $resp"
    
    :if ([:find $resp "\"code\":1"] != -1 || [:find $resp "\"code\":\"1\""] != -1) do={
        :local recordsPos [:find $resp "\"records\":"]
        :local idKey "\"id\":\""
        
        :local idPos ([:find $resp $idKey $recordsPos] + [:len $idKey])
        :set recordId [:pick $resp $idPos [:find $resp "\"" $idPos]]
        
        :log info "DNSPod-DDNS: Successfully caught recordId: $recordId"
    } else={
        :log error "DNSPod-DDNS: API returned error or format mismatch. Response: $resp"
    }
} on-error={ :log warning "DNSPod-DDNS: Record.List query failed." }

# 获取云端当前真实 Value (Record.Info)
:if ([:len $recordId] > 0) do={
    :do {
        :local infoResult [/tool fetch url="https://dnsapi.cn/Record.Info" http-method=post http-header-field=$httpHeader \
            http-data="login_token=$DPToken&format=json&domain=$DPDomain&record_id=$recordId" as-value output=user]
        :local infoResp ($infoResult->"data")
        
        :local valKey "\"value\":\""
        :local valPos ([:find $infoResp $valKey] + [:len $valKey])
        :set cloudIp [:pick $infoResp $valPos [:find $infoResp "\"" $valPos]]
    } on-error={ :log warning "DNSPod-DDNS: Record.Info query failed." }
}

# 核心判断与更新 (不再只依赖 LAST6，而是实测对比)
:global LAST6
:if ($PUB6 != $cloudIp) do={
    :log info "DNSPod-DDNS: IP Out of Sync! Local: $PUB6, Cloud: $cloudIp"

    :local finalUrl "https://dnsapi.cn/Record.Modify"
    :local finalData "login_token=$DPToken&format=json&domain=$DPDomain&sub_domain=$DPSubDomain&record_id=$recordId&record_type=AAAA&record_line=%e9%bb%98%e8%ae%a4&value=$PUB6"

    :if ([:len $recordId] = 0) do={
        :set finalUrl "https://dnsapi.cn/Record.Create"
        :set finalData "login_token=$DPToken&format=json&domain=$DPDomain&sub_domain=$DPSubDomain&record_type=AAAA&record_line=%e9%bb%98%e8%ae%a4&value=$PUB6"
    }

    :do {
        :local updateRes [/tool fetch url=$finalUrl http-method=post http-header-field=$httpHeader http-data=$finalData as-value output=user]
        :local rawData ($updateRes->"data")
        :log info "DNSPod Response is: $rawData"
        :if ([:find ($updateRes->"data") "\"code\":\"1\""] != -1) do={
            :set LAST6 $PUB6
            :log info "DNSPod-DDNS: Sync Success! New IP: $PUB6"
        } else={
            :log error "DNSPod-DDNS: Update Failed: ($updateRes->\"data\")"
        }
    } on-error={ :log error "DNSPod-DDNS: API request failed." }
} else={
    # 即使没变，也刷新一下内存变量确保一致
    :set LAST6 $PUB6
    :log info "DNSPod-DDNS: Local and Cloud are identical ($PUB6). Skip."
}

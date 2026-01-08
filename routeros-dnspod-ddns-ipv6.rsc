# -----------------------------
# RouterOS DNSPod DDNS IPv6 Auto-Setup Script
# -----------------------------

# DNSPod 参数
:global DPToken "YOUR_DNSPOD_ID,YOUR_DNSPOD_TOKEN"
:global DPDomain "example.com"
:global DPSubDomain "home"

# 1. 获取当前 IPv6 地址 (更加健壮的获取方式)
# 遍历所有标记为 global 且非 dynamic=no 的地址，确保拿到真正的公网 IPv6
:local PUB6 ""
:foreach i in=[/ipv6/address/find where global] do={
    :local addr [/ipv6/address get $i address]
    # 进一步排除常见的 Link-local (fe80) 和 Unique Local (fd00/fc00)
    :local prefix4 [:pick $addr 0 4]
    :local prefix2 [:pick $addr 0 2]
    :if ($prefix4 != "fe80" && $prefix2 != "fd" && $prefix2 != "fc") do={
        :set PUB6 $addr
    }
}

:if ($PUB6 != "") do={
    # 去掉 CIDR 后缀 (如 /64)
    :set PUB6 [:pick $PUB6 0 [:find $PUB6 "/"]]
    :global LAST6

    # 只有 IP 真正变化时才执行
    :if ($PUB6 != $LAST6) do={
        :log info "DNSPod-DDNS: IPv6 changed to $PUB6, checking DNS record..."

        # 2. 自动获取 Record ID
        :local listUrl "https://dnsapi.cn/Record.List"
        :local listData ("login_token=$DPToken&format=json&domain=$DPDomain&sub_domain=$DPSubDomain&record_type=AAAA")
        :local recordId ""

        :do {
            :local result [/tool fetch url=$listUrl http-method=post mode=https check-certificate=no http-data=$listData as-value output=user]
            :local resp ($result->"data")

            # 解析 ID
            :local idKey "\"id\":\""
            :local idPos [:find $resp $idKey]

            :if ([:len $idPos] > 0) do={
                :set idPos ($idPos + [:len $idKey])
                :local idEnd [:find $resp "\"" $idPos]
                :set recordId [:pick $resp $idPos $idEnd]
                :log info "DNSPod-DDNS: Found existing RecordID: $recordId"
            }
        } on-error={ :log warning "DNSPod-DDNS: Failed to query record list." }

        # 3. 自动判断：更新还是创建
        :local finalUrl ""
        :local finalData ""

        :if ([:len $recordId] > 0) do={
            :set finalUrl "https://dnsapi.cn/Record.Ddns"
            :set finalData ("login_token=$DPToken&format=json&domain=$DPDomain&sub_domain=$DPSubDomain&record_id=$recordId&record_line=%e9%bb%98%e8%ae%a4&value=$PUB6")
        } else={
            :set finalUrl "https://dnsapi.cn/Record.Create"
            :set finalData ("login_token=$DPToken&format=json&domain=$DPDomain&sub_domain=$DPSubDomain&record_type=AAAA&record_line=%e9%bb%98%e8%ae%a4&value=$PUB6")
        }

        # 4. 执行 API 请求并同步 LAST6
        :do {
            :local finalResult [/tool fetch url=$finalUrl http-method=post mode=https check-certificate=no http-data=$finalData as-value output=user]
            :local finalResp ($finalResult->"data")

            :if ([:find $finalResp "\"code\":\"1\""] != -1) do={
                :set LAST6 $PUB6
                :log info "DNSPod-DDNS: Success! Record updated to $PUB6"
            } else={
                :log error "DNSPod-DDNS: API Error result: $finalResp"
            }
        } on-error={ :log error "DNSPod-DDNS: Final API request failed." }

    } else={
        :log info "DNSPod-DDNS: IPv6 has not changed ($PUB6), skipping."
    }
} else={
    :log error "DNSPod-DDNS: No global IPv6 address found on any interface!"
}

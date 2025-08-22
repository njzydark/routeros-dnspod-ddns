# -----------------------------
# RouterOS Cloudflare DDNS IPv6 Script 2.0
# -----------------------------

# Cloudflare 参数（请自行替换）
:global CFAPITOKEN "YOUR_CLOUDFLARE_API_TOKEN"
:global CFZoneID "YOUR_ZONE_ID"
:global CFRecordID "YOUR_RECORD_ID"
:global CFDNSNAME "YOUR_DOMAIN_NAME"

# 获取 IPv6（WAN 公网地址）
:global PUB6 ""
:foreach i in=[/ipv6/address/print as-value] do={
    :if (($i->"interface" = "pppoe-out1") && ([:pick ($i->"address") 0 4] != "fe80")) do={
        :set PUB6 ($i->"address")
    }
}

:if ($PUB6 != "") do={
    # 去掉 /64 后缀
    :set PUB6 [:pick $PUB6 0 [:find $PUB6 "/"]]
    # 记录上一次 IP
    :global LAST6
    # 如果 IPv6 变化才更新
    :if ($PUB6 != $LAST6) do={
        # Cloudflare API 更新请求
        :log info ("CF-DDNS: IPv6 changed to $PUB6, updating...")

        :local url ("https://api.cloudflare.com/client/v4/zones/" . $CFZoneID . "/dns_records/" . $CFRecordID)

        /tool fetch url=$url http-method=put mode=https check-certificate=no output=none \
            http-header-field="Authorization: Bearer $CFAPITOKEN,Content-Type: application/json" \
            http-data=("{\"type\":\"AAAA\",\"name\":\"" . $CFDNSNAME . "\",\"content\":\"" . $PUB6 . "\",\"ttl\":120,\"proxied\":false}")
        # 更新 LAST6 变量
        :set LAST6 $PUB6
        :log info "CF-DDNS: Update successful → $PUB6"
    } else={
        :log info "CF-DDNS: IPv6 not changed ($PUB6), skipping update"
    }
}
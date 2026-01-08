# RouterOS DNSPod DDNS IPv6 Script

这是一个 RouterOS 脚本，用于将公网 IPv6 地址更新到腾讯云 DNSPod 的 DNS 记录，实现动态 DDNS 功能。适用于 [Mikrotik](https://mikrotik.com/) RouterOS v7 路由器。

当然 RouterOS 本身也有 [Cloud](https://help.mikrotik.com/docs/spaces/ROS/pages/97779929/Cloud#Cloud-DDNS) DDNS 服务，自己按需使用就好。

## 特性

- **全自动维护**：脚本会自动查询现有记录 ID。如果记录不存在，将自动创建。
- **智能 IPv6 获取**：自动扫描全系统所有接口，寻找真正的 **Global Unicast Address**（全球单播地址），排除 `fe80::` (Link-Local) 等非公网地址。
- **支持 Prefix Delegation**：完美支持运营商通过 PD 模式分配到内网网桥（bridge）或其他接口的公网 IPv6。
- **变动检测**：仅在 IPv6 地址发生实质性变化时才会发起 API 请求。
- **增强日志**：在 RouterOS 日志中记录详细的 API 响应结果，方便排查。
- **兼容性强**：适用于 RouterOS 7.x，使用常用的 DNSPod API v1。

## 使用方法

1. 下载 `routeros-dnspod-ddns-ipv6.rsc` 到本地。
2. 替换脚本中的 DNSPod 核心参数：

```routeros
:global DPToken "你的 ID,Token"
:global DPDomain "example.com"
:global DPSubDomain "home"
```

* **DPToken** - DNSPod API Token。格式为 `ID,Token`。您可以在腾讯云 [DNSPod 密钥管理](https://console.dnspod.cn/account/token/token) 中创建。
* **DPDomain** - 您的主域名（例如 `example.com`）。
* **DPSubDomain** - 您的子域名（例如 `home`）。

> **注意**：脚本能够自动提取 `RecordID`。如果您之前从未手动创建过该子域名的 AAAA 记录，脚本在第一次运行时会自动为您创建。

3. 设置定时任务，每 5 分钟自动更新：
```routeros
/system scheduler add name=DNSPodDDNS interval=5m on-event="/system script run routeros-dnspod-ddns-ipv6"
```

## 日志查看

在 WinBox 或 WebFig 中打开 **Log**。
- 成功更新：`DNSPod-DDNS: Success! Result: ...`
- 已是最新：`DNSPod-DDNS: IPv6 has not changed, skipping.`
- API 报错：会在日志中打印具体的 JSON 错误信息。

## 获取 DNSPod Token (DPToken)

1. 登录 [DNSPod 控制台](https://console.dnspod.cn/)。
2. 进入“账号中心” -> “密钥管理”。
3. 创建 API 密钥，记下 ID 和 Token，脚本中填入格式为 `ID,Token`。

## 参考项目
[bajodel/mikrotik-cloudflare-dns](https://github.com/bajodel/mikrotik-cloudflare-dns)

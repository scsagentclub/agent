---
name: mijia-smart-home-mcp
title: 米家智能家居 MCP 集成
description: 部署 Xiaomi Mi Home (Mijia) MCP 服务器并集成到 Hermes Agent，实现通过自然语言控制米家设备（开关灯、调空调、查传感器、执行场景）
version: 1.0.0
author: Hermes Agent
tags: [mijia, xiaomi, mi-home, smart-home, mcp, iot]
dependencies: [python-miio or mijiaAPI]
platforms: [linux]
---

# 米家智能家居 MCP 集成

## 概述

将米家设备控制能力注入 Hermes Agent，让用户可以通过自然语言控制米家设备。

## 前提条件

- 米家账号（手机号/邮箱）
- 服务器能访问外网（小米云API需要）
- Python 3.10+

## 实施方案

### 方案 A：使用 mcp-mijia 项目（推荐）

使用 GitHub 上的 [oujiafan/mcp-mijia](https://github.com/oujiafan/mcp-mijia) 项目，它封装了 `mijiaAPI` 库并提供 MCP 接口。

### 安装步骤

```bash
# 1. 克隆仓库
git clone https://github.com/oujiafan/mcp-mijia.git ~/.hermes/mcp-mijia
cd ~/.hermes/mcp-mijia

# 2. 创建虚拟环境并安装依赖
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

### 认证方式

mcp-mijia **只支持二维码登录**（mijiaAPI 库没有密码登录接口）。

#### 二维码登录流程

1. 生成二维码并保存为图片：

```python
import qrcode
from urllib import parse
from PIL import Image
from mijiaAPI import mijiaAPI
import requests, time, json

api = mijiaAPI()
location_data = api._get_location()
location_data.update({
    "theme": "", "bizDeviceType": "", "_hasLogo": "false",
    "_qrsize": "240", "_dc": str(int(time.time() * 1000)),
})

url = api.login_url + "?" + parse.urlencode(location_data)
headers = {"User-Agent": api.user_agent}
login_ret = requests.get(url, headers=headers)
login_data = api._handle_ret(login_ret)

# ⚠️ 关键: QR码内容必须是 loginUrl，不是 qr_pic_url
login_url = login_data["loginUrl"]
lp_url = login_data["lp"]

qr = qrcode.QRCode(border=1, box_size=10)
qr.add_data(login_url)
qr.make(fit=True)
img = qr.make_image(fill_color="black", back_color="white")
img.save("mijia_qrcode.png")
```

2. 把图片放到用户能访问的地方（如文件穿梭仓、微信发送）。
3. 用米家App扫描二维码。
4. 在后台轮询 `lp_url` 等待扫码结果。
5. 获取到 token 后保存至 `~/.config/mijia-api/auth.json`。

> **⚠️ 二维码有效期约1-2分钟**，从生成到扫码需尽快完成。

### 认证文件位置

mijiaAPI 的认证文件默认路径：
```
~/.config/mijia-api/auth.json
```

格式示例：
```json
{
  "userId": "12345678",
  "serviceToken": "xxx",
  "ssecurity": "xxx",
  "nonce": "xxx",
  "passToken": "xxx",
  "cUserId": "xxx",
  "psecurity": "xxx",
  "expireTime": 1700000000000
}
```

### 密码登录不可行的原因

小米账号系统在检测到新设备/异地登录时会触发**二次验证**（securityStatus=16），返回 `notificationUrl`。此时需要：
1. 手机上米家App确认登录
2. 或扫码二维码（推荐方式）

不能直接通过账号密码绕过。

### 配置到 Hermes Agent

```yaml
# ~/.hermes/config.yaml
mcp_servers:
  mijia:
    command: /home/ubuntu/.hermes/mcp-mijia/venv/bin/python
    args: ["-m", "mijia"]
    workdir: "/home/ubuntu/.hermes/mcp-mijia"
    env:
      PYTHONPATH: "/home/ubuntu/.hermes/mcp-mijia"
    timeout: 30
```

> **⚠️ 关键配置要点：**
> - `command` 必须指向虚拟环境的 Python 解释器（`venv/bin/python`），不是系统 Python
> - 必须设置 `PYTHONPATH` 指向项目目录，因为 Hermes Agent 的 MCP 客户端会过滤环境变量，不会自动设置
> - `timeout` 建议设 30s 以上，首次启动需加载库
> - 如果 command 用系统 Python，会报 `No module named mijia`（即使虚拟环境已安装）
> - 如果缺 `PYTHONPATH`，会报导入模块失败的错误

### 验证

```bash
cd ~/.hermes/mcp-mijia
source venv/bin/activate
python3 -c "
from mijiaAPI import mijiaAPI
api = mijiaAPI()
api._init_session()
homes = api.get_homes_list()
print('家庭:', json.dumps(homes, indent=2, ensure_ascii=False))
"
```

## 可用的 MCP 工具

| 工具 | 功能 |
|------|------|
| `mcp_mijia_list_homes` | 列出所有家庭 |
| `mcp_mijia_list_devices` | 列出设备（可按家庭过滤） |
| `mcp_mijia_list_device_capabilities` | 查询设备能力 |
| `mcp_mijia_get_device_properties` | 获取设备所有属性 |
| `mcp_mijia_get_device_property` | 获取单个属性值 |
| `mcp_mijia_set_device_property` | 设置属性值 |
| `mcp_mijia_run_device_action` | 运行动作 |
| `mcp_mijia_control_device` | 高级控制：on/off/toggle/property=value |
| `mcp_mijia_list_scenes` | 列出场景 |
| `mcp_mijia_run_scene` | 执行场景 |

## 已知坑点

1. **二维码内容必须是 loginUrl，不是 qr_url** — `login_data[\"loginUrl\"]` 是小米认证链接，`login_data[\"qr\"]` 只是二维码图片的URL网址，两者不同。米家App扫描时需要的是前者。
2. **mijiaAPI 库初始化时会自动打印ASCII二维码到stdout** — 如果要在后台运行，需要设置 logging 级别或重定向输出。
3. **认证文件有效期30天** — Token过期后需要重新扫码。
4. **账号密码无法直接登录** — 小米强制新设备二次验证，只能扫码。
5. **服务端环境限制** — 浏览器（Chrome）在无桌面环境的Linux服务器上无法启动（sandbox问题），所以不能用浏览器自动化方式扫码。
6. **Native MCP 工具需重启 agent 才可见** — 在 config.yaml 添加 `mcp_servers.mijia` 后，当前 Hermes Agent 会话不会自动发现该 MCP 的工具。需要在会话中执行 `/reload-mcp` 命令或重启 agent 才能看到 `mcp_mijia_*` 工具。
7. **设备属性名因品牌而异** — OPPLE Smart Light S 这类设备使用 `on`（而非 `power`）作为电源属性。直接操作时注意：
   - 属性 `power` 不存在 → 用 `on` 代替
   - 设值：`device.set("on", True)` 或 `device.set("on", False)`
   - toggle 动作：`device.run_action("toggle")` 无论当前状态，自动翻转
   - 亮度属性名：`brightness`

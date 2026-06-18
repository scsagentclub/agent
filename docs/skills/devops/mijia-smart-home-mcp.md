---
name: mijia-smart-home-mcp
title: 米家智能家居 MCP 集成
description: 一键部署 Xiaomi Mi Home (Mijia) MCP 服务器并集成到 Hermes Agent，实现通过自然语言控制米家设备
version: 2.0.0
author: scsagentclub
tags: [mijia, xiaomi, mi-home, smart-home, mcp, iot, automation]
dependencies: [python3, git, mijiaAPI]
platforms: [linux]
setup: bash docs/skills/devops/scripts/setup.sh
---

# 米家智能家居 MCP 集成

> 🏠 **Clone 即用** — 一条命令完成安装、认证、配置

## 快速开始

```bash
# 1. 克隆仓库
git clone https://github.com/scsagentclub/agent.git
cd agent

# 2. 一键部署（交互式，会引导扫码认证）
bash docs/skills/devops/scripts/setup.sh

# 3. 重启 Hermes Agent
# 之后就可以用自然语言控制米家设备了
```

也可全自动安装：

```bash
bash docs/skills/devops/scripts/setup.sh --auto
```

## 文件结构

```
docs/skills/devops/
├── mijia-smart-home-mcp.md     ← 本文档
└── scripts/
    ├── setup.sh                ← 一键部署脚本（主入口）
    └── auth_helper.py          ← 二维码认证助手
```

## setup.sh 做了什么

`setup.sh` 执行以下步骤：

| 步骤 | 说明 |
|------|------|
| ① 检查依赖 | git、python3、python3-venv 是否就绪 |
| ② 克隆 MCP 项目 | 从 [oujiafan/mcp-mijia](https://github.com/oujiafan/mcp-mijia) 拉取代码 |
| ③ 创建虚拟环境 | 独立 venv，安装 mijiaAPI 依赖 |
| ④ 二维码认证 | 调用 `auth_helper.py` 显示二维码，引导扫码登录 |
| ⑤ 写入配置 | 自动写入 `~/.hermes/config.yaml` 的 `mcp_servers.mijia` |
| ⑥ 验证 | 检查虚拟环境、认证文件、配置是否生效 |

## 手动步骤（不推荐）

如果不想用一键脚本，也可参照以下步骤：

### 1. 克隆 MCP 项目

```bash
git clone https://github.com/oujiafan/mcp-mijia.git ~/.hermes/mcp-mijia
cd ~/.hermes/mcp-mijia
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

### 2. 二维码认证

```bash
python3 auth_helper.py
```

或者手工生成二维码（Python）：

```python
import qrcode
from urllib import parse
from PIL import Image
from mijiaAPI import mijiaAPI
import requests, time

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

> **⚠️ 二维码有效期约1-2分钟**，从生成到扫码需尽快完成。

### 3. 手动配置 Hermes Agent

```yaml
# ~/.hermes/config.yaml
mcp_servers:
  mijia:
    command: /home/yourname/.hermes/mcp-mijia/venv/bin/python
    args: ["-m", "mijia"]
    workdir: "/home/yourname/.hermes/mcp-mijia"
    env:
      PYTHONPATH: "/home/yourname/.hermes/mcp-mijia"
    timeout: 30
```

> **⚠️ 关键配置要点：**
> - `command` 必须指向虚拟环境的 Python 解释器（`venv/bin/python`），不是系统 Python
> - 必须设置 `PYTHONPATH` 指向项目目录，因为 Hermes Agent 的 MCP 客户端会过滤环境变量
> - `timeout` 建议 30s 以上，首次启动需加载库

### 4. 验证安装

```bash
cd ~/.hermes/mcp-mijia
source venv/bin/activate
python3 -c "
from mijiaAPI import mijiaAPI
import json
api = mijiaAPI()
api._init_session()
homes = api.get_homes_list()
print('家庭:', json.dumps(homes, indent=2, ensure_ascii=False))
"
```

## 认证说明

### 认证文件位置

```
~/.config/mijia-api/auth.json
```

### 认证文件格式

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

### 为什么不能用账号密码登录？

小米账号系统在检测到新设备/异地登录时会触发**二次验证**（securityStatus=16），返回 `notificationUrl`。此时需要：
1. 手机上米家App确认登录
2. 或扫码二维码（推荐方式）

不能直接通过账号密码绕过。

### Token 过期怎么办？

认证文件有效期约30天。过期后重新运行：

```bash
bash docs/skills/devops/scripts/setup.sh
```

或仅运行认证助手：

```bash
python3 docs/skills/devops/scripts/auth_helper.py
```

## 可用的 MCP 工具

成功注册后，Hermes Agent 会加载以下工具：

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
| `mcp_mijia_list_scenes` | 列出场景/自动化 |
| `mcp_mijia_run_scene` | 执行场景/自动化 |

## 使用示例

```
💬 "打开客厅灯"
💬 "关闭主卧的灯"
💬 "把餐厅灯亮度调到50%"
💬 "打开空调，设为26度"
💬 "家里的温度是多少？"
💬 "执行离家模式"
```

## 已知坑点

1. **二维码内容必须是 loginUrl，不是 qr_url** — `login_data["loginUrl"]` 是小米认证链接，`login_data["qr"]` 只是二维码图片的URL，两者不同。米家App扫描时需要的是前者。
2. **mijiaAPI 库初始化时会自动打印ASCII二维码到stdout** — 如果要在后台运行，需要设置 logging 级别或重定向输出。
3. **认证文件有效期约30天** — Token过期后需要重新扫码。
4. **账号密码无法直接登录** — 小米强制新设备二次验证，只能扫码。
5. **服务端环境限制** — 在无桌面环境的Linux服务器上，Chrome无法正常启动（sandbox问题），所以不能用浏览器自动化方式扫码。
6. **Native MCP 工具需重启 agent 才可见** — 在 config.yaml 添加 `mcp_servers.mijia` 后，当前 Hermes Agent 会话不会自动发现该 MCP 的工具。需要重启 agent 才能看到 `mcp_mijia_*` 工具。
7. **设备属性名因品牌而异** — OPPLE Smart Light S 这类设备使用 `on`（而非 `power`）作为电源属性。直接操作时注意：
   - 属性 `power` 不存在 → 用 `on` 代替
   - 设值：`device.set("on", True)` 或 `device.set("on", False)`
   - toggle 动作：`device.run_action("toggle")` 无论当前状态，自动翻转
   - 亮度属性名：`brightness`

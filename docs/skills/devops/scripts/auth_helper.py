#!/usr/bin/env python3
"""
米家 MCP 二维码认证助手
一键生成二维码并轮询扫码结果

用法:
  python3 auth_helper.py                     # 默认路径
  python3 auth_helper.py --output qr.png     # 指定二维码输出路径
  python3 auth_helper.py --auto-qr           # 自动打开二维码图片
"""

import qrcode
import sys
import os
import time
import json
import tempfile
import webbrowser
from urllib import parse
from io import BytesIO

try:
    from PIL import Image
except ImportError:
    Image = None

try:
    from mijiaAPI import mijiaAPI
except ImportError:
    print("❌ 请先安装 mijiaAPI: pip install mijiaAPI")
    sys.exit(1)

# ─── 默认认证文件路径 ───
DEFAULT_AUTH_PATH = os.path.expanduser("~/.config/mijia-api/auth.json")


def generate_qrcode(api):
    """生成登录二维码，返回 loginUrl 和 lp_url"""
    location_data = api._get_location()
    location_data.update({
        "theme": "",
        "bizDeviceType": "",
        "_hasLogo": "false",
        "_qrsize": "240",
        "_dc": str(int(time.time() * 1000)),
    })

    import requests
    url = api.login_url + "?" + parse.urlencode(location_data)
    headers = {"User-Agent": api.user_agent}
    login_ret = requests.get(url, headers=headers)
    login_data = api._handle_ret(login_ret)

    login_url = login_data["loginUrl"]
    lp_url = login_data["lp"]

    return login_url, lp_url


def show_qrcode_text(login_url):
    """用字符画显示二维码"""
    qr = qrcode.QRCode(border=1, box_size=2)
    qr.add_data(login_url)
    qr.make(fit=True)
    qr.print_ascii(invert=True)
    print()


def save_qrcode_image(login_url, output_path=None):
    """保存二维码为图片文件"""
    if Image is None:
        return None

    qr = qrcode.QRCode(border=1, box_size=10)
    qr.add_data(login_url)
    qr.make(fit=True)
    img = qr.make_image(fill_color="black", back_color="white")

    if output_path:
        img.save(output_path)
        return output_path
    else:
        # 保存到临时文件
        fd, path = tempfile.mkstemp(suffix=".png", prefix="mijia_qr_")
        os.close(fd)
        img.save(path)
        return path


def poll_for_result(api, lp_url, timeout=120):
    """轮询扫码结果，timeout 秒超时"""
    print(f"⏳ 等待扫码...（最长等待 {timeout} 秒）")
    print("📱 请用米家 App 扫描上面的二维码")
    print()

    import requests
    start = time.time()
    while time.time() - start < timeout:
        result = requests.get(
            api.login_url + lp_url,
            headers={"User-Agent": api.user_agent},
        )
        data = api._handle_ret(result)

        if "location" in data:
            # 扫码成功，获取 token
            service_ret = requests.get(
                data["location"],
                headers={"User-Agent": api.user_agent},
            )
            api._service_token(api._handle_ret(service_ret))
            print("✅ 扫码成功！")
            return True

        elif "code" in data:
            code = data.get("code")
            if code == 0:
                # 未扫码，继续等
                elapsed = int(time.time() - start)
                sys.stdout.write(f"\r⏳ 等待中... {elapsed}s")
                sys.stdout.flush()
                time.sleep(2)
            elif code in (2001, 2004):
                print(f"\n❌ 二维码已过期，请重新运行此脚本")
                return False
            elif code == 2002:
                print(f"\n❌ 扫码取消")
                return False
            else:
                print(f"\n❌ 未知错误: {data}")
                return False
        else:
            time.sleep(2)

    print(f"\n⏰ 超时！{timeout} 秒内未完成扫码")
    return False


def save_auth(api, path=None):
    """保存认证文件"""
    path = path or DEFAULT_AUTH_PATH
    os.makedirs(os.path.dirname(path), exist_ok=True)

    # mijiaAPI 内部维护的 auth_data
    auth_data = {
        "userId": api.account.userId,
        "serviceToken": api.account.serviceToken,
        "ssecurity": api.account.ssecurity,
        "nonce": api.account.nonce,
        "passToken": getattr(api.account, 'passToken', ''),
        "cUserId": getattr(api.account, 'cUserId', ''),
        "psecurity": getattr(api.account, 'psecurity', ''),
    }

    # 如果有 expireTime 则加上
    expire = getattr(api.account, 'expireTime', None)
    if expire:
        # 兼容 int 和 datetime
        if hasattr(expire, 'timestamp'):
            expire = int(expire.timestamp() * 1000)
        auth_data["expireTime"] = int(expire)

    with open(path, "w") as f:
        json.dump(auth_data, f, indent=2, ensure_ascii=False)

    print(f"💾 认证文件已保存: {path}")


def main():
    import argparse
    parser = argparse.ArgumentParser(description="米家 MCP 二维码认证助手")
    parser.add_argument("--output", "-o", help="二维码图片保存路径")
    parser.add_argument("--auto-qr", action="store_true", help="自动打开二维码图片")
    parser.add_argument("--timeout", type=int, default=120, help="扫码等待超时秒数（默认: 120）")
    args = parser.parse_args()

    print()
    print("╔═══════════════════════════════════╗")
    print("║     米家 MCP 二维码认证助手        ║")
    print("╚═══════════════════════════════════╝")
    print()

    # 初始化 API
    print("📡 初始化米家 API...")
    api = mijiaAPI()

    # 生成二维码
    print("📟 生成登录二维码...")
    login_url, lp_url = generate_qrcode(api)

    # 显示字符二维码
    show_qrcode_text(login_url)

    # 保存图片
    img_path = save_qrcode_image(login_url, args.output)
    if img_path:
        print(f"🖼️  二维码图片: {img_path}")
        if args.auto_qr:
            try:
                webbrowser.open(f"file://{img_path}")
                print("🖥️  已自动打开二维码图片")
            except Exception:
                pass

    print()

    # 轮询扫码
    if poll_for_result(api, lp_url, timeout=args.timeout):
        save_auth(api)
        print()
        print("✅ 认证完成！现在可以重启 Hermes Agent 使用米家设备控制功能了。")
        print()
    else:
        print()
        print("❌ 认证失败")
        sys.exit(1)


if __name__ == "__main__":
    main()

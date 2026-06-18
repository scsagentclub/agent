#!/usr/bin/env bash
# =============================================================
# 米家智能家居 MCP 一键部署脚本
# 用于 scsagentclub/agent 仓库
#
# 用法:
#   bash setup.sh                    # 交互式安装
#   bash setup.sh --auto             # 自动安装（默认路径）
#   bash setup.sh --help             # 查看帮助
# =============================================================
set -euo pipefail

# ─── 颜色 ───
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

info()  { echo -e "${CYAN}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()   { echo -e "${RED}[ERR]${NC} $1"; }
header(){ echo -e "\n${BOLD}━━━ $1 ━━━${NC}\n"; }

# ─── 默认路径 ───
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
MCP_DIR="${MCP_DIR:-$HERMES_HOME/mcp-mijia}"
VENV_DIR="$MCP_DIR/venv"
MCP_PROJECT="https://github.com/oujiafan/mcp-mijia.git"
AUTH_FILE="$HOME/.config/mijia-api/auth.json"
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── 帮助 ───
show_help() {
    cat <<EOF
米家智能家居 MCP 一键部署脚本

用法:
  bash setup.sh                交互式安装
  bash setup.sh --auto         自动安装（默认路径）
  bash setup.sh --auto --hermes /path/to/.hermes  指定 Hermes 目录

环境变量:
  HERMES_HOME   Hermes Agent 配置目录（默认: ~/.hermes）
  MCP_DIR       MCP 代码安装目录（默认: \$HERMES_HOME/mcp-mijia）

说明:
  此脚本会:
    1. 克隆 oujiafan/mcp-mijia 项目
    2. 创建 Python 虚拟环境并安装依赖
    3. 运行二维码认证助手引导登录
    4. 自动写入 Hermes Agent 的 config.yaml
EOF
    exit 0
}

# ─── 参数解析 ───
AUTO=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --auto )    AUTO=true; shift ;;
        --hermes )  HERMES_HOME="$2"; shift 2 ;;
        --help )    show_help ;;
        * )         err "未知参数: $1"; show_help ;;
    esac
done

CONFIG_FILE="$HERMES_HOME/config.yaml"

# ─── 检查依赖 ───
check_prereqs() {
    header "检查系统依赖"

    if ! command -v git &>/dev/null; then
        err "git 未安装，请先安装 git"
        exit 1
    fi
    ok "git ✓"

    if ! command -v python3 &>/dev/null; then
        err "Python 3 未安装"
        exit 1
    fi
    PY_VERSION=$(python3 --version 2>&1 | cut -d' ' -f2)
    ok "Python $PY_VERSION ✓"

    # 检查 python3-venv
    if ! python3 -c "import venv" &>/dev/null 2>&1; then
        warn "Python venv 模块缺失，尝试安装..."
        if command -v apt-get &>/dev/null; then
            sudo apt-get update -qq && sudo apt-get install -y -qq python3-venv python3-pip
        elif command -v yum &>/dev/null; then
            sudo yum install -y -q python3-venv python3-pip
        else
            err "无法自动安装 python3-venv，请手动安装后重试"
            exit 1
        fi
        ok "python3-venv 已安装"
    fi
    ok "python3-venv ✓"

    # 检查 pip
    if ! command -v pip3 &>/dev/null && ! python3 -m pip --version &>/dev/null 2>&1; then
        warn "pip3 未安装，尝试安装..."
        sudo apt-get install -y -qq python3-pip || sudo yum install -y -q python3-pip
    fi
    ok "pip3 ✓"
}

# ─── 克隆 MCP 项目 ───
clone_project() {
    header "克隆 mcp-mijia 项目"

    if [[ -d "$MCP_DIR/.git" ]]; then
        info "项目已存在，拉取最新代码..."
        cd "$MCP_DIR" && git pull
    else
        info "克隆到 $MCP_DIR ..."
        if [[ -d "$MCP_DIR" ]]; then
            warn "目录 $MCP_DIR 已存在但非 git 仓库，备份到 ${MCP_DIR}.bak"
            mv "$MCP_DIR" "${MCP_DIR}.bak"
        fi
        git clone "$MCP_PROJECT" "$MCP_DIR"
    fi
    ok "mcp-mijia 项目就绪 ✅"
}

# ─── 创建虚拟环境 ───
setup_venv() {
    header "创建 Python 虚拟环境"

    if [[ -d "$VENV_DIR" ]]; then
        info "虚拟环境已存在，跳过创建"
    else
        python3 -m venv "$VENV_DIR"
        ok "虚拟环境已创建"
    fi

    info "安装依赖..."
    "$VENV_DIR/bin/pip" install --upgrade pip -q
    "$VENV_DIR/bin/pip" install -r "$MCP_DIR/requirements.txt" -q
    ok "依赖安装完成 ✅"
}

# ─── 二维码认证 ───
do_auth() {
    header "米家账号认证"

    if [[ -f "$AUTH_FILE" ]]; then
        info "检测到已有认证文件：$AUTH_FILE"
        # 检查是否过期
        EXPIRE=$(python3 -c "import json; f=open('$AUTH_FILE'); d=json.load(f); print(d.get('expireTime', 0))" 2>/dev/null || echo 0)
        NOW=$(date +%s%3N)
        if [[ "$EXPIRE" -gt "$NOW" ]]; then
            ok "认证文件有效 ✅"
            return 0
        else
            warn "认证文件已过期，重新认证..."
        fi
    fi

    info "运行认证助手..."
    "$VENV_DIR/bin/python3" "$SCRIPTS_DIR/auth_helper.py"
    echo ""
    info "扫码完成后按回车继续..."
    read -r
    echo ""

    if [[ -f "$AUTH_FILE" ]]; then
        ok "认证成功 ✅"
    else
        err "认证失败，未检测到 $AUTH_FILE"
        exit 1
    fi
}

# ─── 写入 Hermes Config ───
write_config() {
    header "写入 Hermes Agent 配置"

    if [[ ! -f "$CONFIG_FILE" ]]; then
        info "config.yaml 不存在，创建..."
        mkdir -p "$(dirname "$CONFIG_FILE")"
        echo "mcp_servers:" > "$CONFIG_FILE"
    fi

    # 检查是否已配过
    if grep -q "mcp_servers:" "$CONFIG_FILE" 2>/dev/null && grep -q "mijia:" <(grep -A1 "mcp_servers:" "$CONFIG_FILE" 2>/dev/null || echo ""); then
        # 更精确检查：看 mcp_servers 下是否有 mijia 条目
        EXISTING=$(python3 -c "
import yaml
try:
    with open('$CONFIG_FILE') as f:
        cfg = yaml.safe_load(f)
    if cfg and 'mcp_servers' in cfg and 'mijia' in cfg['mcp_servers']:
        print('found')
    else:
        print('not_found')
except:
    print('not_found')
" 2>/dev/null || echo "not_found")

        if [[ "$EXISTING" == "found" ]]; then
            info "config.yaml 中已存在 mijia 配置，跳过写入"
            ok "配置就绪 ✅"
            return 0
        fi
    fi

    # 用 Python 写入 YAML（避免手动拼串出错）
    "$VENV_DIR/bin/python3" -c "
import yaml, sys, os

config_path = '$CONFIG_FILE'
mcp_dir = '$MCP_DIR'
venv_python = '$VENV_DIR/bin/python'

# 读取现有配置
if os.path.exists(config_path) and os.path.getsize(config_path) > 0:
    with open(config_path) as f:
        cfg = yaml.safe_load(f) or {}
else:
    cfg = {}

if 'mcp_servers' not in cfg:
    cfg['mcp_servers'] = {}

cfg['mcp_servers']['mijia'] = {
    'command': venv_python,
    'args': ['-m', 'mijia'],
    'workdir': mcp_dir,
    'env': {
        'PYTHONPATH': mcp_dir
    },
    'timeout': 30
}

with open(config_path, 'w') as f:
    yaml.dump(cfg, f, default_flow_style=False, sort_keys=False, allow_unicode=True)

print('config written')
" 2>&1

    ok "MCP 配置已写入 $CONFIG_FILE ✅"
    info "提示：需重启 Hermes Agent 后 mcp_mijia_* 工具才在当前会话可见"
}

# ─── 验证 ───
verify() {
    header "验证安装"

    info "检查虚拟环境..."
    if "$VENV_DIR/bin/python3" -c "import mijiaAPI" 2>/dev/null; then
        ok "mijiaAPI 导入成功 ✅"
    else
        err "mijiaAPI 导入失败，请检查依赖安装"
        exit 1
    fi

    info "检查认证文件..."
    if [[ -f "$AUTH_FILE" ]]; then
        EXPIRE=$(python3 -c "import json; f=open('$AUTH_FILE'); d=json.load(f); print(d.get('expireTime', 0))" 2>/dev/null || echo 0)
        NOW=$(date +%s%3N)
        if [[ "$EXPIRE" -gt "$NOW" ]]; then
            ok "认证有效 ✅"
        else
            warn "认证文件已过期，需重新扫码"
        fi
    else
        warn "未检测到认证文件，后续需手动扫码认证"
    fi

    info "检查 Hermes 配置..."
    if grep -q "mijia" "$CONFIG_FILE" 2>/dev/null; then
        ok "Hermes 配置已写入 ✅"
    else
        warn "Hermes 配置未写入"
    fi

    echo ""
    echo -e "${GREEN}${BOLD}========================================${NC}"
    echo -e "${GREEN}${BOLD}  米家 MCP 安装完成！${NC}"
    echo -e "${GREEN}${BOLD}========================================${NC}"
    echo ""
    echo -e "  项目目录:   ${CYAN}$MCP_DIR${NC}"
    echo -e "  虚拟环境:   ${CYAN}$VENV_DIR${NC}"
    echo -e "  认证文件:   ${CYAN}$AUTH_FILE${NC}"
    echo -e "  配置位置:   ${CYAN}$CONFIG_FILE${NC}"
    echo ""
    echo -e "  ${YELLOW}下一步: 重启 Hermes Agent 即可使用米家设备控制${NC}"
    echo -e "  ${YELLOW}  mcp_mijia_* 工具会自动加载${NC}"
    echo ""
}

# ─── 主流程 ───
main() {
    echo ""
    echo -e "${BOLD}${CYAN}╔══════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║     米家智能家居 MCP 一键部署        ║${NC}"
    echo -e "${BOLD}${CYAN}╚══════════════════════════════════════╝${NC}"
    echo ""
    info "Hermes 目录: $HERMES_HOME"
    info "MCP 安装目录: $MCP_DIR"

    check_prereqs
    clone_project
    setup_venv

    if [[ "$AUTO" == false ]]; then
        echo ""
        info "是否现在进行米家账号二维码认证？(y/N)"
        read -r DO_AUTH
        if [[ "$DO_AUTH" =~ ^[Yy] ]]; then
            do_auth
        else
            warn "跳过认证，稍后可手动运行: bash $(dirname "$0")/auth_helper.py"
        fi
    else
        do_auth
    fi

    write_config
    verify
}

main "$@"

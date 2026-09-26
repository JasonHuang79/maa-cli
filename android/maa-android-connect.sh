#!/usr/bin/env bash
# maa-android-connect —— 在 Termux 里把 MAA 自动连到本机 adb
#
# 为什么需要它：在 Android 本机跑 MAA，MaaCore 只能通过 adb 连游戏（原生控制需要
# Android App 运行时，Termux 拿不到）。而手动连 adb 很繁琐：
# 要开无线调试、要 adb pair 输配对码、端口每次还可能变。
# 本脚本按「成功率从高到低」依次尝试，免去手动操作。
#
# 用法：
#   ./maa-android-connect.sh            # 自动尝试所有方式
#   ./maa-android-connect.sh --root     # 只试 root 方式（设固定端口）
#   ./maa-android-connect.sh --mdns     # 只试 mDNS 发现（已配对过的设备）
#   ./maa-android-connect.sh --verbose  # 打印更多过程
#
# 退出码：0 = 已连上；1 = 全部失败（会打印手动步骤）

set -uo pipefail

# ── 常见端口（部分设备/模拟器会监听这些）────────────────────────
COMMON_PORTS="5555 5556 5557 7555 16384 16385"

ONLY=""
VERBOSE=0
for arg in "$@"; do
    case "$arg" in
        --root) ONLY="root" ;;
        --mdns) ONLY="mdns" ;;
        --verbose) VERBOSE=1 ;;
        -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
        *) echo "未知参数：$arg（用 --help 查看用法）" >&2; exit 2 ;;
    esac
done

C_RESET=$'\033[0m'; C_CYAN=$'\033[36m'; C_GREEN=$'\033[32m'
C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'
log()  { printf '%s[*]%s %s\n' "$C_CYAN" "$C_RESET" "$*"; }
ok()   { printf '%s[+]%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%s[!]%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
err()  { printf '%s[x]%s %s\n' "$C_RED" "$C_RESET" "$*"; }
trace() { [ "$VERBOSE" -eq 1 ] && printf '    %s\n' "$*"; return 0; }

# ── 前置检查 ────────────────────────────────────────────────────
if ! command -v adb >/dev/null 2>&1; then
    err "未找到 adb。请先安装：pkg install -y android-tools"
    exit 1
fi

# 已有可用设备就直接收工
connected() {
    adb devices 2>/dev/null | awk 'NR>1 && $2=="device" { n++ } END { exit !(n>0) }'
}
show_devices() {
    adb devices 2>/dev/null | sed 's/^/    /'
}

if connected; then
    ok "已有可用的 adb 设备，无需重连"
    show_devices
    exit 0
fi
log "当前没有可用设备，开始尝试自动连接"

# ── 方式 1：mDNS 发现（无需 root，但要求之前配对过）──────────────
try_mdns() {
    log "方式 1：mDNS 发现无线调试服务"
    command -v adb >/dev/null || return 1

    # 启动本地 adb server（mdns 发现需要它）
    adb start-server >/dev/null 2>&1

    local found
    found="$(adb mdns services 2>/dev/null \
             | awk '$2 ~ /_adb-tls-connect/ { print $3 }' | head -5)"
    trace "发现的服务：${found:-（无）}"

    if [ -z "$found" ]; then
        warn "未发现无线调试服务（可能未开启无线调试，或此前未配对过）"
        return 1
    fi

    local addr
    while read -r addr; do
        [ -n "$addr" ] || continue
        log "尝试连接 $addr"
        adb connect "$addr" >/dev/null 2>&1
        sleep 1
        if connected; then
            ok "已通过 mDNS 连接到 $addr"
            show_devices
            return 0
        fi
    done <<< "$found"

    warn "mDNS 发现的地址均未能连接（多半是尚未配对，需先 adb pair）"
    return 1
}

# ── 方式 2：root 设固定端口（最可靠，但需要 su）──────────────────
have_root() {
    command -v su >/dev/null 2>&1 || return 1
    su -c id 2>/dev/null | grep -q 'uid=0'
}

try_root() {
    log "方式 2：使用 root 设固定 adb 端口"

    if ! have_root; then
        warn "没有可用的 su（root），跳过"
        return 1
    fi

    # 注意：重启 adbd 会短暂断开现有 adb 连接，故放在此处（前面已确认无设备）
    log "设置 service.adb.tcp.port=5555 并重启 adbd"
    su -c 'setprop service.adb.tcp.port 5555' 2>/dev/null
    if ! su -c 'setprop ctl.restart adbd' 2>/dev/null; then
        # 部分设备不支持 ctl.restart，退回 stop/start
        trace "ctl.restart 不可用，改用 stop/start"
        su -c 'stop adbd' 2>/dev/null
        sleep 1
        su -c 'start adbd' 2>/dev/null
    fi

    # 等 adbd 起来
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        sleep 1
        adb connect 127.0.0.1:5555 >/dev/null 2>&1
        if connected; then
            ok "已通过 root 连接到 127.0.0.1:5555"
            show_devices
            return 0
        fi
    done

    warn "root 方式未成功（设备可能限制 setprop adb 端口）"
    return 1
}

# ── 方式 3：扫常见端口 ──────────────────────────────────────────
try_ports() {
    log "方式 3：扫描常见 adb 端口"
    local port
    for port in $COMMON_PORTS; do
        trace "尝试 127.0.0.1:$port"
        adb connect "127.0.0.1:$port" >/dev/null 2>&1
        sleep 1
        if connected; then
            ok "已连接到 127.0.0.1:$port"
            show_devices
            return 0
        fi
    done
    warn "常见端口均不可用"
    return 1
}

# ── 依次尝试 ────────────────────────────────────────────────────
case "$ONLY" in
    root) try_root ;;
    mdns) try_mdns ;;
    *)    try_mdns || try_root || try_ports ;;
esac

if connected; then
    exit 0
fi

# ── 全部失败：给出手动步骤 ──────────────────────────────────────
echo
err "自动连接失败，请手动操作（任选一种）："

cat <<'EOF'

【A. 有 root：设固定端口（最省事）】
    su -c 'setprop service.adb.tcp.port 5555; setprop ctl.restart adbd'
    adb connect 127.0.0.1:5555

【B. 无 root：用系统「无线调试」】
    1. 打开 设置 → 开发者选项 → 无线调试
    2. 点「使用配对码配对设备」，记下 配对码 与 端口号
    3. 在 Termux 里执行（端口换成配对界面显示的）：
           adb pair 127.0.0.1:<配对端口>
       （提示输入配对码时填入）
    4. 再连接（端口看「无线调试」主界面显示的 IP 与端口）：
           adb connect 127.0.0.1:<调试端口>
    5. adb devices 确认设备为 device 状态

【C. 若以上都失败】
    - 确认已安装 android-tools：pkg install -y android-tools
    - 确认「开发者选项」已开启
    - 部分设备需要先通过 USB 连一次电脑执行 adb tcpip 5555

连上之后即可使用 maa-cli，例如：
    maa startup
    maa fight 1-7 --times 5
EOF

exit 1

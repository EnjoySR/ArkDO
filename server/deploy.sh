#!/usr/bin/env bash
# 把仓库里的 relay.py 部署到中继服务器。
#
# 以仓库为准:改中继请改本文件同目录的 relay.py 并提交,再用本脚本部署。
# 别直接改服务器上的副本——那样仓库和线上很快就对不上了。
#
# 用法: ./deploy.sh <ssh-host>            部署并重启
#       ./deploy.sh <ssh-host> --dry      只比对差异,不改动
set -euo pipefail

HOST="${1:-}"
DRY="${2:-}"
REMOTE_DIR="/opt/wp-relay"
LOCAL_PY="$(cd "$(dirname "$0")" && pwd)/relay.py"

if [ -z "$HOST" ]; then
  echo "用法: $0 <ssh-host> [--dry]" >&2
  exit 1
fi

[ -f "$LOCAL_PY" ] || { echo "找不到 $LOCAL_PY" >&2; exit 1; }

# 本地先过一遍语法,别把语法错误推上去导致服务起不来。
python3 -c "import py_compile; py_compile.compile('$LOCAL_PY', doraise=True)"
echo "✓ 本地语法检查通过"

echo "── 与线上的差异 ──"
if ssh "$HOST" "cat $REMOTE_DIR/relay.py" 2>/dev/null | diff -u - "$LOCAL_PY"; then
  echo "(无差异)"
  [ "$DRY" = "--dry" ] && exit 0
fi

if [ "$DRY" = "--dry" ]; then
  echo "--dry:仅比对,未改动。"
  exit 0
fi

read -r -p "确认部署到 $HOST ? [y/N] " ok
[ "$ok" = "y" ] || { echo "已取消"; exit 0; }

# 先备份线上版本,出问题能立刻回滚。
ssh "$HOST" "sudo cp $REMOTE_DIR/relay.py $REMOTE_DIR/relay.py.bak.\$(date +%Y%m%d_%H%M%S)"
scp "$LOCAL_PY" "$HOST:/tmp/relay-new.py"
ssh "$HOST" "sudo mv /tmp/relay-new.py $REMOTE_DIR/relay.py \
  && sudo chmod 644 $REMOTE_DIR/relay.py \
  && python3 -c \"import py_compile; py_compile.compile('$REMOTE_DIR/relay.py', doraise=True)\" \
  && sudo systemctl restart wp-relay"

sleep 2
echo "── 部署结果 ──"
ssh "$HOST" "systemctl is-active wp-relay && sudo journalctl -u wp-relay -n 3 --no-pager"
echo "✓ 完成。健康检查请访问 <RELAY_PUBLIC_BASE>/wp/health"

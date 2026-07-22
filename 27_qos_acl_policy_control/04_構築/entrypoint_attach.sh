#!/usr/bin/env bash
set -euo pipefail

IOL_PID=${IOL_PID:-513}

hostname gns3-iouvm
# ライセンス（/iol/.iourc）の扱い:
#  - イメージに有効なIOURCが焼き込まれている場合はそれを尊重し、上書きしない。
#  - 存在しない/全0（サニタイズ値）の場合のみ、プレースホルダを書き出す。
#    利用者自身のIOURC値（hostnameに対応するライセンス）に差し替えて使うこと。
#  - IOL(IOU)ライセンスはCisco proprietaryのため、この値をgit等へ公開しないこと。
if ! { [ -s /iol/.iourc ] && grep -qE 'gns3-iouvm *= *[0-9a-fA-F]+' /iol/.iourc \
       && ! grep -qE 'gns3-iouvm *= *0{16} *;' /iol/.iourc; }; then
  cat > /iol/.iourc <<'IOURC'
[license]
gns3-iouvm = 0000000000000000;
IOURC
fi
export IOURC=/iol/.iourc

ip addr flush dev eth0 2>/dev/null || true
ip -6 addr flush dev eth0 2>/dev/null || true
rm -f "/tmp/netio${IOL_PID}"* "/tmp/iol_lock_${IOL_PID}"

previous_count=0
stable_count=0
for _ in $(seq 1 30); do
  current_count=$(find /sys/class/net -maxdepth 1 -name 'eth*' | wc -l)
  if [ "$current_count" -eq "$previous_count" ] && [ "$current_count" -gt 0 ]; then
    stable_count=$((stable_count + 1))
    [ "$stable_count" -ge 3 ] && break
  else
    stable_count=0
  fi
  previous_count=$current_count
  sleep 1
done

max_eth=$(find /sys/class/net -maxdepth 1 -name 'eth*' -printf '%f\n' \
  | sed 's/^eth//' | sort -n | tail -1)
num_slots=$(( (${max_eth:-0} + 4) / 4 ))

# iouyap(ID 513)を自己修復モードで自動起動する。
# - IOLブート完了後（+60秒）に起動し、終了したら10秒おきに再起動する
# - デプロイ時・コンテナ再起動時のどちらでも配線が自動復旧する
#   （手動での ./deploy.sh iouyap 投入は不要。詳細:
#     トラブルシューティング_IOL受信不能_2026-07-10.md）
(
  sleep 60
  cd /iol
  until /usr/bin/iouyap 513; do sleep 10; done
) >/dev/null 2>&1 &

# IOLをPID1にしてdocker attachの標準入力をIOSへ直結する。
# -m 1024: RAM 1GB明示。省略時256MBはNAT/NBAR等でMALLOCFAILになる
# （26_dynamic_routing_deep_dive/04_構築/トラブルシューティング_IOL_NAT_MALLOCFAIL.md の教訓）
exec /iol/iol.bin "$IOL_PID" -e "$num_slots" -s 0 -c config.txt -m 1024 -n 1024

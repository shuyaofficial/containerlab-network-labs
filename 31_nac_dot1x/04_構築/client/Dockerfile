# 802.1X サプリカント端末（arm64）
# wpa_supplicant で有線 802.1X（EAP-MD5）を実行する。
FROM ubuntu:24.04

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      wpasupplicant iproute2 iputils-ping iptables \
    && rm -rf /var/lib/apt/lists/*

COPY wpa_supplicant.conf /etc/wpa_supplicant.conf

# clab から exec で起動制御するため、常駐だけさせる
CMD ["sleep", "infinity"]

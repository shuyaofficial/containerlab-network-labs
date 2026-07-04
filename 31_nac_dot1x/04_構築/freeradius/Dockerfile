# FreeRADIUS 認証サーバ（arm64 ネイティブ）
# 公式イメージ freeradius/freeradius-server は amd64 のみのため、
# arm64 Ubuntu ベースに apt で導入する（軽量検証結果_nwzt_2026-07-04 の方針）。
FROM ubuntu:24.04

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      freeradius freeradius-utils iproute2 iputils-ping \
    && rm -rf /var/lib/apt/lists/*

# EAP-MD5 をラボの既定 EAP 方式にする（証明書不要で 802.1X を試せる）
RUN sed -i 's/^\s*default_eap_type = .*/        default_eap_type = md5/' /etc/freeradius/3.0/mods-available/eap

COPY clients.conf /etc/freeradius/3.0/clients.conf
COPY authorize    /etc/freeradius/3.0/mods-config/files/authorize

EXPOSE 1812/udp 1813/udp 3799/udp
# -X = フォアグラウンド + 詳細ログ（学習・切り分けに有効）
CMD ["freeradius", "-X"]

# N4 マイクロセグメンテーション端末イメージ（arm64）
# 層2（ホスト分散FW）の nftables と、疎通確認用の各種ツールを載せる。
# pc10a / pc10b（クライアント）と srv20（http/tcp サーバ）で共用する。
FROM ubuntu:24.04

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      nftables \
      iproute2 \
      iputils-ping \
      curl \
      ncat \
      python3 \
      ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# srv20 で使う簡易コンテンツ（http/80 の応答本文）
RUN mkdir -p /srv/www && \
    printf 'MICROSEG-SRV20-OK\n' > /srv/www/index.html

# clab から exec で IP 設定・サーバ起動・nftables 投入を制御するため常駐だけさせる
CMD ["sleep", "infinity"]

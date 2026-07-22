# テーマ35 Faucet SDN — OVS（Open vSwitch）自前ビルドイメージ
#
# OVSの公式Dockerイメージ（openvswitch/ovs等）はarm64に対応していないため、
# Ubuntu 24.04 arm64ベースに apt パッケージの openvswitch-switch を導入した自前イメージを用意する。
# データパスは userspace（netdev）で動作させるため、カーネルモジュール（openvswitch.ko）は不要。

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        openvswitch-switch \
        openvswitch-common \
        iproute2 \
        iputils-ping \
        tcpdump \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY bootstrap.sh /usr/local/bin/bootstrap.sh
RUN chmod +x /usr/local/bin/bootstrap.sh

# bootstrap.sh が ovsdb-server / ovs-vswitchd の起動と br0 のプラミングを行い、
# 最後にフォアグラウンドでプロセスを維持する（docker attach 前提のPID1運用）。
ENTRYPOINT ["/usr/local/bin/bootstrap.sh"]

#!/bin/bash
# =============================================================================
# capstone ラボ 統合コンフィグ投入スクリプト（全6台 Cisco IOL）
# -----------------------------------------------------------------------------
#  - OrbStack の `clab` マシン内で root 実行する想定:
#       sudo bash configure_all.sh
#  - 管理IPはコンテナ名から動的解決（IPドリフトに強い）。
#  - SSHは UserKnownHostsFile=/dev/null で host key churn を無効化。
#  - 設定内容は 03_詳細設計 パラメータシート(IP/ルーティング/NAT)に準拠。
#    ※ IPsec/GRE VPN(Tunnel0) はユーザー本人が後で実施するため本スクリプトでは扱わない。
# =============================================================================

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 \
-o KexAlgorithms=+diffie-hellman-group14-sha1 -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa"
USER=admin
PASS=admin

# コンテナ名から管理IPv4を解決
getip() {
  docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "clab-capstone-$1" 2>/dev/null
}

# SSHが立ち上がるまで待機（stdin はヒアドキュメントを食べないよう /dev/null）
wait_ssh() {
  local ip=$1 name=$2 i
  for i in $(seq 1 60); do
    if sshpass -p "$PASS" ssh $SSH_OPTS "$USER@$ip" "exit" </dev/null 2>/dev/null; then
      return 0
    fi
    sleep 5
  done
  echo "[FAIL] $name ($ip): SSH not reachable"; return 1
}

# push <name>  … 標準入力(ヒアドキュメント)のコンフィグをSSHで流し込む
push() {
  local name=$1 ip
  ip=$(getip "$name")
  if [ -z "$ip" ]; then echo "[ERR] $name: cannot resolve mgmt IP"; return 1; fi
  echo ">>> Configuring $name ($ip) ..."
  wait_ssh "$ip" "$name" || return 1
  sshpass -p "$PASS" ssh $SSH_OPTS "$USER@$ip"
  echo "<<< $name done."
}

echo "===== Waiting for all devices and pushing configuration ====="

# -----------------------------------------------------------------------------
# 1) ISP（疑似インターネット）: BGP65000 + Loopback 8.8.8.8(疎通確認用 internet 役)
# -----------------------------------------------------------------------------
push isp <<'EOF'
terminal length 0
conf t
hostname isp
interface Loopback0
 ip address 8.8.8.8 255.255.255.255
 exit
interface e0/1
 ip address 200.0.1.254 255.255.255.0
 no shut
 exit
interface e0/2
 ip address 200.0.2.254 255.255.255.0
 no shut
 exit
interface e0/3
 ip address 200.0.3.254 255.255.255.0
 no shut
 exit
ip route 0.0.0.0 0.0.0.0 Null0
router bgp 65000
 bgp router-id 100.100.100.100
 neighbor 200.0.1.1 remote-as 65001
 neighbor 200.0.2.1 remote-as 65001
 network 0.0.0.0
 exit
end
write memory
EOF

# -----------------------------------------------------------------------------
# 2) HQ-Edge1: NAT(overload) + OSPF(default originate) + eBGP(local-pref 200 優先)
# -----------------------------------------------------------------------------
push hq-edge1 <<'EOF'
terminal length 0
conf t
hostname hq-edge1
interface Loopback0
 ip address 1.1.1.1 255.255.255.255
 exit
interface e0/1
 ip address 200.0.1.1 255.255.255.0
 ip nat outside
 no shut
 exit
interface e0/2
 ip address 10.0.0.1 255.255.255.252
 ip nat inside
 no shut
 exit
interface e0/3
 ip address 10.0.0.5 255.255.255.252
 ip nat inside
 no shut
 exit
access-list 100 deny ip 10.0.0.0 0.255.255.255 10.2.40.0 0.0.0.255
access-list 100 permit ip 10.0.0.0 0.255.255.255 any
ip nat inside source list 100 interface Ethernet0/1 overload
router ospf 1
 router-id 1.1.1.1
 network 10.0.0.0 0.0.0.3 area 0
 network 10.0.0.4 0.0.0.3 area 0
 default-information originate
 exit
router bgp 65001
 bgp router-id 1.1.1.1
 neighbor 200.0.1.254 remote-as 65000
 address-family ipv4
  neighbor 200.0.1.254 activate
 exit-address-family
 exit
route-map SET_LOCAL_PREF permit 10
 set local-preference 200
 exit
router bgp 65001
 address-family ipv4
  neighbor 200.0.1.254 route-map SET_LOCAL_PREF in
 exit-address-family
 exit
end
write memory
EOF

# -----------------------------------------------------------------------------
# 3) HQ-Edge2: NAT(overload) + OSPF(default originate) + eBGP(サブ回線)
# -----------------------------------------------------------------------------
push hq-edge2 <<'EOF'
terminal length 0
conf t
hostname hq-edge2
interface Loopback0
 ip address 2.2.2.2 255.255.255.255
 exit
interface e0/1
 ip address 200.0.2.1 255.255.255.0
 ip nat outside
 no shut
 exit
interface e0/2
 ip address 10.0.0.9 255.255.255.252
 ip nat inside
 no shut
 exit
interface e0/3
 ip address 10.0.0.13 255.255.255.252
 ip nat inside
 no shut
 exit
access-list 100 deny ip 10.0.0.0 0.255.255.255 10.2.40.0 0.0.0.255
access-list 100 permit ip 10.0.0.0 0.255.255.255 any
ip nat inside source list 100 interface Ethernet0/1 overload
router ospf 1
 router-id 2.2.2.2
 network 10.0.0.8 0.0.0.3 area 0
 network 10.0.0.12 0.0.0.3 area 0
 default-information originate
 exit
router bgp 65001
 bgp router-id 2.2.2.2
 neighbor 200.0.2.254 remote-as 65000
 exit
end
write memory
EOF

# -----------------------------------------------------------------------------
# 4) HQ-Core1 (L2/多層SW): ip routing + VLAN10 + Po1(LACP) + SVI/HSRP(Active) + OSPF
# -----------------------------------------------------------------------------
push hq-core1 <<'EOF'
terminal length 0
conf t
hostname hq-core1
ip routing
vlan 10
 name SALES
 exit
interface Loopback0
 ip address 3.3.3.3 255.255.255.255
 exit
interface e0/1
 no switchport
 ip address 10.0.0.2 255.255.255.252
 no shut
 exit
interface e0/2
 no switchport
 ip address 10.0.0.10 255.255.255.252
 no shut
 exit
interface range e1/1-2
 switchport trunk encapsulation dot1q
 switchport mode trunk
 channel-group 1 mode active
 no shut
 exit
interface e1/3
 switchport mode access
 switchport access vlan 10
 no shut
 exit
interface Vlan10
 ip address 10.1.10.252 255.255.255.0
 standby 10 ip 10.1.10.254
 standby 10 priority 150
 standby 10 preempt
 no shut
 exit
router ospf 1
 router-id 3.3.3.3
 network 10.0.0.0 0.0.0.3 area 0
 network 10.0.0.8 0.0.0.3 area 0
 network 10.1.10.0 0.0.0.255 area 0
 exit
end
write memory
EOF

# -----------------------------------------------------------------------------
# 5) HQ-Core2 (L2/多層SW): ip routing + VLAN10 + Po1(LACP) + SVI/HSRP(Standby) + OSPF
# -----------------------------------------------------------------------------
push hq-core2 <<'EOF'
terminal length 0
conf t
hostname hq-core2
ip routing
vlan 10
 name SALES
 exit
interface Loopback0
 ip address 4.4.4.4 255.255.255.255
 exit
interface e0/1
 no switchport
 ip address 10.0.0.6 255.255.255.252
 no shut
 exit
interface e0/2
 no switchport
 ip address 10.0.0.14 255.255.255.252
 no shut
 exit
interface range e1/1-2
 switchport trunk encapsulation dot1q
 switchport mode trunk
 channel-group 1 mode active
 no shut
 exit
interface Vlan10
 ip address 10.1.10.253 255.255.255.0
 standby 10 ip 10.1.10.254
 standby 10 priority 100
 standby 10 preempt
 no shut
 exit
router ospf 1
 router-id 4.4.4.4
 network 10.0.0.4 0.0.0.3 area 0
 network 10.0.0.12 0.0.0.3 area 0
 network 10.1.10.0 0.0.0.255 area 0
 exit
end
write memory
EOF

# -----------------------------------------------------------------------------
# 6) BR-Edge: 支社LAN GW + NAT(overload) + デフォルトルート(→ISP)
#    ※ HQ↔支社の VPN はユーザーが後で追加（ここではインターネット到達のみ確立）
# -----------------------------------------------------------------------------
push br-edge <<'EOF'
terminal length 0
conf t
hostname br-edge
interface e0/1
 ip address 200.0.3.1 255.255.255.0
 ip nat outside
 no shut
 exit
interface e0/2
 ip address 10.2.40.254 255.255.255.0
 ip nat inside
 no shut
 exit
access-list 1 permit 10.2.40.0 0.0.0.255
ip nat inside source list 1 interface Ethernet0/1 overload
ip route 0.0.0.0 0.0.0.0 200.0.3.254
end
write memory
EOF

echo "===== All devices configured ====="

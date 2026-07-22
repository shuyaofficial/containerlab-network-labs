# =====================================================================
# hq-edge — MikroTik RouterOS CHR 7.21.4 / HQ WANエッジ / AS65010
# 投入方式: deploy.sh の "config" サブコマンドがブート後にsshで1行ずつ投入する。
#   clab startup-config(FTP自動投入)は不採用(エラー行でimportが丸ごと中断し
#   IP設定すら入らないことを2026-07-17実機テストで確認)。
# ★重要: 各行は「パス+コマンド」を1行に完結させること(例:/ip address add ...)。
#   deploy.shは1行=1 sshセッションで投入するため、RouterOS流の
#   「/ip address(改行)add ...」ブロック記法だと2行目が root コンテキストで
#   実行され失敗する(2026-07-17実機で確認)。
# ★インラインコメント厳禁(#は行頭のみ)。行末#はその行を構文エラーにする。
# 以下は2026-07-17実機でBGP/OSPFのestablishedを確認済みの完結コマンド列。
# clab eth割当: eth1=ether2 / eth2=ether3 / eth3=ether4(ether1=mgmt)
# =====================================================================

# ===== 1. インターフェースIP =====
/ip address add address=10.50.255.6/30 interface=ether2 comment=to-isp-a
/ip address add address=10.50.255.10/30 interface=ether3 comment=to-isp-b
/ip address add address=10.50.255.17/30 interface=ether4 comment=to-hq-core

# ===== 2. OSPF area0(ether4=hq-core向け。default経路をHQ内へ配布) =====
/routing/ospf/instance add name=v2 version=2 router-id=10.50.255.101 originate-default=always
/routing/ospf/area add name=backbone area-id=0.0.0.0 instance=v2
/routing/ospf/interface-template add interfaces=ether4 area=backbone

# ===== 3. BGP広報用の自社集約(10.50.0.0/16。blackholeで経路存在を担保) =====
/ip firewall address-list add list=bgp-nets address=10.50.0.0/16
/ip route add dst-address=10.50.0.0/16 blackhole comment=bgp-aggregate

# ===== 4. BGPインスタンス(AS+Router ID)。v7.21はconnectionがinstance必須 =====
/routing/bgp/instance add name=mv as=65010 router-id=10.50.255.101

# ===== 5. eBGP デュアルホーム(isp-a/isp-b)。local.role=ebgpは必須 =====
/routing/bgp/connection add name=to-isp-a instance=mv remote.address=10.50.255.5 remote.as=65001 local.role=ebgp output.network=bgp-nets
/routing/bgp/connection add name=to-isp-b instance=mv remote.address=10.50.255.9 remote.as=65002 local.role=ebgp output.network=bgp-nets

# ===== 6. REST API(API試験用。http有効化のみ。経路には無影響) =====
/ip service set www disabled=no

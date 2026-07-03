# ネットワーク構築における罠：FortiOSのVPN確立仕様について

## 概要
IKEv2 Route-based VPN（Cisco IOL - FortiGate間）の構築時、IPsecのPhase 1ネゴシエーションが `IN-NEG` のまま進まない問題が発生した。
アンダーレイ（Ping）の疎通が取れており、暗号化アルゴリズム（Proposal）も一致しているにもかかわらず、VPNが確立しなかった。

## 原因（FortiOSの仕様）
FortiGate（FortiOS）には、**「VPNトンネルインターフェースを参照するファイアウォールポリシー（許可ルール）が存在しない場合、IKEv2のネゴシエーション（SA_INIT）を拒否する」**という仕様（最適化機能）が存在する。

設計上、通信確認のPingテスト（下回り）が終わってから、通信を許可するファイアウォールポリシー（Policy 2, 3）を投入しようと後回しにしていたことが仇となった。
FortiGateから見ると「どこへも通信が許可されていないトンネルを作るのはリソースの無駄である」と判断され、ネゴシエーションが強制的に遮断されていた。

## 解決策
VPNトンネルを通過するトラフィックを許可するファイアウォールポリシー（IPv4 Policy）を投入した。

```text
config firewall policy
    edit 2
        set name "VPN_Out"
        set srcintf "port3" "port4"
        set dstintf "VPN_to_Branch"
        set action accept
        set srcaddr "all"
        set dstaddr "all"
        set schedule "always"
        set service "ALL"
    next
    edit 3
        set name "VPN_In"
        set srcintf "VPN_to_Branch"
        set dstintf "port3" "port4"
        set action accept
        set srcaddr "all"
        set dstaddr "all"
        set schedule "always"
        set service "ALL"
    next
end
```
上記ポリシーを投入した直後、IPsec VPN（Tunnel-id 2）のステータスが正常に `READY` へ遷移し、トンネルが開通した。

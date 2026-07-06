/* NW-ZT Console 実データ
 * 出所: 各ラボの実機検証で採取した本物の値（試験結果 doc / 実行ログ）。
 * 稼働中ラボから再生成する場合は capture/ の export で per-lab JSON を作り、
 * refresh でこのファイルを再構築する（外部依存ゼロ・file:// でも開ける）。 */
window.NWZT_DATA = {
  "meta": {
    "product": "NW-ZT Console",
    "subtitle": "ネットワーク中心ゼロトラスト 運用コンソール",
    "capturedAt": "2026-07-06",
    "source": "実機検証ラボからの採取値（OSS × arm64）",
    "repo": "github.com/shuyaofficial/containerlab-network-labs",
    "posture": {
      "level": "secured",
      "label": "セキュア",
      "note": "4観点すべてで default-deny が有効"
    },
    "kpis": [
      {
        "id": "nac",
        "label": "認証済み端末",
        "value": 1,
        "total": 2,
        "unit": "台",
        "tone": "trust",
        "sub": "1 台は未認証で隔離",
        "nav": "nac"
      },
      {
        "id": "ztna",
        "label": "ダークサービス",
        "value": 1,
        "total": 1,
        "unit": "件",
        "tone": "dmz",
        "sub": "内向きポート 0・overlay 経由のみ",
        "nav": "ztna"
      },
      {
        "id": "ndr",
        "label": "NDR アラート",
        "value": 3,
        "unit": "件",
        "tone": "untrust",
        "sub": "重大 0 / 高 1 / 中 2（east-west）",
        "nav": "ndr"
      },
      {
        "id": "microseg",
        "label": "μセグ ポリシー",
        "value": 5,
        "unit": "本",
        "tone": "obs",
        "sub": "許可 3 / 拒否 2（2 層）",
        "nav": "microseg"
      }
    ],
    "zones": [
      {
        "id": "untrust",
        "name": "Untrust",
        "tone": "untrust",
        "nodes": [
          {
            "n": "client",
            "t": "端末"
          },
          {
            "n": "attacker",
            "t": "偵察元"
          }
        ]
      },
      {
        "id": "dmz",
        "name": "DMZ / 認可層",
        "tone": "dmz",
        "nodes": [
          {
            "n": "ziti",
            "t": "SDP broker"
          },
          {
            "n": "IOL sw",
            "t": "認証者"
          },
          {
            "n": "suricata",
            "t": "NDR センサ"
          }
        ]
      },
      {
        "id": "trust",
        "name": "Trust / 業務",
        "tone": "trust",
        "nodes": [
          {
            "n": "app",
            "t": "業務アプリ"
          },
          {
            "n": "srv20",
            "t": "サーバ"
          },
          {
            "n": "backend",
            "t": "backend"
          }
        ]
      },
      {
        "id": "obs",
        "name": "可観測",
        "tone": "obs",
        "nodes": [
          {
            "n": "Loki",
            "t": "ログ集約"
          },
          {
            "n": "Grafana",
            "t": "可視化"
          },
          {
            "n": "Hubble",
            "t": "verdict"
          }
        ]
      }
    ],
    "flows": [
      {
        "from": "untrust",
        "to": "dmz",
        "label": "認証 / 認可",
        "verdict": "checked"
      },
      {
        "from": "dmz",
        "to": "trust",
        "label": "許可済みのみ",
        "verdict": "allow"
      },
      {
        "from": "untrust",
        "to": "trust",
        "label": "直接は不可",
        "verdict": "deny"
      },
      {
        "from": "dmz",
        "to": "obs",
        "label": "ログ / verdict",
        "verdict": "observe"
      }
    ]
  },
  "nac": {
    "theme": "31_nac_dot1x",
    "title": "アクセス制御（NAC / 802.1X）",
    "commercial": "Cisco ISE / Aruba ClearPass",
    "oss": "FreeRADIUS + Cisco IOL L2",
    "summary": {
      "authorized": 1,
      "unauthorized": 1,
      "vlans": [
        "10 BUSINESS",
        "99 QUARANTINE"
      ]
    },
    "sessions": [
      {
        "user": "alice",
        "mac": "aac1.ab1a.f78a",
        "port": "Et0/1",
        "vlan": "10",
        "vlanName": "BUSINESS",
        "status": "Authorized",
        "method": "802.1X (EAP-MD5)"
      },
      {
        "user": "—",
        "mac": "—",
        "port": "Et0/2",
        "vlan": "—",
        "vlanName": "隔離 / 通信不可",
        "status": "Unauthorized",
        "method": "no supplicant"
      }
    ],
    "policy": {
      "intent": "who → VLAN",
      "rows": [
        {
          "who": "alice",
          "vlan": "VLAN 10 (BUSINESS)",
          "via": "RADIUS Tunnel-Private-Group-Id=10"
        }
      ]
    },
    "proof": "RADIUS Access-Accept で動的 VLAN 割当。未認証ポートは Unauthorized のまま業務網に入れない。"
  },
  "ztna": {
    "theme": "36_ztna_openziti",
    "title": "ゼロトラストアクセス（SDP 型 ZTNA）",
    "commercial": "Zscaler ZPA / Cisco Secure Access",
    "oss": "OpenZiti (controller + router + tunneler)",
    "summary": {
      "services": 1,
      "identities": 2,
      "policies": 2,
      "dark": 1
    },
    "services": [
      {
        "name": "webapp",
        "dark": true,
        "hostedBy": "apphost",
        "target": "darkweb:80 (zn-app のみ)"
      }
    ],
    "identities": [
      {
        "name": "apphost",
        "role": "hosts",
        "enrolled": true
      },
      {
        "name": "webclient",
        "role": "clients",
        "enrolled": true
      }
    ],
    "policy": {
      "intent": "identity → service",
      "rows": [
        {
          "type": "Dial",
          "who": "#clients",
          "what": "@webapp"
        },
        {
          "type": "Bind",
          "who": "#hosts",
          "what": "@webapp"
        }
      ]
    },
    "proof": {
      "overlay": "HTTP 200",
      "direct": "HTTP 000",
      "note": "内向きポート 0。認可された client だけが overlay 経由で到達、直接は到達不能。"
    }
  },
  "ndr": {
    "theme": "42_ndr_flow",
    "title": "脅威・フロー（NDR / east-west 可視化）",
    "commercial": "Darktrace / Cisco Secure Network Analytics",
    "oss": "Suricata + Loki / Grafana",
    "summary": {
      "alerts": 3,
      "flows": 312,
      "critical": 0,
      "high": 1,
      "medium": 2
    },
    "alerts": [
      {
        "sid": 1000001,
        "sig": "ZT-NDR east-west SYN scan",
        "src": "172.40.0.21",
        "dst": "172.40.0.22",
        "proto": "TCP",
        "severity": 2,
        "sevLabel": "高",
        "iface": "ndr-br0",
        "note": "同一サブネット横方向の偵察"
      },
      {
        "sid": 1000002,
        "sig": "ZT-NDR east-west HTTP (台帳)",
        "src": "172.40.0.21",
        "dst": "172.40.0.22",
        "proto": "TCP",
        "severity": 3,
        "sevLabel": "中",
        "iface": "ndr-br0",
        "note": "HTTP アクセスの記録"
      }
    ],
    "topTalkers": [
      {
        "src": "172.40.0.21",
        "dst": "172.40.0.22",
        "flows": 300,
        "kind": "SYN スキャン（1→多ポート）"
      }
    ],
    "proof": "docker bridge を host mode Suricata で監視。SYN スキャンを DPI(alert) とフロー(300+件) の両面で捕捉。"
  },
  "microseg": {
    "theme": "microseg_cilium + microseg_nftables",
    "title": "セグメンテーション（マイクロセグメンテーション）",
    "commercial": "Cisco TrustSec/SGT / Illumio",
    "oss": "IOL VLAN·ACL + nftables ／ Cilium·eBPF",
    "approaches": [
      {
        "id": "nftables",
        "name": "nftables / IOL 版（2 層）",
        "rules": [
          {
            "from": "VLAN10",
            "to": "srv20:80",
            "verdict": "allow",
            "layer": "層1 inter-VLAN ACL",
            "counter": 6
          },
          {
            "from": "VLAN10",
            "to": "srv20:22",
            "verdict": "deny",
            "layer": "層1 inter-VLAN ACL",
            "counter": 1
          },
          {
            "from": "pc10a",
            "to": "pc10b",
            "verdict": "deny",
            "layer": "層2 host nftables",
            "counter": 3
          }
        ],
        "insight": "同一 VLAN 内の横移動は VLAN/ACL では止められず、ホスト nftables が担う（層2）。"
      },
      {
        "id": "cilium",
        "name": "Cilium / eBPF 版（L4 / L7）",
        "rules": [
          {
            "from": "frontend",
            "to": "backend GET /",
            "verdict": "allow",
            "layer": "L7 CiliumNetworkPolicy",
            "counter": "200"
          },
          {
            "from": "frontend",
            "to": "backend GET /admin",
            "verdict": "deny",
            "layer": "L7 CiliumNetworkPolicy",
            "counter": "403"
          },
          {
            "from": "other",
            "to": "backend",
            "verdict": "deny",
            "layer": "L4 NetworkPolicy",
            "counter": "000"
          }
        ],
        "insight": "Identity ベースの宣言的ポリシーで IP 直書き ACL の破綻を解消。L7 は HTTP パス単位で 403。"
      }
    ]
  }
};

# 試験証跡: Mission 4 LLQ実証（2026-07-10）

[試験結果_2026-07-10.md](../試験結果_2026-07-10.md) の裏付けとなる生ログ。

| ファイル | 内容 | 要点 |
|---|---|---|
| `iperf_client.txt` | hq-pc→br-pc の負荷トラフィック（TCP並列10本・40秒） | sender 8.65Mbps / receiver 8.39Mbps（WAN 10M shapeを溢れさせた） |
| `voip_ping.txt` | hq-voip→br-pc の音声ping（5pps・45秒） | 223送信/223受信・**loss 0%** |
| `show1.txt` | 負荷中の hq-edge `show policy-map interface Ethernet0/2` | VOICE `b/w exceed drops: 0` / class-default `total drops 85` |

**結論**: WAN輻輳下で音声（EF）はLLQ優先で0ドロップ、データは意図どおりドロップ。QoSの目的を実測で証明。

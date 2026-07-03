# ログ記録：FortiOS VPNデバッグ「no policy configured」エラー

## 発生事象ログ
Cisco（br-edge）側でIKEv2が `IN-NEG` のまま進まない事象について、FortiGate（fgt-edge）側でIKEデバッグ（`diagnose debug application ike -1`）を実施した際のリアルタイムログ。

```text
ike V=root:0: comes 200.0.3.1:500->200.0.1.1:500,ifindex=4,vrf=0,len=472....
ike V=root:0: IKEv2 exchange=SA_INIT id=51b2d2ebab3a0fcc/0000000000000000 len=472
...
ike V=root:0:51b2d2ebab3a0fcc/0000000000000000:94: incoming proposal:
ike V=root:0:51b2d2ebab3a0fcc/0000000000000000:94: proposal id = 1:
ike V=root:0:51b2d2ebab3a0fcc/0000000000000000:94:   protocol = IKEv2:
ike V=root:0:51b2d2ebab3a0fcc/0000000000000000:94:      encapsulation = IKEv2/none
ike V=root:0:51b2d2ebab3a0fcc/0000000000000000:94:         type=ENCR, val=DES_CBC
ike V=root:0:51b2d2ebab3a0fcc/0000000000000000:94:         type=INTEGR, val=AUTH_HMAC_SHA2_256_128
ike V=root:0:51b2d2ebab3a0fcc/0000000000000000:94:         type=PRF, val=PRF_HMAC_SHA2_256
ike V=root:0:51b2d2ebab3a0fcc/0000000000000000:94:         type=DH_GROUP, val=MODP2048.
ike V=root:0:VPN_to_Branch: ignoring IKEv2 request, no policy configured
ike V=root:0:51b2d2ebab3a0fcc/0000000000000000:94: negotiation failure
ike V=root:Negotiate SA Error: [11820]
```

## ログの分析と真因
ログの最終行手前にある `ignoring IKEv2 request, no policy configured` がすべてを物語っている。
これは「受信した暗号化プロポーザル（DES, SHA256, DH Group14）には一切の不備がないが、このVPNトンネル（VPN_to_Branch）に紐づくファイアウォールポリシーが1つも存在しないため、トンネル構築要求を意図的に無視した」というFortiOSの振る舞いを示している。

暗号化不一致（Proposal mismatch）などを疑って長時間検証を行っていたが、実際には設定順序（ポリシー投入を後回しにしていたこと）が原因であったことを示す決定的な証拠ログとなった。

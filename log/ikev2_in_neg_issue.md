# ログ記録：IKEv2 IN-NEG ステータスと通信断の解消

## 発生事象ログ
Cisco（br-edge）側で `show crypto ikev2 sa` を実行した際、ステータスが `IN-NEG` のまま確立されない事象が発生。

```text
br-edge#show crypto ikev2 sa
 IPv4 Crypto IKEv2  SA 

Tunnel-id Local                 Remote                fvrf/ivrf            Status 
1         200.0.3.1/500         200.0.1.1/500         none/none            IN-NEG 
      Encr: Unknown - 0, PRF: Unknown - 0, Hash: None, DH Grp:0, Auth sign: Unknown - 0, Auth verify: Unknown - 0
      Life/Active Time: 86400/0 sec
```

## 切り分けのためのPingテストログ
br-edgeから対向への疎通確認を実施。

```text
br-edge#ping 200.0.3.254
Type escape sequence to abort.
Sending 5, 100-byte ICMP Echos to 200.0.3.254, timeout is 2 seconds:
!!!!!
Success rate is 100 percent (5/5), round-trip min/avg/max = 1/5/16 ms

br-edge#ping 200.0.1.254 
Type escape sequence to abort.
Sending 5, 100-byte ICMP Echos to 200.0.1.254, timeout is 2 seconds:
!!!!!
Success rate is 100 percent (5/5), round-trip min/avg/max = 1/2/5 ms

br-edge#ping 200.0.1.1 
Type escape sequence to abort.
Sending 5, 100-byte ICMP Echos to 200.0.1.1, timeout is 2 seconds:
.....
Success rate is 0 percent (0/5)
```
このログから、ISP（200.0.1.254）までは到達しているが、FortiGate（200.0.1.1）からの応答がないことが判明した。

## 解決後のPingテストログ
FortiGateのスタティックルートの優先度（distance 1）を変更後、通信が正常化。

```text
br-edge#ping 200.0.1.1 
Type escape sequence to abort.
Sending 5, 100-byte ICMP Echos to 200.0.1.1, timeout is 2 seconds:
!!!!!
Success rate is 100 percent (5/5), round-trip min/avg/max = 1/3/6 ms
```

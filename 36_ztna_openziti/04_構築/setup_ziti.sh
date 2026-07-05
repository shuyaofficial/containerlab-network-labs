#!/usr/bin/env bash
# N2 OpenZiti ダークサービスのセットアップ（deploy 後に実行）
# サービス/identity/ポリシー作成 → enrollment → tunneler 起動 → 実証まで。
set -euo pipefail
ZE="sudo docker exec ziti ziti edge"

echo "== コントローラ login 待機 =="
for i in $(seq 1 15); do sudo docker exec ziti ziti edge login ziti:1280 -u admin -p admin -y >/dev/null 2>&1 && break; sleep 6; done

echo "== ルータ online 待機 =="
for i in $(seq 1 10); do
  $ZE list edge-routers 2>/dev/null | grep -q "true" && break; sleep 4
done

echo "== サービス設定・サービス・identity・ポリシー作成（冪等: 既存はスキップ） =="
$ZE create config webapp-host host.v1 '{"protocol":"tcp","address":"darkweb","port":80}' 2>/dev/null || true
$ZE create service webapp --configs webapp-host 2>/dev/null || true
$ZE create identity apphost   -a hosts   -o /tmp/ziti/apphost.jwt   2>/dev/null || true
$ZE create identity webclient -a clients -o /tmp/ziti/webclient.jwt 2>/dev/null || true
$ZE create service-policy webapp-bind Bind --service-roles '@webapp' --identity-roles '#hosts'   2>/dev/null || true
$ZE create service-policy webapp-dial Dial --service-roles '@webapp' --identity-roles '#clients' 2>/dev/null || true
$ZE create edge-router-policy allEr --edge-router-roles '#all' --identity-roles '#all' 2>/dev/null || true
$ZE create service-edge-router-policy allSerp --edge-router-roles '#all' --service-roles '#all' 2>/dev/null || true

echo "== JWT 配布（注意: docker cp は root:0600 で作るため chmod 644 が必須） =="
sudo docker cp ziti:/tmp/ziti/apphost.jwt   /tmp/apphost.jwt   && sudo docker cp /tmp/apphost.jwt   apptun:/apphost.jwt
sudo docker cp ziti:/tmp/ziti/webclient.jwt /tmp/webclient.jwt && sudo docker cp /tmp/webclient.jwt clienttun:/webclient.jwt
sudo docker exec -u root apptun    chmod 644 /apphost.jwt
sudo docker exec -u root clienttun chmod 644 /webclient.jwt

echo "== enrollment =="
sudo docker exec apptun    ziti edge enroll /apphost.jwt   -o /tmp/apphost.json
sudo docker exec clienttun ziti edge enroll /webclient.jwt -o /tmp/webclient.json

echo "== tunneler 起動（apptun=host / clienttun=proxy webapp:8080） =="
sudo docker exec -d apptun    sh -c "ziti tunnel host -i /tmp/apphost.json > /tmp/host.log 2>&1"
sudo docker exec -d clienttun sh -c "ziti tunnel proxy webapp:8080 -i /tmp/webclient.json > /tmp/proxy.log 2>&1"
sleep 15

echo "== 実証 =="
echo -n "[1] オーバーレイ経由 client→localhost:8080→darkweb : "
sudo docker exec clienttun sh -c 'curl -s -m8 -o /dev/null -w "HTTP %{http_code}\n" http://localhost:8080/'
echo -n "[2] 直接 client→darkweb:80（到達不能が正常）      : "
sudo docker exec clienttun sh -c 'curl -s -m5 -o /dev/null -w "HTTP %{http_code}\n" http://darkweb:80/ || echo "unreachable"'

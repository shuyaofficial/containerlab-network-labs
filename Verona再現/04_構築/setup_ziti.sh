#!/usr/bin/env bash
# Verona再現: ZTNAダークサービスのセットアップ（36_ztna_openziti/setup_ziti.shを流用・改変）
# deploy.sh deploy-core 後に実行。サービス/identity/ポリシー作成 → enrollment → tunneler起動 → 実証まで。
# Verona p25「ダイナミックポートコントロール」・p12「証明書単位のゼロトラストアクセス」の再現。
set -euo pipefail
ZE="sudo docker exec ziti ziti edge"

echo "== コントローラ login 待機 =="
for i in $(seq 1 15); do sudo docker exec ziti ziti edge login ziti:1280 -u admin -p admin -y >/dev/null 2>&1 && break; sleep 6; done

echo "== ルータ online 待機 =="
for i in $(seq 1 10); do
  $ZE list edge-routers 2>/dev/null | grep -q "true" && break; sleep 4
done

echo "== サービス設定・サービス・identity・ポリシー作成（冪等: 既存はスキップ） =="
$ZE create config protected-app-host host.v1 '{"protocol":"tcp","address":"protected-app","port":80}' 2>/dev/null || true
$ZE create service protected-app --configs protected-app-host 2>/dev/null || true
$ZE create identity apphost      -a hosts   -o /tmp/ziti/apphost.jwt      2>/dev/null || true
$ZE create identity remoteclient -a clients -o /tmp/ziti/remoteclient.jwt 2>/dev/null || true
$ZE create service-policy protected-app-bind Bind --service-roles '@protected-app' --identity-roles '#hosts'   2>/dev/null || true
$ZE create service-policy protected-app-dial Dial --service-roles '@protected-app' --identity-roles '#clients' 2>/dev/null || true
$ZE create edge-router-policy allEr --edge-router-roles '#all' --identity-roles '#all' 2>/dev/null || true
$ZE create service-edge-router-policy allSerp --edge-router-roles '#all' --service-roles '#all' 2>/dev/null || true

echo "== JWT 配布（注意: docker cp は root:0600 で作るため chmod 644 が必須） =="
sudo docker cp ziti:/tmp/ziti/apphost.jwt      /tmp/apphost.jwt      && sudo docker cp /tmp/apphost.jwt      apptun:/apphost.jwt
sudo docker cp ziti:/tmp/ziti/remoteclient.jwt /tmp/remoteclient.jwt && sudo docker cp /tmp/remoteclient.jwt clienttun:/remoteclient.jwt
sudo docker exec -u root apptun    chmod 644 /apphost.jwt
sudo docker exec -u root clienttun chmod 644 /remoteclient.jwt

echo "== enrollment =="
sudo docker exec apptun    ziti edge enroll /apphost.jwt      -o /tmp/apphost.json
sudo docker exec clienttun ziti edge enroll /remoteclient.jwt -o /tmp/remoteclient.json

echo "== tunneler 起動（apptun=host / clienttun=proxy protected-app:8080） =="
sudo docker exec -d apptun    sh -c "ziti tunnel host -i /tmp/apphost.json > /tmp/host.log 2>&1"
sudo docker exec -d clienttun sh -c "ziti tunnel proxy protected-app:8080 -i /tmp/remoteclient.json > /tmp/proxy.log 2>&1"
sleep 15

echo "== 実証（ダイナミックポートコントロール／ダークサービスの成立確認） =="
echo -n "[1] オーバーレイ経由 clienttun→localhost:8080→protected-app : "
sudo docker exec clienttun sh -c 'curl -s -m8 -o /dev/null -w "HTTP %{http_code}\n" http://localhost:8080/'
echo -n "[2] 直接 clienttun→protected-app:80（到達不能が正常）        : "
sudo docker exec clienttun sh -c 'curl -s -m5 -o /dev/null -w "HTTP %{http_code}\n" http://protected-app:80/ || echo "unreachable"'

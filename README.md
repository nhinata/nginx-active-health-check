# nginx_with_health_check

nginxでactive health checkを行うためのモジュール（[nginx_upstream_check_module](https://github.com/yaoweibin/nginx_upstream_check_module)）を組み込んだ環境構築サンプル

* nginx 1.30.6 をソースからビルドし、モジュールのパッチを当てて組み込む
* 確認用のバックエンド `backend01`〜`backend05`（nginx:alpine）を同時に起動する

build : `docker compose up -d --build`

```
    upstream api {
        server backend01:80;
        server backend02:80;
        server backend03:80;
        server backend04:80;
        server backend05:80;

        check interval=5000 rise=1 fall=2 timeout=3000 type=http port=80;
        check_http_send "GET /health.html HTTP/1.0\r\nHost: localhost\r\n\r\n";
        check_http_expect_alive http_2xx http_3xx;
    }
```
上記により5000ms間隔で各サーバの`/health.html`へhttpリクエストを送り、レスポンスが2xx,3xx系以外（または3000ms以内に応答がない）の状態が2回続くと対象のサーバはdownとみなされる。1回成功すればupに戻る

```
    server {
        listen       80;
        listen  [::]:80;
        server_name  localhost;

    
        location / {
            access_log  off;
            error_log   /var/log/nginx/error.log;
            proxy_pass  http://api/;
        }
    }

    server {
        listen       8080;
        server_name  localhost;

        location /status {
            check_status;
            access_log   off;
        }
    }
```
`curl http://localhost:8080/status`でサーバのstatusリストが確認可能（`?format=csv`や`?format=json`も可）。
バックエンドの構成が見えてしまうため、8080番はホストの`127.0.0.1`にのみ公開している

### 動作確認
```
curl http://localhost/                    # backend01〜05 に振り分けられる
docker compose stop backend03             # 停止させると約10秒でdownになる
docker compose pause backend04            # 応答しない状態では約20秒でdownになる
curl "http://localhost:8080/status?format=csv"
docker compose start backend03 && docker compose unpause backend04
```
* nginxは起動時にバックエンドのIPを解決するため、バックエンドを作り直してIPが変わった場合は`docker compose restart nginx`が必要
* ログは`docker compose logs nginx`で確認できる

### ref
* module : https://github.com/yaoweibin/nginx_upstream_check_module
* passive or active : https://docs.nginx.com/nginx/admin-guide/load-balancer/http-health-check/
* ngx_stream_upstream_module : https://nginx.org/en/docs/stream/ngx_stream_upstream_module.html
* ngx_stream_upstream_hc_module : https://nginx.org/en/docs/stream/ngx_stream_upstream_hc_module.html

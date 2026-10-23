# nginx_with_health_check

[English](README.md) | 日本語

OSS 版 nginx で **active health check**（nginx 側から定期的にバックエンドへリクエストを送り、生死を判定する仕組み）を試すための再現環境です。

OSS 版 nginx に標準で備わっているのは、実際のリクエストが失敗したときにサーバを外す passive health check（`max_fails` / `fail_timeout`）だけです。active health check は有償の NGINX Plus の機能のため、ここではサードパーティの [nginx_upstream_check_module](https://github.com/yaoweibin/nginx_upstream_check_module) を組み込んだ nginx をビルドしています。

`docker compose up` だけで nginx とバックエンド 5 台が起動し、バックエンドを止めると down と判定され、戻すと up に復帰する様子を手元で確認できます。

> 学習・検証用のサンプルです。本番で active health check を使う場合は、標準で同機能を持つ NGINX Plus・Tengine・HAProxy なども検討してください。

## 構成

```
curl localhost:80     --->  nginx  --- proxy_pass --->  backend01 ... backend05
                              |    --- check -------->  GET /health.html (every 5s)
curl localhost:8080   --->  /status (up / down list)
```

| ファイル | 内容 |
|---|---|
| `docker-compose.yml` | nginx と確認用バックエンド `backend01`〜`backend05` |
| `docker/nginx/Dockerfile` | nginx 1.30.6 にモジュールのパッチを当ててソースからビルド |
| `docker/nginx/nginx.conf` | upstream とヘルスチェックの設定 |
| `docker/nginx/nginx_upstream_check_module/` | モジュール本体（取り込み元は[下記](#同梱しているモジュール)） |

バックエンドは `/` で自分のホスト名を、`/health.html` で `ok` を返します。

## クイックスタート

必要なもの: Docker（Compose v2）。ポート 80 と 8080 を使います。ARM64（Apple Silicon）で動作確認しています。

```sh
docker compose up -d --build
curl http://localhost/                          # backend01〜05 のどれかが返る
curl "http://localhost:8080/status?format=csv"  # 各バックエンドの状態
```

5 台とも `up` になっていれば正常です。

```
0,api,172.19.0.4:80,up,3,0,http,80
1,api,172.19.0.6:80,up,3,0,http,80
2,api,172.19.0.5:80,up,3,0,http,80
3,api,172.19.0.3:80,up,3,0,http,80
4,api,172.19.0.2:80,up,3,0,http,80
```

列は左から、番号・upstream 名・アドレス・状態・連続成功回数・連続失敗回数・チェック種別・ポートです。`?format=csv` を外すと HTML、`?format=json` で JSON になります。

終わったら `docker compose down` で停止します。

## 障害を起こしてみる

### バックエンドを止める

```sh
docker compose stop backend03
```

15 秒ほどで backend03（3 行目）が `down` になります。

```
2,api,172.19.0.5:80,down,0,2,http,80
```

この間も `curl http://localhost/` はすべて 200 で返り、backend03 には振り分けられません。

```sh
docker compose start backend03   # 数秒で up に戻る
```

### 応答しない状態にする

プロセスは生きているが応答しない、という状態は `pause` で再現できます。

```sh
docker compose pause backend04     # 15 秒ほどで down
docker compose unpause backend04   # 数秒で up に戻る
```

判定の経過は `docker compose logs nginx` で確認できます。

```
[error] 9#0: check time out with peer: 172.19.0.3:80
[error] 9#0: disable check peer: 172.19.0.3:80
[error] 8#0: enable check peer: 172.19.0.3:80
```

## 設定

`docker/nginx/nginx.conf` の該当部分です。

```nginx
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

| 項目 | 値 | 意味 |
|---|---|---|
| `interval` | 5000 | チェックの間隔（ミリ秒） |
| `timeout` | 3000 | この時間内に応答がなければ失敗とみなす（ミリ秒） |
| `fall` | 2 | 連続でこの回数失敗すると down |
| `rise` | 1 | 連続でこの回数成功すると up |
| `type` / `port` | http / 80 | HTTP でポート 80 にチェックを送る |
| `check_http_send` | — | チェックで送るリクエスト。`Host` を付けないと、バーチャルホストを使うバックエンドで 404 になり誤判定する |
| `check_http_expect_alive` | 2xx, 3xx | 正常とみなすステータス |

この設定での実測（各 1 回）は、停止・無応答とも down まで 15〜16 秒、復帰は 4 秒でした。早く検知したい場合は `interval` や `timeout` を短くします。

状態一覧は 8080 番の別 server に置き、`docker-compose.yml` でホストの `127.0.0.1` にだけ公開しています。バックエンドの構成が外から見えないようにするためです。

```nginx
server {
    listen 8080;
    location /status {
        check_status;
        access_log off;
    }
}
```

## 注意点

- nginx はバックエンドの IP を起動時に一度だけ解決します。バックエンドを作り直して IP が変わった場合は `docker compose restart nginx` が必要です。
- 少ないリクエスト数だと 1 台に偏って見えることがあります。nginx の worker ごとに振り分けの順番を持っているためで、回数を増やすと分散します。
- モジュールのパッチは nginx のバージョンごとに用意されています。nginx のバージョン（`Dockerfile` の `NGINX_VERSION`）を変える場合は、対応するパッチを選び直してください。

## 同梱しているモジュール

`docker/nginx/nginx_upstream_check_module/` は [yaoweibin/nginx_upstream_check_module](https://github.com/yaoweibin/nginx_upstream_check_module) のコミット [`02c6c9d`](https://github.com/yaoweibin/nginx_upstream_check_module/tree/02c6c9de14ca1e60adb9f48179707c57d532d622) から、ビルドに必要なファイルと README を取り込んだものです。BSD ライセンスで、著作権表示とライセンス本文は同ディレクトリの `README` にあります。

## ライセンス

このリポジトリは [MIT License](LICENSE) です。ただし `docker/nginx/nginx_upstream_check_module/` 配下は、上記のとおりモジュール本来の BSD ライセンスに従います。

## 参考

- [nginx_upstream_check_module](https://github.com/yaoweibin/nginx_upstream_check_module) — 使用しているモジュール。設定項目の詳細はこちらの README
- [HTTP Health Checks（NGINX ドキュメント）](https://docs.nginx.com/nginx/admin-guide/load-balancer/http-health-check/) — passive と active の違い
- [ngx_stream_upstream_module](https://nginx.org/en/docs/stream/ngx_stream_upstream_module.html) — TCP/UDP（stream）の upstream 設定
- [ngx_stream_upstream_hc_module](https://nginx.org/en/docs/stream/ngx_stream_upstream_hc_module.html) — NGINX Plus の stream 向け active health check

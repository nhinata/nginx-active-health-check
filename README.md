# nginx_with_health_check

English | [日本語](README.ja.md)

A ready-to-run environment for trying **active health checks** (nginx periodically sends requests to each backend and marks it up or down) on open source nginx.

Open source nginx only ships with passive health checks (`max_fails` / `fail_timeout`), which take a server out of rotation after real requests to it fail. Active health checks are a feature of the commercial NGINX Plus, so this repository builds nginx with the third-party [nginx_upstream_check_module](https://github.com/yaoweibin/nginx_upstream_check_module).

A single `docker compose up` starts nginx and five backends. Stop a backend and watch it get marked down; bring it back and watch it recover.

> This is a sample for learning and testing. For production use of active health checks, also consider NGINX Plus, Tengine or HAProxy, which support them out of the box.

## How it works

```
curl localhost:80     --->  nginx  --- proxy_pass --->  backend01 ... backend05
                              |    --- check -------->  GET /health.html (every 5s)
curl localhost:8080   --->  /status (up / down list)
```

| File | Purpose |
|---|---|
| `docker-compose.yml` | nginx and the demo backends `backend01`–`backend05` |
| `docker/nginx/Dockerfile` | Builds nginx 1.30.6 from source with the module's patch applied |
| `docker/nginx/nginx.conf` | Upstream and health check configuration |
| `docker/nginx/nginx_upstream_check_module/` | The module source (see [Bundled module](#bundled-module) for where it comes from) |

Each backend returns its own hostname at `/` and `ok` at `/health.html`.

## Quick start

Requirements: Docker with Compose v2. Ports 80 and 8080 must be free. Tested on ARM64 (Apple Silicon).

```sh
docker compose up -d --build
curl http://localhost/                          # returns one of backend01-backend05
curl "http://localhost:8080/status?format=csv"  # health of each backend
```

All five backends should be `up`:

```
0,api,172.19.0.4:80,up,3,0,http,80
1,api,172.19.0.6:80,up,3,0,http,80
2,api,172.19.0.5:80,up,3,0,http,80
3,api,172.19.0.3:80,up,3,0,http,80
4,api,172.19.0.2:80,up,3,0,http,80
```

The columns are: index, upstream name, address, status, consecutive successes, consecutive failures, check type and port. Drop `?format=csv` for an HTML page, or use `?format=json` for JSON.

Run `docker compose down` when you are done.

## Simulating failures

### Stop a backend

```sh
docker compose stop backend03
```

After about 15 seconds, backend03 (the third row) turns `down`:

```
2,api,172.19.0.5:80,down,0,2,http,80
```

Meanwhile, every `curl http://localhost/` still returns 200, and no requests are sent to backend03.

```sh
docker compose start backend03   # back up within a few seconds
```

### Make a backend unresponsive

Use `pause` to simulate a backend whose process is alive but does not respond:

```sh
docker compose pause backend04     # down after about 15 seconds
docker compose unpause backend04   # back up within a few seconds
```

You can follow the checks with `docker compose logs nginx`:

```
[error] 9#0: check time out with peer: 172.19.0.3:80
[error] 9#0: disable check peer: 172.19.0.3:80
[error] 8#0: enable check peer: 172.19.0.3:80
```

## Configuration

The relevant part of `docker/nginx/nginx.conf`:

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

| Directive | Value | Meaning |
|---|---|---|
| `interval` | 5000 | Time between checks (ms) |
| `timeout` | 3000 | A check fails if there is no response within this time (ms) |
| `fall` | 2 | Mark a server down after this many consecutive failures |
| `rise` | 1 | Mark a server up after this many consecutive successes |
| `type` / `port` | http / 80 | Send HTTP checks to port 80 |
| `check_http_send` | — | The request sent as a check. Without a `Host` header, backends that use virtual hosts return 404 and are wrongly marked down |
| `check_http_expect_alive` | 2xx, 3xx | Status codes treated as healthy |

With these settings, it took 15–16 seconds for a stopped or unresponsive backend to be marked down, and 4 seconds for it to come back up (one measurement each). Lower `interval` and `timeout` to detect failures faster.

The status page is served by a separate server on port 8080, which `docker-compose.yml` publishes only on the host's `127.0.0.1`, so the backend layout is not exposed to the outside:

```nginx
server {
    listen 8080;
    location /status {
        check_status;
        access_log off;
    }
}
```

## Caveats

- nginx resolves backend addresses only once, at startup. If you recreate a backend and its IP address changes, run `docker compose restart nginx`.
- With only a few requests, traffic may look concentrated on one backend. Each nginx worker keeps its own round-robin position; send more requests and they spread out.
- The module provides a separate patch for each range of nginx versions. If you change the nginx version (`NGINX_VERSION` in the `Dockerfile`), pick the matching patch.

## Bundled module

`docker/nginx/nginx_upstream_check_module/` contains the files needed for the build, plus the README, taken from commit [`02c6c9d`](https://github.com/yaoweibin/nginx_upstream_check_module/tree/02c6c9de14ca1e60adb9f48179707c57d532d622) of [yaoweibin/nginx_upstream_check_module](https://github.com/yaoweibin/nginx_upstream_check_module). The module is BSD licensed; its copyright notice and license text are in the `README` in that directory.

## License

This repository is licensed under the [MIT License](LICENSE). The files under `docker/nginx/nginx_upstream_check_module/` remain under the module's own BSD license, as described above.

## References

- [nginx_upstream_check_module](https://github.com/yaoweibin/nginx_upstream_check_module) — the module used here; see its README for all directives
- [HTTP Health Checks (NGINX documentation)](https://docs.nginx.com/nginx/admin-guide/load-balancer/http-health-check/) — passive vs. active health checks
- [ngx_stream_upstream_module](https://nginx.org/en/docs/stream/ngx_stream_upstream_module.html) — upstream configuration for TCP/UDP (stream)
- [ngx_stream_upstream_hc_module](https://nginx.org/en/docs/stream/ngx_stream_upstream_hc_module.html) — NGINX Plus active health checks for stream

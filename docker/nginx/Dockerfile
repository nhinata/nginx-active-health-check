FROM debian:bookworm-slim AS build

ARG NGINX_VERSION=1.30.6

WORKDIR /work

RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates curl build-essential patch libpcre2-dev zlib1g-dev && \
    rm -rf /var/lib/apt/lists/*

COPY nginx_upstream_check_module /work/nginx_upstream_check_module

RUN curl -fsSL "https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz" | tar -xz && \
    cd nginx-${NGINX_VERSION} && \
    patch -p1 < ../nginx_upstream_check_module/check_1.20.1+.patch && \
    ./configure --add-module=../nginx_upstream_check_module && \
    make && \
    make install


FROM debian:bookworm-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends libpcre2-8-0 zlib1g && \
    rm -rf /var/lib/apt/lists/* && \
    useradd -r -s /bin/false nginx && \
    mkdir -p /var/log/nginx && \
    ln -sf /dev/stdout /var/log/nginx/access.log && \
    ln -sf /dev/stderr /var/log/nginx/error.log

COPY --from=build /usr/local/nginx /usr/local/nginx
RUN ln -s /usr/local/nginx/sbin/nginx /usr/bin/nginx

COPY nginx.conf /etc/nginx/

CMD ["nginx", "-c", "/etc/nginx/nginx.conf", "-g", "daemon off;"]

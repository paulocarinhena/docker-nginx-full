#!/bin/bash
# Verifies a built nginx-full image: OpenResty version, nginx core version,
# dynamic geoip2 module ABI and the Lua modules NPM relies on.
# Usage: ci-verify.sh <image>   (EXPECTED_OPENRESTY must be set)
# MIN_NGINX_VERSION defaults to 1031008 (nginx 1.31.8, first OpenResty release
# with CVE-2026-15176/97205/93479 fixed); lowered only for the baseline run.
set -euo pipefail

IMAGE="$1"
: "${EXPECTED_OPENRESTY:?EXPECTED_OPENRESTY must be set}"
export MIN_NGINX_VERSION="${MIN_NGINX_VERSION:-1031008}"

echo "::group::verify ${IMAGE}"
docker run --rm -i --entrypoint bash -e EXPECTED_OPENRESTY -e MIN_NGINX_VERSION "$IMAGE" -s <<'EOF'
set -euo pipefail

nginx -V 2>&1 | tee /tmp/V
grep -qx "nginx version: openresty/${EXPECTED_OPENRESTY}" /tmp/V
grep -q "ngx_http_geoip2_module" /tmp/V

mkdir -p /var/log/nginx /var/cache/nginx
cat > /tmp/t.conf <<'CONF'
load_module /usr/lib/nginx/modules/ngx_http_geoip2_module.so;
user root;
pid /tmp/t.pid;
error_log /dev/stderr warn;
events {}
http {
	map $host $mapped { default "map-ok"; }
	server {
		listen 127.0.0.1:8099;
		location /version {
			content_by_lua_block { ngx.say(ngx.config.nginx_version) }
		}
		location /modules {
			content_by_lua_block {
				for _, m in ipairs({ "cjson", "resty.core", "resty.http", "resty.openidc" }) do
					require(m)
				end
				ngx.say("ok")
			}
		}
		location /map {
			return 200 "$mapped\n";
		}
	}
}
CONF

nginx -t -c /tmp/t.conf
nginx -c /tmp/t.conf
trap 'nginx -c /tmp/t.conf -s quit || true' EXIT
sleep 1

version="$(curl -fsS http://127.0.0.1:8099/version)"
echo "ngx.config.nginx_version=${version} (min ${MIN_NGINX_VERSION})"
[ "$version" -ge "$MIN_NGINX_VERSION" ]

[ "$(curl -fsS http://127.0.0.1:8099/modules)" = "ok" ]
[ "$(curl -fsS http://127.0.0.1:8099/map)" = "map-ok" ]
echo "verify passed"
EOF
echo "::endgroup::"

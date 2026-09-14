#!/bin/sh

set +e

MARKER="VRP_BASEIMG_20260914-073026"

say() {
  printf '%s | %s\n' "$MARKER" "$*"
}

section() {
  say "===== $* ====="
}

section "BASE IMAGE IDENTITY"

say "uid=$(id -u 2>/dev/null)"
say "pwd=$(pwd 2>/dev/null)"
say "hostname=$(hostname 2>/dev/null)"

section "TOP LEVEL"

for P in   /code/app   /opt   /usr/local   /etc   /root   /var/run   /var/lib
do
  if [ -e "$P" ]; then
    say "ROOT=$P"

    find "$P"       -maxdepth 2       -mindepth 1       -printf '%M %u %g %s %p\n'       2>/dev/null       | head -400       | while IFS= read -r L
    do
      say "tree: $L"
    done
  fi
done

section "KNOWN CREDENTIAL FILENAMES"

find   /code/app   /opt   /usr/local   /etc   /root   /var/lib   /var/run   -xdev   -type f   \(     -iname '*credential*'     -o -iname '*secret*'     -o -iname '*token*'     -o -iname '*private*key*'     -o -iname 'application_default_credentials.json'     -o -iname 'credentials.db'     -o -iname 'config.json'     -o -iname '.netrc'     -o -iname '.npmrc'     -o -iname '.pypirc'     -o -iname 'id_rsa'     -o -iname 'id_ed25519'     -o -iname '*.p12'     -o -iname '*.pfx'     -o -iname '*.jks'     -o -iname '*.kubeconfig'   \)   2>/dev/null   | sort -u   | while IFS= read -r F
do
  [ -f "$F" ] || continue

  SZ=$(stat -c '%s' "$F" 2>/dev/null)
  MODE=$(stat -c '%A' "$F" 2>/dev/null)
  OWNER=$(stat -c '%U:%G' "$F" 2>/dev/null)
  SHA=$(sha256sum "$F" 2>/dev/null | awk '{print $1}')

  say "candidate path=$F size=$SZ mode=$MODE owner=$OWNER sha256=$SHA"
done

section "PRIVATE KEY SIGNATURES"

for ROOT in   /code/app   /opt   /usr/local   /etc   /root
do
  [ -d "$ROOT" ] || continue

  grep     -RIl     --binary-files=without-match     -E     'BEGIN ([A-Z0-9 ]+ )?PRIVATE KEY|BEGIN OPENSSH PRIVATE KEY'     "$ROOT"     2>/dev/null     | while IFS= read -r F
  do
    SZ=$(stat -c '%s' "$F" 2>/dev/null)
    SHA=$(sha256sum "$F" 2>/dev/null | awk '{print $1}')

    say "PRIVATE_KEY_SIGNATURE path=$F size=$SZ sha256=$SHA"
  done
done

section "SERVICE ACCOUNT JSON SIGNATURE"

for ROOT in   /code/app   /opt   /usr/local   /etc   /root
do
  [ -d "$ROOT" ] || continue

  grep     -RIl     --binary-files=without-match     '"type"[[:space:]]*:[[:space:]]*"service_account"'     "$ROOT"     2>/dev/null     | while IFS= read -r F
  do
    SZ=$(stat -c '%s' "$F" 2>/dev/null)
    SHA=$(sha256sum "$F" 2>/dev/null | awk '{print $1}')

    say "SERVICE_ACCOUNT_JSON_SIGNATURE path=$F size=$SZ sha256=$SHA"
  done
done

section "TOKEN-LIKE CONFIG SIGNATURES"

for ROOT in   /code/app   /opt   /usr/local   /etc   /root
do
  [ -d "$ROOT" ] || continue

  grep     -RIl     --binary-files=without-match     -E     '"refresh_token"[[:space:]]*:|"client_secret"[[:space:]]*:|access_token[[:space:]]*='     "$ROOT"     2>/dev/null     | while IFS= read -r F
  do
    SZ=$(stat -c '%s' "$F" 2>/dev/null)
    SHA=$(sha256sum "$F" 2>/dev/null | awk '{print $1}')

    say "TOKEN_CONFIG_SIGNATURE path=$F size=$SZ sha256=$SHA"
  done
done

section "FILE CAPABILITIES"

if command -v getcap >/dev/null 2>&1; then
  getcap -r     /usr     /bin     /sbin     /opt     /code/app     2>/dev/null     | while IFS= read -r L
  do
    say "getcap: $L"
  done
else
  say "getcap=<unavailable>"
fi

section "SUID SGID"

find   /usr   /bin   /sbin   /opt   -xdev   -type f   \( -perm -4000 -o -perm -2000 \)   -printf '%M %u %g %s %p\n'   2>/dev/null   | while IFS= read -r L
do
  say "privileged_binary: $L"
done

section "SAFETY"

say "secret_contents=NOT_PRINTED"
say "credential_use=NOT_ATTEMPTED"
say "token_endpoint=NOT_REQUESTED"
say "external_resource_access=NOT_ATTEMPTED"

section "DONE"

say "BASE_IMAGE_CENSUS_COMPLETE"

exit 0

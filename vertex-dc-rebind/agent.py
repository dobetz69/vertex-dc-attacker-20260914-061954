import urllib.parse

import google.auth
from google.auth.transport.requests import AuthorizedSession

PROJECT = "project-a09451ee-54c6-459e-bbe"
ORG = "850018898700"
RUNTIME_SA = "vrp70-re-control1@project-a09451ee-54c6-459e-bbe.iam.gserviceaccount.com"
SOURCE = "S1A_CEILING_20260914-093151"

PROJECT_PERMISSIONS = [
    "resourcemanager.projects.setIamPolicy",
    "resourcemanager.projects.getIamPolicy",
    "resourcemanager.projects.delete",
    "resourcemanager.projects.update",

    "iam.serviceAccounts.create",
    "iam.roles.create",

    "serviceusage.services.enable",
    "serviceusage.services.disable",
]

ORG_PERMISSIONS = [
    "resourcemanager.organizations.setIamPolicy",
    "resourcemanager.organizations.getIamPolicy",
    "resourcemanager.projects.create",
]

SERVICE_ACCOUNT_PERMISSIONS = [
    "iam.serviceAccounts.setIamPolicy",
    "iam.serviceAccounts.actAs",
    "iam.serviceAccountKeys.create",
    "iam.serviceAccounts.getAccessToken",
    "iam.serviceAccounts.signBlob",
    "iam.serviceAccounts.signJwt",
]


def test_permissions(session, url, permissions):
    r = session.post(
        url,
        json={"permissions": permissions},
        timeout=30,
    )

    try:
        body = r.json()
    except Exception:
        body = {
            "raw": r.text[:1000]
        }

    return {
        "http": r.status_code,
        "permissions": body.get("permissions", []),
        "error": body.get("error"),
    }


class PermissionCensus:
    def query(self, marker: str = ""):
        credentials, detected_project = google.auth.default(
            scopes=[
                "https://www.googleapis.com/auth/cloud-platform"
            ]
        )

        session = AuthorizedSession(credentials)

        project = test_permissions(
            session,
            (
                "https://cloudresourcemanager.googleapis.com/"
                f"v1/projects/{PROJECT}:testIamPermissions"
            ),
            PROJECT_PERMISSIONS,
        )

        organization = test_permissions(
            session,
            (
                "https://cloudresourcemanager.googleapis.com/"
                f"v3/organizations/{ORG}:testIamPermissions"
            ),
            ORG_PERMISSIONS,
        )

        encoded_sa = urllib.parse.quote(
            RUNTIME_SA,
            safe="",
        )

        service_account = test_permissions(
            session,
            (
                "https://iam.googleapis.com/v1/"
                f"projects/-/serviceAccounts/{encoded_sa}"
                ":testIamPermissions"
            ),
            SERVICE_ACCOUNT_PERMISSIONS,
        )

        project_setiam = (
            "resourcemanager.projects.setIamPolicy"
            in project["permissions"]
        )

        org_setiam = (
            "resourcemanager.organizations.setIamPolicy"
            in organization["permissions"]
        )

        return {
            "source": SOURCE,
            "marker": marker,
            "detected_project": detected_project,

            "project": project,
            "organization": organization,
            "service_account": service_account,

            "project_setIamPolicy": project_setiam,
            "organization_setIamPolicy": org_setiam,

            "S1A_PROJECT_PATH_OPEN": project_setiam,
            "S1A_ORG_PATH_OPEN": org_setiam,

            "mutations_performed": False,
            "token_printed": False,
        }


root_agent = PermissionCensus()

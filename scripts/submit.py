import os
import sys
import time

from asc_api import api, find_app_id, get_localization_id, get_or_create_version

APP_VERSION = os.environ.get("APP_VERSION", "1.0")
BUILD_NUMBER = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("BUILD_NUMBER", "")
REVIEW_CONTACT = {
    "contactFirstName": "Tokyo",
    "contactLastName": "Nasu",
    "contactEmail": "tokyonasu@yahoo.co.jp",
    "contactPhone": "+81 80-2368-9194",
}


def wait_for_build(app_id):
    print(f"Waiting for processed build (expecting build {BUILD_NUMBER or 'any'})...")
    for attempt in range(90):
        payload = api("GET", f"/builds?filter[app]={app_id}&sort=-uploadedDate&limit=10")
        for item in payload.get("data", []):
            attrs = item["attributes"]
            version = attrs.get("version", "")
            state = attrs.get("processingState", "")
            print(f"  build {version}: {state}")
            if BUILD_NUMBER and version == str(BUILD_NUMBER) and state == "VALID":
                return item["id"]
            if not BUILD_NUMBER and version and state == "VALID":
                return item["id"]
        print(f"  attempt {attempt + 1}/90, waiting 30s")
        time.sleep(30)
    raise RuntimeError(f"Target build {BUILD_NUMBER or 'any'} was not processed in time")


def update_review_detail(version_id):
    review_details = api("GET", f"/appStoreVersions/{version_id}/appStoreReviewDetail")
    attrs = {
        **REVIEW_CONTACT,
        "demoAccountRequired": False,
        "demoAccountName": "",
        "demoAccountPassword": "",
        "notes": (
            "This app uses the microphone to record and analyze sleep sounds (snoring, breathing). "
            "Recording happens only when the user explicitly starts a sleep session. "
            "AdMob ads are shown on the free tier. ATT permission is requested at launch. "
            "HealthKit entitlement is declared for future sleep data integration but not yet used for writes."
        ),
    }
    if review_details.get("data"):
        detail_id = review_details["data"]["id"]
        api("PATCH", f"/appStoreReviewDetails/{detail_id}", json={
            "data": {"type": "appStoreReviewDetails", "id": detail_id, "attributes": attrs}
        })
    else:
        api("POST", "/appStoreReviewDetails", json={
            "data": {
                "type": "appStoreReviewDetails",
                "attributes": attrs,
                "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}}},
            }
        })


def main():
    app_id = find_app_id()
    version_id = get_or_create_version(app_id, APP_VERSION)
    build_id = wait_for_build(app_id)

    try:
        api("PATCH", f"/builds/{build_id}", json={
            "data": {"type": "builds", "id": build_id, "attributes": {"usesNonExemptEncryption": False}}
        })
    except RuntimeError as e:
        if "409" in str(e):
            print("usesNonExemptEncryption already set, skipping")
        else:
            raise

    try:
        api("PATCH", f"/apps/{app_id}", json={
            "data": {
                "type": "apps",
                "id": app_id,
                "attributes": {"contentRightsDeclaration": "DOES_NOT_USE_THIRD_PARTY_CONTENT"},
            }
        })
    except RuntimeError as e:
        if "409" in str(e):
            print("contentRightsDeclaration already set, skipping")
        else:
            raise

    update_review_detail(version_id)

    for attempt in range(5):
        try:
            api("PATCH", f"/appStoreVersions/{version_id}/relationships/build", json={
                "data": {"type": "builds", "id": build_id}
            })
            print("Build linked to version")
            break
        except RuntimeError as e:
            if "409" in str(e):
                print("Build already linked to version, skipping")
                break
            if attempt < 4:
                print(f"Build link attempt {attempt + 1} failed, retrying in 30s...")
                time.sleep(30)
            else:
                raise

    loc_id = get_localization_id(version_id)
    if loc_id:
        try:
            api("PATCH", f"/appStoreVersionLocalizations/{loc_id}", json={
                "data": {
                    "type": "appStoreVersionLocalizations",
                    "id": loc_id,
                    "attributes": {
                        "whatsNew": "初回リリース。いびき検出・睡眠ステージ推定・無呼吸スクリーニング機能を搭載。",
                    },
                }
            })
            print("whatsNew set")
        except RuntimeError as e:
            if "409" in str(e):
                print("whatsNew already set, skipping")
            else:
                raise

    canceled = False
    for state in ["READY_FOR_REVIEW", "COMPLETING", "UNRESOLVED_ISSUES"]:
        try:
            existing = api("GET", f"/apps/{app_id}/reviewSubmissions?filter[state]={state}")
            for item in existing.get("data", []):
                try:
                    api("PATCH", f"/reviewSubmissions/{item['id']}", json={
                        "data": {"type": "reviewSubmissions", "id": item["id"], "attributes": {"canceled": True}}
                    })
                    print(f"Canceled review submission {item['id']}")
                    canceled = True
                except RuntimeError:
                    pass
        except RuntimeError:
            pass

    if canceled:
        print("Waiting for cancellation to propagate...")
        time.sleep(20)

    for attempt in range(4):
        try:
            review = api("POST", "/reviewSubmissions", json={
                "data": {
                    "type": "reviewSubmissions",
                    "attributes": {"platform": "IOS"},
                    "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
                }
            })
            review_id = review["data"]["id"]

            api("POST", "/reviewSubmissionItems", json={
                "data": {
                    "type": "reviewSubmissionItems",
                    "relationships": {
                        "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": review_id}},
                        "appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}},
                    },
                }
            })

            api("PATCH", f"/reviewSubmissions/{review_id}", json={
                "data": {"type": "reviewSubmissions", "id": review_id, "attributes": {"submitted": True}}
            })
            print("Submitted for review")
            break
        except RuntimeError as e:
            if "409" in str(e) and attempt < 3:
                print(f"Submit attempt {attempt + 1} failed (409), waiting 20s...")
                time.sleep(20)
            else:
                raise


if __name__ == "__main__":
    main()

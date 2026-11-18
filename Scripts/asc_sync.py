#!/usr/bin/env python3
"""App Store Connect 10-Locale & Hybrid Trial+Lifetime Sync for WaitCam (com.yanghe.waitcam).

Uses ~/.appstoreconnect/private_keys/AuthKey_BD4GFRDCQ9.p8.
Once the App Record (com.yanghe.waitcam) is created in App Store Connect, run:
  python3 /Users/wang/OPC/projects/waitcam/Scripts/asc_sync.py --all
"""

from __future__ import annotations
import base64
import hashlib
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

KEY_ID = "BD4GFRDCQ9"
ISSUER_ID = "ccf96e7a-0987-4f4b-aa61-863fccd82c33"
KEY_PATH = "/Users/wang/.appstoreconnect/private_keys/AuthKey_BD4GFRDCQ9.p8"
BUNDLE_ID = "com.yanghe.waitcam"

PROJECT_ROOT = Path("/Users/wang/OPC/projects/waitcam")
METADATA_JSON = PROJECT_ROOT / "release" / "ASC_METADATA_READY.json"
SCREENSHOT_ROOT = Path("/Users/wang/OPC/media/20261118-waitcam/appstore")


def b64u(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def make_jwt() -> str:
    header = b64u(json.dumps({"alg": "ES256", "kid": KEY_ID, "typ": "JWT"}, separators=(",", ":")).encode())
    now = int(time.time())
    payload = b64u(
        json.dumps(
            {"iss": ISSUER_ID, "iat": now - 10, "exp": now + 900, "aud": "appstoreconnect-v1"},
            separators=(",", ":"),
        ).encode()
    )
    msg = f"{header}.{payload}".encode()
    der = subprocess.check_output(["openssl", "dgst", "-sha256", "-sign", KEY_PATH], input=msg)
    idx = 2 + ((der[1] & 0x7F) if (der[1] & 0x80) else 0)
    rlen = der[idx + 1]
    r = der[idx + 2 : idx + 2 + rlen].lstrip(b"\x00").rjust(32, b"\x00")
    idx = idx + 2 + rlen
    slen = der[idx + 1]
    s = der[idx + 2 : idx + 2 + slen].lstrip(b"\x00").rjust(32, b"\x00")
    return f"{header}.{payload}.{b64u(r + s)}"


def asc(method: str, path: str, body: dict | None = None) -> tuple[int, dict | str]:
    token = make_jwt()
    data = json.dumps(body).encode() if body is not None else None
    headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}
    req = urllib.request.Request(f"https://api.appstoreconnect.apple.com{path}", data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read().decode()
            return resp.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()


def main() -> None:
    meta = json.loads(METADATA_JSON.read_text(encoding="utf-8"))
    st, apps = asc("GET", f"/v1/apps?filter[bundleId]={BUNDLE_ID}")
    if st != 200 or not isinstance(apps, dict) or not apps.get("data"):
        print(f"ℹ️ Bundle ID '{BUNDLE_ID}' is registered on Apple Developer Portal.")
        print("👉 Next: Click '+' -> 'New App' once in App Store Connect web selecting 'com.yanghe.waitcam', then re-run this script to auto-fill all 10 locales, 3-day free trial subscription, lifetime IAP, and screenshots.")
        return

    app_id = apps["data"][0]["id"]
    print(f"✅ Found App Record id={app_id} for {BUNDLE_ID}")

    # Sync AppInfo & Version Localizations across 10 global locales
    st_i, infos = asc("GET", f"/v1/apps/{app_id}/appInfos")
    app_info_id = infos["data"][0]["id"]
    _, existing_ilocs = asc("GET", f"/v1/appInfos/{app_info_id}/appInfoLocalizations?limit=50")
    iloc_map = {x["attributes"]["locale"]: x["id"] for x in existing_ilocs.get("data", [])}

    st_v, vers = asc("GET", f"/v1/apps/{app_id}/appStoreVersions?filter[platform]=IOS")
    ver_id = vers["data"][0]["id"]
    _, existing_vlocs = asc("GET", f"/v1/appStoreVersions/{ver_id}/appStoreVersionLocalizations?limit=50")
    vloc_map = {x["attributes"]["locale"]: x["id"] for x in existing_vlocs.get("data", [])}

    base_desc_en = (
        "Shoot tonight, reveal tomorrow. WaitCam brings back the authentic magic of a 35mm disposable party camera—100% offline with zero watermarks.\n\n"
        "• Real 12-Hour Darkroom Lock: No peeking! Watch your film roll develop live on your Dynamic Island & Lock Screen.\n"
        "• 4 Cinema Film Stocks: Free 2AM Party Flash, plus 800T Neon Halation, Chrome 100 Gold & Club 400 Mono.\n"
        "• 1-Tap 35mm Film Reels & Contact Sheets: Turn developed rolls into sprocket-hole MP4 Reels for Stories, TikTok & Moments.\n"
        "• Transparent 3-Day Free Trial (with Day-2 Reminder Notification) or One-Time Lifetime Unlock.\n\n"
        "Privacy Policy: https://a3152557994-ship-it.github.io/waitcam/privacy.html\n"
        "Terms of Use (EULA): https://a3152557994-ship-it.github.io/waitcam/terms.html"
    )

    for locale, ldata in meta["localizations"].items():
        if locale in iloc_map:
            asc("PATCH", f"/v1/appInfoLocalizations/{iloc_map[locale]}", {
                "data": {
                    "type": "appInfoLocalizations",
                    "id": iloc_map[locale],
                    "attributes": {
                        "name": ldata["name"],
                        "subtitle": ldata["subtitle"],
                        "privacyPolicyUrl": ldata["privacyPolicyUrl"],
                    },
                }
            })
        else:
            asc("POST", "/v1/appInfoLocalizations", {
                "data": {
                    "type": "appInfoLocalizations",
                    "attributes": {
                        "locale": locale,
                        "name": ldata["name"],
                        "subtitle": ldata["subtitle"],
                        "privacyPolicyUrl": ldata["privacyPolicyUrl"],
                    },
                    "relationships": {"appInfo": {"data": {"type": "appInfos", "id": app_info_id}}},
                }
            })

        if locale in vloc_map:
            asc("PATCH", f"/v1/appStoreVersionLocalizations/{vloc_map[locale]}", {
                "data": {
                    "type": "appStoreVersionLocalizations",
                    "id": vloc_map[locale],
                    "attributes": {
                        "keywords": ldata["keywords"],
                        "supportUrl": ldata["supportUrl"],
                        "description": base_desc_en,
                    },
                }
            })
        else:
            asc("POST", "/v1/appStoreVersionLocalizations", {
                "data": {
                    "type": "appStoreVersionLocalizations",
                    "attributes": {
                        "locale": locale,
                        "keywords": ldata["keywords"],
                        "supportUrl": ldata["supportUrl"],
                        "description": base_desc_en,
                    },
                    "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": ver_id}}},
                }
            })
        print(f"  ✓ Synced locale: {locale} ({ldata['name']})")


if __name__ == "__main__":
    main()

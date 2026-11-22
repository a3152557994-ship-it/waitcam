#!/usr/bin/env python3
"""App Store Connect Complete Sync & Submission Prep for WaitCam (com.yanghe.waitcam).

Modeled directly on the verified 2026-11-20 CleanShield ASC sync workflow.
Uses ~/.appstoreconnect/private_keys/AuthKey_BD4GFRDCQ9.p8 via stdlib + openssl.

Usage:
  python3 /Users/wang/OPC/projects/waitcam/Scripts/asc_sync.py [--upload-ipa] [--wait-build] [--all] [--check]
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any, Optional

KEY_ID = "BD4GFRDCQ9"
ISSUER_ID = "ccf96e7a-0987-4f4b-aa61-863fccd82c33"
KEY_PATH = "/Users/wang/.appstoreconnect/private_keys/AuthKey_BD4GFRDCQ9.p8"
BUNDLE_ID = "com.yanghe.waitcam"

PROJECT_ROOT = Path("/Users/wang/OPC/projects/waitcam")
METADATA_JSON = PROJECT_ROOT / "release" / "ASC_METADATA_READY.json"
IPA_PATH = PROJECT_ROOT / "dist" / "ipa" / "WaitCam.ipa"
SCREENSHOT_ROOT = Path("/Users/wang/OPC/media/20261118-waitcam/appstore")

PROMO_TEXT_EN = (
    "Shoot tonight, reveal tomorrow! Free 2AM Party Flash with zero watermarks, "
    "1-tap 35mm Reel MP4 export & transparent 3-day trial with Day-2 reminder."
)
PROMO_TEXT_ZH_HANS = (
    "今晚按下快门，12 小时后次日揭晓！基础 2AM 派对闪光灯永久无水印，"
    "一键导出 35mm 晒片短片，3 天免费试用配第 2 天到期贴心提醒。"
)
PROMO_TEXT_ZH_HANT = (
    "今晚按下快門，12 小時後次日揭曉！基礎 2AM 派對閃光燈永久無浮水印，"
    "一鍵匯出 35mm 底片短片，3 天免費試用配第 2 天到期貼心提醒。"
)

DESC_EN = (
    "Shoot tonight, reveal tomorrow. WaitCam brings back the authentic magic of a 35mm disposable party camera—100% offline with zero watermarks.\n\n"
    "• Real 12-Hour Darkroom Lock: No peeking! Watch your film roll develop live on your Dynamic Island & Lock Screen, or enable the 30-second Demo Mode anytime in Lab Settings.\n"
    "• 4 Cinema Film Stocks: Free 2AM Party Flash (zero watermarks), plus 800T Neon Halation, Chrome 100 Gold & Club 400 Mono.\n"
    "• 1-Tap 35mm Film Reels & Contact Sheets: Export developed rolls into authentic sprocket-hole MP4 Reels or high-res contact sheets offline.\n"
    "• 100% Private AES-256 Local Vault: Every frame stays encrypted on your iPhone or iPad with zero servers or tracking.\n\n"
    "SUBSCRIPTION & UNLOCK OPTIONS (GUIDELINE 3.1.2):\n"
    "• WaitCam Pro Annual (\$14.99/year): Includes a transparent 3-day \$0 free trial plus an optional Day-2 local notification reminder 24 hours before billing, and auto-renews yearly unless canceled in iOS Settings at least 24 hours before the period ends.\n"
    "• WaitCam Pro Lifetime (\$9.99 one-time Black Friday offer) & Darkroom Plus (\$2.99 one-time): Permanent non-consumable unlocks with Family Sharing.\n\n"
    "Privacy Policy: https://a3152557994-ship-it.github.io/waitcam/privacy.html\n"
    "Terms of Use (EULA): https://a3152557994-ship-it.github.io/waitcam/terms.html"
).replace("\\$", "$")

DESC_ZH_HANS = (
    "今晚按下快门，12 小时后次日揭晓！WaitCam 将经典 35mm 一次性派对胶卷相机的等待仪式感带回 iPhone 与 iPad —— 100% 纯本地离线暗房，基础成片永久无水印。\n\n"
    "• 真实 12 小时暗房封存：拍摄期间禁止偷看成片！可在灵动岛与锁屏实时追踪显影倒计时（实验室设置内亦提供 30 秒极速体验模式）。\n"
    "• 4 款电影级胶片影调：免费标配 2AM 派对闪光灯（零水印直出），另有 800T 霓虹晕影、Chrome 100 复古金与 Club 400 黑白。\n"
    "• 一键导出 35mm 带齿孔晒片短片与接触印相单：显影揭晓后纯本地生成竖屏 H.264 MP4 短片或整卷印相单，直发小红书与朋友圈。\n"
    "• AES-256 纯本地私密暗房：零服务器、零账号登录、零隐私追踪，所有胶卷仅存于您的设备本地。\n\n"
    "订阅与解锁说明：\n"
    "• WaitCam Pro 年度会员（¥38/年 或 \$14.99/年）：首开享 3 天 ¥0 免费试用，并于试用第 2 天（扣费前 24 小时）发送本地提醒通知；除非在当期结束前至少 24 小时于系统「设置 -> Apple 账户 -> 订阅」中取消，否则将自动续期。\n"
    "• 黑五终身买断 Pro（¥28 一次买断）与 暗房轻量版（¥8 一次买断）：非消耗型永久解锁并支持家人共享。\n\n"
    "隐私政策：https://a3152557994-ship-it.github.io/waitcam/privacy.html\n"
    "使用条款 (EULA)：https://a3152557994-ship-it.github.io/waitcam/terms.html"
).replace("\\$", "$")

DESC_ZH_HANT = (
    "今晚按下快門，12 小時後次日揭曉！WaitCam 將經典 35mm 即可拍派對底片相機的等待儀式感帶回 iPhone 與 iPad —— 100% 純本地離線暗房，基礎成片永久無浮水印。\n\n"
    "• 真實 12 小時暗房封存：拍攝期間禁止偷看成片！可在動態島與鎖定畫面即時追蹤顯影倒數（實驗室設定亦提供 30 秒極速體驗模式）。\n"
    "• 4 款電影級底片色調：免費標配 2AM 派對閃光燈（無浮水印直出），另有 800T 霓虹光暈、Chrome 100 復古金與 Club 400 黑白。\n"
    "• 一鍵匯出 35mm 齒孔短片與接觸印相單：顯影揭曉後純本地產生直式 H.264 MP4 短片或整卷印相單。\n"
    "• AES-256 純本地私密暗房：零伺服器、零帳號登入、零追蹤。\n\n"
    "訂閱與解鎖說明：\n"
    "• WaitCam Pro 年度方案（\$14.99/年）：提供 3 天 \$0 免費試用並附帶第 2 天本地到期提醒通知；除非在週期結束前至少 24 小時於系統設定取消，否則將自動續訂。\n"
    "• 終身買斷 Pro（\$9.99 一次買斷）與 Darkroom Plus（\$2.99 一次買斷）：支援家人共享。\n\n"
    "隱私權政策：https://a3152557994-ship-it.github.io/waitcam/privacy.html\n"
    "使用條款 (EULA)：https://a3152557994-ship-it.github.io/waitcam/terms.html"
).replace("\\$", "$")


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


def asc(method: str, path: str, body: dict | None = None) -> tuple[int, dict[str, Any] | str]:
    token = make_jwt()
    data = json.dumps(body).encode() if body is not None else None
    headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}
    url = path if path.startswith("http") else f"https://api.appstoreconnect.apple.com{path}"
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read().decode()
            return resp.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, raw


def find_closest_price_point(endpoint: str, target_price: float) -> Optional[str]:
    next_url: Optional[str] = endpoint
    best_id: Optional[str] = None
    best_diff = 99999.0
    pages = 0
    while next_url and pages < 6:
        pages += 1
        st, res = asc("GET", next_url)
        if st != 200 or not isinstance(res, dict):
            return best_id
        for pp in res.get("data", []):
            p_str = pp.get("attributes", {}).get("customerPrice")
            if p_str is None:
                continue
            try:
                val = float(p_str)
            except ValueError:
                continue
            diff = abs(val - target_price)
            if diff < best_diff:
                best_diff = diff
                best_id = pp["id"]
                if diff <= 0.01:
                    return best_id
        next_url = res.get("links", {}).get("next")
    return best_id


def get_all_territory_ids() -> list[str]:
    st, res = asc("GET", "/v1/territories?limit=200")
    if st == 200 and isinstance(res, dict):
        return [t["id"] for t in res.get("data", [])]
    return ["USA", "CHN"]


def upload_binary_asset(
    reserve_endpoint: str,
    commit_endpoint_prefix: str,
    resource_type: str,
    rel_key: str,
    rel_type: str,
    rel_id: str,
    png_path: Path,
) -> None:
    raw_bytes = png_path.read_bytes()
    checksum = hashlib.md5(raw_bytes).hexdigest()
    st, res = asc("POST", reserve_endpoint, {
        "data": {
            "type": resource_type,
            "attributes": {"fileSize": len(raw_bytes), "fileName": png_path.name},
            "relationships": {rel_key: {"data": {"type": rel_type, "id": rel_id}}},
        }
    })
    if st not in (200, 201) or not isinstance(res, dict):
        print(f"    ! Asset reserve failed ({reserve_endpoint}) for {png_path.name}: {st} {res}")
        return
    asset_id = res["data"]["id"]
    for op in res["data"]["attributes"].get("uploadOperations", []):
        chunk = raw_bytes[op["offset"] : op["offset"] + op["length"]]
        hdrs = {h["name"]: h["value"] for h in op.get("requestHeaders", [])}
        req = urllib.request.Request(op["url"], data=chunk, headers=hdrs, method=op["method"])
        urllib.request.urlopen(req, timeout=60).read()
    st_c, res_c = asc("PATCH", f"{commit_endpoint_prefix}/{asset_id}", {
        "data": {
            "type": resource_type,
            "id": asset_id,
            "attributes": {"uploaded": True, "sourceFileChecksum": checksum},
        }
    })
    print(f"    Uploaded {png_path.name} ({resource_type}) -> {st_c}")
    if st_c not in (200, 204):
        print("      commit note:", res_c)


def sync_screenshot_set(vloc_id: str, display_type: str, folder: Path) -> None:
    pngs = sorted(folder.glob("*.png"))
    if not pngs:
        print(f"    ! No PNGs in {folder}")
        return
    _, sets = asc("GET", f"/v1/appStoreVersionLocalizations/{vloc_id}/appScreenshotSets")
    set_id = None
    for s in sets.get("data", []) if isinstance(sets, dict) else []:
        if s["attributes"]["screenshotDisplayType"] == display_type:
            set_id = s["id"]
            break
    if set_id:
        _, existing = asc("GET", f"/v1/appScreenshotSets/{set_id}/appScreenshots")
        existing_items = existing.get("data", []) if isinstance(existing, dict) else []
        if len(existing_items) == len(pngs):
            print(f"    • {display_type} already has {len(existing_items)} screenshots in {folder.name}, skipping.")
            return
        for item in existing_items:
            asc("DELETE", f"/v1/appScreenshots/{item['id']}")
    else:
        st_c, cset = asc("POST", "/v1/appScreenshotSets", {
            "data": {
                "type": "appScreenshotSets",
                "attributes": {"screenshotDisplayType": display_type},
                "relationships": {"appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": vloc_id}}},
            }
        })
        if st_c in (200, 201) and isinstance(cset, dict):
            set_id = cset["data"]["id"]
        else:
            print(f"    ! Create screenshotSet {display_type} failed: {st_c} {cset}")
    if set_id:
        for png in pngs:
            upload_binary_asset("/v1/appScreenshots", "/v1/appScreenshots", "appScreenshots", "appScreenshotSet", "appScreenshotSets", set_id, png)


def attach_valid_build(app_id: str, ver_id: str, wait_build: bool = False) -> Optional[dict[str, Any]]:
    attempts = 20 if wait_build else 1
    for attempt in range(1, attempts + 1):
        _, blds = asc("GET", f"/v1/builds?filter[app]={app_id}&sort=-uploadedDate&limit=10")
        builds = blds.get("data", []) if isinstance(blds, dict) else []
        valid_build = next((b for b in builds if b["attributes"].get("processingState") == "VALID"), None)
        if valid_build:
            st_b, res_b = asc("PATCH", f"/v1/appStoreVersions/{ver_id}/relationships/build", {
                "data": {"type": "builds", "id": valid_build["id"]}
            })
            print(f"  Attached VALID build {valid_build['attributes']['version']} ({valid_build['id']}) -> {st_b}")
            if st_b not in (200, 204):
                print("   ", res_b)
            return valid_build
        if not wait_build or attempt == attempts:
            states = [(b["attributes"].get("version"), b["attributes"].get("processingState")) for b in builds]
            print(f"  No VALID build ready yet (seen: {states}).")
            return None
        print(f"  Waiting 15s for build processing ({attempt}/{attempts})...")
        time.sleep(15)
    return None


def sync_app_metadata_and_version(
    app_id: str,
    meta: dict[str, Any],
    territories: list[str],
    wait_build: bool = False,
) -> str:
    print(f"[1/5] Updating App rights, categories & 4+ age rating for {app_id}...")
    st_app, res_app = asc("PATCH", f"/v1/apps/{app_id}", {
        "data": {
            "type": "apps",
            "id": app_id,
            "attributes": {
                "contentRightsDeclaration": "DOES_NOT_USE_THIRD_PARTY_CONTENT",
                "primaryLocale": "en-US",
            },
        }
    })
    print("  PATCH /v1/apps ->", st_app)
    if st_app not in (200, 204):
        print("   ", res_app)

    _, infos = asc("GET", f"/v1/apps/{app_id}/appInfos")
    app_info_id = infos["data"][0]["id"]
    st_cat, res_cat = asc("PATCH", f"/v1/appInfos/{app_info_id}", {
        "data": {
            "type": "appInfos",
            "id": app_info_id,
            "relationships": {
                "primaryCategory": {"data": {"type": "appCategories", "id": "PHOTO_AND_VIDEO"}},
                "secondaryCategory": {"data": {"type": "appCategories", "id": "LIFESTYLE"}},
            },
        }
    })
    print("  PATCH appInfos categories (PHOTO_AND_VIDEO / LIFESTYLE) ->", st_cat)
    if st_cat not in (200, 204):
        print("   ", res_cat)

    _, age_res = asc("GET", f"/v1/appInfos/{app_info_id}/ageRatingDeclaration")
    if isinstance(age_res, dict) and age_res.get("data"):
        age_id = age_res["data"]["id"]
        st_age, res_age = asc("PATCH", f"/v1/ageRatingDeclarations/{age_id}", {
            "data": {
                "type": "ageRatingDeclarations",
                "id": age_id,
                "attributes": {
                    "advertising": False,
                    "alcoholTobaccoOrDrugUseOrReferences": "NONE",
                    "contests": "NONE",
                    "gambling": False,
                    "gamblingSimulated": "NONE",
                    "gunsOrOtherWeapons": "NONE",
                    "healthOrWellnessTopics": False,
                    "kidsAgeBand": None,
                    "lootBox": False,
                    "medicalOrTreatmentInformation": "NONE",
                    "messagingAndChat": False,
                    "parentalControls": False,
                    "profanityOrCrudeHumor": "NONE",
                    "ageAssurance": False,
                    "sexualContentGraphicAndNudity": "NONE",
                    "sexualContentOrNudity": "NONE",
                    "socialMedia": False,
                    "socialMediaAgeRestricted": False,
                    "horrorOrFearThemes": "NONE",
                    "matureOrSuggestiveThemes": "NONE",
                    "unrestrictedWebAccess": False,
                    "userGeneratedContent": False,
                    "violenceCartoonOrFantasy": "NONE",
                    "violenceRealisticProlongedGraphicOrSadistic": "NONE",
                    "violenceRealistic": "NONE",
                },
            }
        })
        print("  PATCH ageRatingDeclarations (4+) ->", st_age)
        if st_age not in (200, 204):
            print("   ", res_age)

    print("[2/5] Ensuring App Availability & Free Base Pricing...")
    st_av, _ = asc("GET", f"/v2/appAvailabilities/{app_id}")
    if st_av == 404:
        avail_refs = [{"type": "territoryAvailabilities", "id": f"${{ta-{t}}}"} for t in territories]
        avail_inc = [
            {
                "type": "territoryAvailabilities",
                "id": f"${{ta-{t}}}",
                "attributes": {"available": True, "releaseDate": None, "preOrderEnabled": False},
                "relationships": {"territory": {"data": {"type": "territories", "id": t}}},
            }
            for t in territories
        ]
        st_post_av, res_post_av = asc("POST", "/v2/appAvailabilities", {
            "data": {
                "type": "appAvailabilities",
                "attributes": {"availableInNewTerritories": True},
                "relationships": {
                    "app": {"data": {"type": "apps", "id": app_id}},
                    "territoryAvailabilities": {"data": avail_refs},
                },
            },
            "included": avail_inc,
        })
        print(f"  POST /v2/appAvailabilities ({len(territories)} territories) -> {st_post_av}")
        if st_post_av not in (200, 201):
            print("   ", res_post_av)
    else:
        print("  • App Availability already configured.")

    usa_pp = find_closest_price_point(f"/v1/apps/{app_id}/appPricePoints?filter[territory]=USA&limit=50", 0.0)
    chn_pp = find_closest_price_point(f"/v1/apps/{app_id}/appPricePoints?filter[territory]=CHN&limit=50", 0.0)
    if usa_pp:
        manual_refs = [{"type": "appPrices", "id": "${price-usa}"}]
        included = [{
            "type": "appPrices",
            "id": "${price-usa}",
            "attributes": {"startDate": None},
            "relationships": {"appPricePoint": {"data": {"type": "appPricePoints", "id": usa_pp}}},
        }]
        if chn_pp:
            manual_refs.append({"type": "appPrices", "id": "${price-chn}"})
            included.append({
                "type": "appPrices",
                "id": "${price-chn}",
                "attributes": {"startDate": None},
                "relationships": {"appPricePoint": {"data": {"type": "appPricePoints", "id": chn_pp}}},
            })
        st_ps, res_ps = asc("POST", "/v1/appPriceSchedules", {
            "data": {
                "type": "appPriceSchedules",
                "relationships": {
                    "app": {"data": {"type": "apps", "id": app_id}},
                    "baseTerritory": {"data": {"type": "territories", "id": "USA"}},
                    "manualPrices": {"data": manual_refs},
                },
            },
            "included": included,
        })
        print("  POST appPriceSchedules (FREE) ->", st_ps)
        if st_ps not in (200, 201):
            print("   ", res_ps)

    print("[3/5] Syncing Version 1.0.0, 10 Localizations, Screenshots, ReviewDetails & Build...")
    _, vers = asc("GET", f"/v1/apps/{app_id}/appStoreVersions?filter[platform]=IOS")
    ver_id = vers["data"][0]["id"]
    st_v, res_v = asc("PATCH", f"/v1/appStoreVersions/{ver_id}", {
        "data": {
            "type": "appStoreVersions",
            "id": ver_id,
            "attributes": {
                "versionString": "1.0.0",
                "copyright": "2026 Yang He",
                "releaseType": "AFTER_APPROVAL",
            },
        }
    })
    print("  PATCH appStoreVersions (1.0.0 / 2026 Yang He) ->", st_v)
    if st_v not in (200, 204):
        print("   ", res_v)

    _, existing_ilocs = asc("GET", f"/v1/appInfos/{app_info_id}/appInfoLocalizations?limit=50")
    iloc_map = {x["attributes"]["locale"]: x["id"] for x in existing_ilocs.get("data", [])}
    _, existing_vlocs = asc("GET", f"/v1/appStoreVersions/{ver_id}/appStoreVersionLocalizations?limit=50")
    vloc_map = {x["attributes"]["locale"]: x["id"] for x in existing_vlocs.get("data", [])}

    for locale, ldata in meta["localizations"].items():
        i_attrs = {
            "name": ldata["name"],
            "subtitle": ldata["subtitle"],
            "privacyPolicyUrl": ldata["privacyPolicyUrl"],
        }
        if locale in iloc_map:
            st_il, _ = asc("PATCH", f"/v1/appInfoLocalizations/{iloc_map[locale]}", {
                "data": {"type": "appInfoLocalizations", "id": iloc_map[locale], "attributes": i_attrs}
            })
            if st_il == 409:
                # Preserve existing unique App Name if en-US name used fallback
                asc("PATCH", f"/v1/appInfoLocalizations/{iloc_map[locale]}", {
                    "data": {
                        "type": "appInfoLocalizations",
                        "id": iloc_map[locale],
                        "attributes": {"subtitle": ldata["subtitle"], "privacyPolicyUrl": ldata["privacyPolicyUrl"]},
                    }
                })
        else:
            asc("POST", "/v1/appInfoLocalizations", {
                "data": {
                    "type": "appInfoLocalizations",
                    "attributes": {"locale": locale, **i_attrs},
                    "relationships": {"appInfo": {"data": {"type": "appInfos", "id": app_info_id}}},
                }
            })

        if locale == "zh-Hans":
            desc_text, promo_text = DESC_ZH_HANS, PROMO_TEXT_ZH_HANS
        elif locale == "zh-Hant":
            desc_text, promo_text = DESC_ZH_HANT, PROMO_TEXT_ZH_HANT
        else:
            desc_text, promo_text = DESC_EN, PROMO_TEXT_EN

        v_attrs = {
            "keywords": ldata["keywords"],
            "supportUrl": ldata["supportUrl"],
            "marketingUrl": "https://a3152557994-ship-it.github.io/waitcam/",
            "promotionalText": promo_text,
            "description": desc_text,
        }
        if locale in vloc_map:
            vloc_id = vloc_map[locale]
            st_vl, res_vl = asc("PATCH", f"/v1/appStoreVersionLocalizations/{vloc_id}", {
                "data": {"type": "appStoreVersionLocalizations", "id": vloc_id, "attributes": v_attrs}
            })
            print(f"  PATCH versionLoc {locale} ({ldata['name']}) -> {st_vl}")
            if st_vl not in (200, 204):
                print("   ", res_vl)
        else:
            st_vl, created_vl = asc("POST", "/v1/appStoreVersionLocalizations", {
                "data": {
                    "type": "appStoreVersionLocalizations",
                    "attributes": {"locale": locale, **v_attrs},
                    "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": ver_id}}},
                }
            })
            vloc_id = created_vl["data"]["id"] if isinstance(created_vl, dict) and "data" in created_vl else None
            print(f"  POST versionLoc {locale} ({ldata['name']}) -> {st_vl}")

        if vloc_id and locale in ("en-US", "zh-Hans"):
            print(f"  Syncing iPhone 6.5\" & iPad 13\" screenshots for {locale}...")
            sync_screenshot_set(vloc_id, "APP_IPHONE_65", SCREENSHOT_ROOT / locale)
            sync_screenshot_set(vloc_id, "APP_IPAD_PRO_3GEN_129", SCREENSHOT_ROOT / "ipad" / locale)

    review_notes = (
        "WaitCam is a 100% offline 35mm disposable film camera app with zero servers and zero login required.\n\n"
        "How to test every feature quickly:\n"
        "1. Free Core Tier: Shoot photos with the free '2AM Party Flash' stock and export watermark-free images, 35mm Reel MP4 videos, and contact sheets directly to Photos.\n"
        "2. 30-Second Demo Roll (skip 12h Darkroom wait): Open Lab Settings (gear icon) and enable Demo Mode (30-second roll unlock) so you can immediately verify shooting, Dynamic Island/Live Activity darkroom countdown, and full reveal.\n"
        "3. StoreKit 2 Hybrid Paywall: Tap any locked Pro film stock ('800T Neon Halation', 'Chrome 100', 'Club 400 Mono') to open ImpulsePaywallSheetView, showing:\n"
        "   - WaitCam Pro Annual (\$14.99/yr) with transparent 3-day \$0 Free Trial + Day-2 local reminder toggle\n"
        "   - WaitCam Pro Lifetime (\$9.99 one-time Black Friday unlock)\n"
        "   - Darkroom Plus (\$2.99 one-time unlock)\n"
        "   - Restore Purchases, Privacy Policy & Terms of Use (EULA) links, plus dismiss close button."
    ).replace("\\$", "$")
    review_attrs = {
        "contactFirstName": "Yang",
        "contactLastName": "He",
        "contactPhone": "+86 196 3394 8182",
        "contactEmail": "a3152557994@gmail.com",
        "demoAccountRequired": False,
        "notes": review_notes,
    }
    st_r, res_r = asc("GET", f"/v1/appStoreVersions/{ver_id}/appStoreReviewDetail")
    if st_r == 200 and isinstance(res_r, dict) and res_r.get("data"):
        rd_id = res_r["data"]["id"]
        st_rp, _ = asc("PATCH", f"/v1/appStoreReviewDetails/{rd_id}", {
            "data": {"type": "appStoreReviewDetails", "id": rd_id, "attributes": review_attrs}
        })
        print("  PATCH appStoreReviewDetails ->", st_rp)
    else:
        st_rp, _ = asc("POST", "/v1/appStoreReviewDetails", {
            "data": {
                "type": "appStoreReviewDetails",
                "attributes": review_attrs,
                "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": ver_id}}},
            }
        })
        print("  POST appStoreReviewDetails ->", st_rp)

    attach_valid_build(app_id, ver_id, wait_build=wait_build)
    return ver_id


def sync_non_consumable_iap(
    app_id: str,
    territories: list[str],
    product_id: str,
    ref_name: str,
    usa_price: float,
    chn_price: float,
    locs: dict[str, dict[str, str]],
    review_note: str,
    review_shot: Path,
    existing_iaps: dict[str, str],
) -> None:
    iap_id = existing_iaps.get(product_id)
    if not iap_id:
        st_c, created = asc("POST", "/v2/inAppPurchases", {
            "data": {
                "type": "inAppPurchases",
                "attributes": {
                    "name": ref_name,
                    "productId": product_id,
                    "inAppPurchaseType": "NON_CONSUMABLE",
                    "familySharable": True,
                    "reviewNote": review_note,
                },
                "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
            }
        })
        print(f"  POST /v2/inAppPurchases ({product_id}) -> {st_c}")
        if st_c in (200, 201) and isinstance(created, dict):
            iap_id = created["data"]["id"]
        else:
            print("   ", created)
            return
    else:
        asc("PATCH", f"/v2/inAppPurchases/{iap_id}", {
            "data": {
                "type": "inAppPurchases",
                "id": iap_id,
                "attributes": {"familySharable": True, "reviewNote": review_note},
            }
        })

    _, cur_locs = asc("GET", f"/v2/inAppPurchases/{iap_id}/inAppPurchaseLocalizations")
    exist_ll = {x["attributes"]["locale"]: x["id"] for x in cur_locs.get("data", []) if isinstance(cur_locs, dict)}
    for loc, attrs in locs.items():
        if loc in exist_ll:
            asc("PATCH", f"/v1/inAppPurchaseLocalizations/{exist_ll[loc]}", {
                "data": {"type": "inAppPurchaseLocalizations", "id": exist_ll[loc], "attributes": attrs}
            })
        else:
            st_l, res_l = asc("POST", "/v1/inAppPurchaseLocalizations", {
                "data": {
                    "type": "inAppPurchaseLocalizations",
                    "attributes": {"locale": loc, **attrs},
                    "relationships": {"inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": iap_id}}},
                }
            })
            print(f"    POST iapLoc {product_id} {loc} -> {st_l}")
            if st_l not in (200, 201):
                print("     ", res_l)

    st_ia, _ = asc("GET", f"/v2/inAppPurchases/{iap_id}/inAppPurchaseAvailability")
    if st_ia == 404:
        st_p, res_p = asc("POST", "/v1/inAppPurchaseAvailabilities", {
            "data": {
                "type": "inAppPurchaseAvailabilities",
                "attributes": {"availableInNewTerritories": True},
                "relationships": {
                    "inAppPurchase": {"data": {"type": "inAppPurchases", "id": iap_id}},
                    "availableTerritories": {"data": [{"type": "territories", "id": t} for t in territories]},
                },
            }
        })
        print(f"    POST inAppPurchaseAvailabilities {product_id} ({len(territories)}) -> {st_p}")
        if st_p not in (200, 201):
            print("     ", res_p)

    usa_pp = find_closest_price_point(f"/v2/inAppPurchases/{iap_id}/pricePoints?filter[territory]=USA&limit=200", usa_price)
    chn_pp = find_closest_price_point(f"/v2/inAppPurchases/{iap_id}/pricePoints?filter[territory]=CHN&limit=200", chn_price)
    if usa_pp:
        mrefs = [{"type": "inAppPurchasePrices", "id": "${iap-usa}"}]
        incs = [{
            "type": "inAppPurchasePrices",
            "id": "${iap-usa}",
            "attributes": {"startDate": None},
            "relationships": {
                "inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": iap_id}},
                "inAppPurchasePricePoint": {"data": {"type": "inAppPurchasePricePoints", "id": usa_pp}},
            },
        }]
        if chn_pp:
            mrefs.append({"type": "inAppPurchasePrices", "id": "${iap-chn}"})
            incs.append({
                "type": "inAppPurchasePrices",
                "id": "${iap-chn}",
                "attributes": {"startDate": None},
                "relationships": {
                    "inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": iap_id}},
                    "inAppPurchasePricePoint": {"data": {"type": "inAppPurchasePricePoints", "id": chn_pp}},
                },
            })
        st_ip, res_ip = asc("POST", "/v1/inAppPurchasePriceSchedules", {
            "data": {
                "type": "inAppPurchasePriceSchedules",
                "relationships": {
                    "inAppPurchase": {"data": {"type": "inAppPurchases", "id": iap_id}},
                    "baseTerritory": {"data": {"type": "territories", "id": "USA"}},
                    "manualPrices": {"data": mrefs},
                },
            },
            "included": incs,
        })
        print(f"    POST iapPriceSchedule {product_id} (\${usa_price} / ¥{chn_price}) -> {st_ip}".replace("\\$", "$"))
        if st_ip not in (200, 201):
            print("     ", res_ip)

    st_is, res_is = asc("GET", f"/v2/inAppPurchases/{iap_id}/appStoreReviewScreenshot")
    if (st_is == 404 or not (isinstance(res_is, dict) and res_is.get("data"))) and review_shot.exists():
        upload_binary_asset(
            "/v1/inAppPurchaseAppStoreReviewScreenshots",
            "/v1/inAppPurchaseAppStoreReviewScreenshots",
            "inAppPurchaseAppStoreReviewScreenshots",
            "inAppPurchaseV2",
            "inAppPurchases",
            iap_id,
            review_shot,
        )


def sync_three_day_trial(sub_id: str, product_id: str, territories: list[str]) -> None:
    st_ex, res_ex = asc("GET", f"/v1/subscriptions/{sub_id}/introductoryOffers?limit=200")
    existing = res_ex.get("data", []) if st_ex == 200 and isinstance(res_ex, dict) else []
    if existing:
        print(f"    • Introductory Offer already exists on {product_id} ({len(existing)} entry/entries).")
        return

    # First attempt global/base introductory offer without territory relationship; fall back per-territory if API requires territory
    st_o, res_o = asc("POST", "/v1/subscriptionIntroductoryOffers", {
        "data": {
            "type": "subscriptionIntroductoryOffers",
            "attributes": {
                "duration": "THREE_DAYS",
                "offerMode": "FREE_TRIAL",
                "numberOfPeriods": 1,
                "startDate": None,
                "endDate": None,
            },
            "relationships": {
                "subscription": {"data": {"type": "subscriptions", "id": sub_id}},
            },
        }
    })
    if st_o in (200, 201):
        print(f"    POST 3-Day Free Trial (global) on {product_id} -> {st_o}")
        return

    print(f"    Global 3-day trial returned {st_o}; applying per-territory across {len(territories)} markets...")
    ok_cnt = 0
    first_err = None
    for tid in territories:
        st_t, res_t = asc("POST", "/v1/subscriptionIntroductoryOffers", {
            "data": {
                "type": "subscriptionIntroductoryOffers",
                "attributes": {
                    "duration": "THREE_DAYS",
                    "offerMode": "FREE_TRIAL",
                    "numberOfPeriods": 1,
                    "startDate": None,
                    "endDate": None,
                },
                "relationships": {
                    "subscription": {"data": {"type": "subscriptions", "id": sub_id}},
                    "territory": {"data": {"type": "territories", "id": tid}},
                },
            }
        })
        if st_t in (200, 201):
            ok_cnt += 1
        elif first_err is None:
            first_err = (st_t, res_t)
    print(f"    Created 3-Day Free Trial in {ok_cnt}/{len(territories)} territories for {product_id}")
    if ok_cnt == 0 and first_err:
        print("      Note:", first_err)


def sync_all_iaps(app_id: str, territories: list[str]) -> None:
    print("[4/5] Configuring 2 Non-Consumables + Annual Subscription (with 3-Day Free Trial) to READY_TO_SUBMIT...")
    review_shot = SCREENSHOT_ROOT / "en-US" / "iphone65_05.png"

    _, iap_list = asc("GET", f"/v1/apps/{app_id}/inAppPurchasesV2?limit=50")
    existing_iaps = {x["attributes"]["productId"]: x["id"] for x in iap_list.get("data", []) if isinstance(iap_list, dict)}

    sync_non_consumable_iap(
        app_id=app_id,
        territories=territories,
        product_id="com.yanghe.waitcam.pro.lifetime",
        ref_name="WaitCam Pro Lifetime",
        usa_price=9.99,
        chn_price=28.0,
        locs={
            "en-US": {
                "name": "WaitCam Pro Lifetime",
                "description": "One-time lifetime unlock for all film LUTs, custom timers & Contact Sheets.",
            },
            "zh-Hans": {
                "name": "WaitCam 终身买断 Pro",
                "description": "黑五特惠一次买断，永久解锁全部电影胶片影调、自定义显影与印相单。",
            },
        },
        review_note="Black Friday one-time Lifetime unlock presented in ImpulsePaywallSheetView with Family Sharing.",
        review_shot=review_shot,
        existing_iaps=existing_iaps,
    )

    sync_non_consumable_iap(
        app_id=app_id,
        territories=territories,
        product_id="com.yanghe.waitcam.darkroom.plus",
        ref_name="WaitCam Darkroom Plus",
        usa_price=2.99,
        chn_price=8.0,
        locs={
            "en-US": {
                "name": "Darkroom Plus Pass",
                "description": "One-time pass unlocking 800T & Club 400 Mono film stocks offline.",
            },
            "zh-Hans": {
                "name": "暗房轻量解锁卡",
                "description": "低门槛一次解锁 800T 霓虹晕影与 Club 400 黑白胶片滤镜。",
            },
        },
        review_note="Starter one-time Lite Pass shown as non-hostile fallback inside ImpulsePaywallSheetView.",
        review_shot=review_shot,
        existing_iaps=existing_iaps,
    )

    # --- Subscription Group: WaitCam Pro Pass ---
    sg_ref = "WaitCam Pro Pass"
    _, sgs = asc("GET", f"/v1/apps/{app_id}/subscriptionGroups")
    sg_id = next(
        (g["id"] for g in sgs.get("data", []) if g["attributes"]["referenceName"] == sg_ref),
        None,
    )
    if not sg_id:
        st_g, created_g = asc("POST", "/v1/subscriptionGroups", {
            "data": {
                "type": "subscriptionGroups",
                "attributes": {"referenceName": sg_ref},
                "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
            }
        })
        print("  POST /v1/subscriptionGroups ->", st_g)
        if st_g in (200, 201) and isinstance(created_g, dict):
            sg_id = created_g["data"]["id"]
    if not sg_id:
        print("  ! Missing Subscription Group id, skipping annual subscription.")
        return

    _, cur_sgl = asc("GET", f"/v1/subscriptionGroups/{sg_id}/subscriptionGroupLocalizations")
    exist_sgl = {x["attributes"]["locale"]: x["id"] for x in cur_sgl.get("data", []) if isinstance(cur_sgl, dict)}
    sg_locs = {
        "en-US": {"name": "WaitCam Pro Pass", "customAppName": "WaitCam"},
        "zh-Hans": {"name": "WaitCam Pro 会员", "customAppName": "WaitCam"},
    }
    for loc, attrs in sg_locs.items():
        if loc not in exist_sgl:
            st_gl, _ = asc("POST", "/v1/subscriptionGroupLocalizations", {
                "data": {
                    "type": "subscriptionGroupLocalizations",
                    "attributes": {"locale": loc, **attrs},
                    "relationships": {"subscriptionGroup": {"data": {"type": "subscriptionGroups", "id": sg_id}}},
                }
            })
            print(f"  POST subGroupLoc {loc} -> {st_gl}")

    _, subs_res = asc("GET", f"/v1/subscriptionGroups/{sg_id}/subscriptions")
    sub_map = {x["attributes"]["productId"]: x["id"] for x in subs_res.get("data", []) if isinstance(subs_res, dict)}

    sub_pid = "com.yanghe.waitcam.pro.annual"
    sid = sub_map.get(sub_pid)
    sub_review_note = (
        "Annual auto-renewable subscription with 3-day free trial and automatic Day-2 local reminder "
        "scheduled 24 hours before renewal in NotificationAndPhotoService."
    )
    if not sid:
        st_cs, created_s = asc("POST", "/v1/subscriptions", {
            "data": {
                "type": "subscriptions",
                "attributes": {
                    "name": "WaitCam Pro Annual",
                    "productId": sub_pid,
                    "subscriptionPeriod": "ONE_YEAR",
                    "groupLevel": 1,
                    "familySharable": True,
                    "reviewNote": sub_review_note,
                },
                "relationships": {"group": {"data": {"type": "subscriptionGroups", "id": sg_id}}},
            }
        })
        print(f"  POST /v1/subscriptions ({sub_pid}) -> {st_cs}")
        if st_cs in (200, 201) and isinstance(created_s, dict):
            sid = created_s["data"]["id"]
        else:
            print("   ", created_s)
            return
    else:
        asc("PATCH", f"/v1/subscriptions/{sid}", {
            "data": {
                "type": "subscriptions",
                "id": sid,
                "attributes": {
                    "groupLevel": 1,
                    "familySharable": True,
                    "reviewNote": sub_review_note,
                },
            }
        })

    sub_locs = {
        "en-US": {
            "name": "WaitCam Pro Annual",
            "description": "Includes 3-day free trial, all film LUTs, and lossless HD darkroom vault.",
        },
        "zh-Hans": {
            "name": "WaitCam Pro 年度会员",
            "description": "含 3 天免费试用与第 2 天提醒，解锁全部电影胶片影调与高清显影。",
        },
    }
    _, cur_sl = asc("GET", f"/v1/subscriptions/{sid}/subscriptionLocalizations")
    exist_sl = {x["attributes"]["locale"]: x["id"] for x in cur_sl.get("data", []) if isinstance(cur_sl, dict)}
    for loc, attrs in sub_locs.items():
        if loc in exist_sl:
            asc("PATCH", f"/v1/subscriptionLocalizations/{exist_sl[loc]}", {
                "data": {"type": "subscriptionLocalizations", "id": exist_sl[loc], "attributes": attrs}
            })
        else:
            st_sl, _ = asc("POST", "/v1/subscriptionLocalizations", {
                "data": {
                    "type": "subscriptionLocalizations",
                    "attributes": {"locale": loc, **attrs},
                    "relationships": {"subscription": {"data": {"type": "subscriptions", "id": sid}}},
                }
            })
            print(f"  POST subLoc {sub_pid} {loc} -> {st_sl}")

    st_sa, _ = asc("GET", f"/v1/subscriptions/{sid}/subscriptionAvailability")
    if st_sa == 404:
        st_psa, res_psa = asc("POST", "/v1/subscriptionAvailabilities", {
            "data": {
                "type": "subscriptionAvailabilities",
                "attributes": {"availableInNewTerritories": True},
                "relationships": {
                    "subscription": {"data": {"type": "subscriptions", "id": sid}},
                    "availableTerritories": {"data": [{"type": "territories", "id": t} for t in territories]},
                },
            }
        })
        print(f"  POST subscriptionAvailabilities {sub_pid} ({len(territories)}) -> {st_psa}")
        if st_psa not in (200, 201):
            print("   ", res_psa)

    _, cur_sp = asc("GET", f"/v1/subscriptions/{sid}/prices?limit=200")
    if len(cur_sp.get("data", []) if isinstance(cur_sp, dict) else []) < 5:
        usa_sp = find_closest_price_point(f"/v1/subscriptions/{sid}/pricePoints?filter[territory]=USA&limit=200", 14.99)
        chn_sp = find_closest_price_point(f"/v1/subscriptions/{sid}/pricePoints?filter[territory]=CHN&limit=200", 38.0)
        if usa_sp:
            eq_url: Optional[str] = f"/v1/subscriptionPricePoints/{usa_sp}/equalizations?limit=200&include=territory"
            ter_pp: dict[str, str] = {"USA": usa_sp}
            while eq_url:
                st_eq, eq_res = asc("GET", eq_url)
                if st_eq != 200 or not isinstance(eq_res, dict):
                    break
                for item in eq_res.get("data", []):
                    tid = item.get("relationships", {}).get("territory", {}).get("data", {}).get("id")
                    if tid:
                        ter_pp[tid] = item["id"]
                eq_url = eq_res.get("links", {}).get("next")
            if chn_sp:
                ter_pp["CHN"] = chn_sp
            print(f"  Setting {len(ter_pp)} territory prices for {sub_pid} ($14.99 USA / ¥38 CHN)...")
            ok_cnt = 0
            for tid, pp_id in ter_pp.items():
                st_p, _ = asc("POST", "/v1/subscriptionPrices", {
                    "data": {
                        "type": "subscriptionPrices",
                        "attributes": {"preserveCurrentPrice": False, "startDate": None},
                        "relationships": {
                            "subscription": {"data": {"type": "subscriptions", "id": sid}},
                            "subscriptionPricePoint": {"data": {"type": "subscriptionPricePoints", "id": pp_id}},
                        },
                    }
                })
                if st_p in (200, 201):
                    ok_cnt += 1
            print(f"    Created {ok_cnt}/{len(ter_pp)} subscriptionPrices for {sub_pid}")

    sync_three_day_trial(sid, sub_pid, territories)

    st_ss, res_ss = asc("GET", f"/v1/subscriptions/{sid}/appStoreReviewScreenshot")
    if (st_ss == 404 or not (isinstance(res_ss, dict) and res_ss.get("data"))) and review_shot.exists():
        upload_binary_asset(
            "/v1/subscriptionAppStoreReviewScreenshots",
            "/v1/subscriptionAppStoreReviewScreenshots",
            "subscriptionAppStoreReviewScreenshots",
            "subscription",
            "subscriptions",
            sid,
            review_shot,
        )


def verify_readiness(app_id: str) -> None:
    print("[5/5] Verifying IAPs, Subscriptions, 3-Day Trial & Version Readiness...")
    _, iaps = asc("GET", f"/v1/apps/{app_id}/inAppPurchasesV2")
    for x in iaps.get("data", []) if isinstance(iaps, dict) else []:
        print("  IAP:", x["attributes"]["productId"], "id=", x["id"], "->", x["attributes"]["state"])
    _, sgs = asc("GET", f"/v1/apps/{app_id}/subscriptionGroups")
    for sg in sgs.get("data", []) if isinstance(sgs, dict) else []:
        _, subs = asc("GET", f"/v1/subscriptionGroups/{sg['id']}/subscriptions")
        for x in subs.get("data", []) if isinstance(subs, dict) else []:
            _, io = asc("GET", f"/v1/subscriptions/{x['id']}/introductoryOffers?limit=200")
            io_cnt = len(io.get("data", []) if isinstance(io, dict) else [])
            print("  Sub:", x["attributes"]["productId"], "id=", x["id"], "->", x["attributes"]["state"], f"introOffers={io_cnt}")
    _, vers = asc("GET", f"/v1/apps/{app_id}/appStoreVersions?filter[platform]=IOS&include=build")
    if isinstance(vers, dict) and vers.get("data"):
        v = vers["data"][0]
        b = v.get("relationships", {}).get("build", {}).get("data")
        print("  Version:", v["attributes"]["versionString"], v["attributes"]["appStoreState"], "build:", b)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--upload-ipa", action="store_true")
    parser.add_argument("--wait-build", action="store_true")
    parser.add_argument("--all", action="store_true")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    meta = json.loads(METADATA_JSON.read_text(encoding="utf-8"))
    st, apps = asc("GET", f"/v1/apps?filter[bundleId]={BUNDLE_ID}")
    if st != 200 or not isinstance(apps, dict) or not apps.get("data"):
        print(f"Bundle ID '{BUNDLE_ID}' registered; App Record not created in ASC yet.")
        return 2

    app_id = apps["data"][0]["id"]
    print(f"Found App Record id={app_id} for {BUNDLE_ID}")
    if args.check and not args.all and not args.upload_ipa and not args.wait_build:
        verify_readiness(app_id)
        return 0

    if args.upload_ipa and IPA_PATH.exists():
        print(f"Uploading {IPA_PATH} via xcrun altool...")
        subprocess.run([
            "xcrun", "altool", "--upload-app",
            "--type", "ios",
            "-f", str(IPA_PATH),
            "--apiKey", KEY_ID,
            "--apiIssuer", ISSUER_ID,
        ], check=False)

    territories = get_all_territory_ids()
    sync_app_metadata_and_version(app_id, meta, territories, wait_build=args.wait_build)
    sync_all_iaps(app_id, territories)
    verify_readiness(app_id)
    return 0


if __name__ == "__main__":
    sys.exit(main())

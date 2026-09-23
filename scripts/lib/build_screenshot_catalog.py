#!/usr/bin/env python3
"""Turns an `xcrun xcresulttool export attachments` output directory into
docs/demo-screenshots/<group>/NN-slug.png + README.md + manifest.json.

Called by scripts/capture_ios_catalog.sh — not meant to be run standalone,
though it can be for debugging:
    python3 scripts/lib/build_screenshot_catalog.py \
        --export-dir output/ios-screenshot-catalog/attachments \
        --docs-dir docs/demo-screenshots \
        --sim-name "banbe-screenshot-catalog" --sim-os "17.5" \
        --generated-at "2026-01-01T00:00:00Z"

Pairing PNG <-> metadata: ScreenshotCatalogTests.swift's `capture()` helper
attaches two XCTAttachments per screenshot inside the SAME `XCTContext.
runActivity` — "<group>/<order>-<slug>" (the PNG) and
"<group>/<order>-<slug>.meta" (a JSON sidecar with the full title/
description/role/testName/generatedAt). Confirmed by an actual run on this
machine (xcresulttool 25115): `suggestedHumanReadableName` does NOT
preserve `.name` verbatim — "/" is stripped entirely with no separator
(no simple way back to group/order/slug from the string alone), and a
"_<index>_<uuid>" is inserted before the file extension, e.g.
"04-messaging/01-inbox" -> "04-messaging01-inbox_0_<uuid>.png". The PNG and
its `.meta` sidecar share the exact same "<uuid>" (both attached within the
same activity/moment) — that shared uuid is what this script actually pairs
them on. group/order/slug/title/etc. are never parsed back out of the name
string at all; they come from the `.meta` JSON sidecar's own content.
"""
import argparse
import json
import re
import shutil
import sys
from pathlib import Path


def fail(msg: str) -> None:
    print(f"[build_screenshot_catalog] ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--export-dir", required=True)
    p.add_argument("--docs-dir", required=True)
    p.add_argument("--sim-name", required=True)
    p.add_argument("--sim-os", required=True)
    p.add_argument("--generated-at", required=True)
    args = p.parse_args()

    export_dir = Path(args.export_dir)
    docs_dir = Path(args.docs_dir)
    manifest_path = export_dir / "manifest.json"
    if not manifest_path.exists():
        fail(f"{manifest_path} does not exist")

    xcresult_manifest = json.loads(manifest_path.read_text())

    # xcresulttool does not preserve `XCTAttachment.name` verbatim in
    # `suggestedHumanReadableName`: confirmed by an actual run on this
    # machine (xcresulttool 25115) — it strips "/" entirely (our
    # "<group>/<order>-<slug>" became "<group><order>-<slug>", no
    # separator) and inserts a disambiguating "_<index>_<uuid>" right
    # before the file extension, e.g.:
    #   "04-messaging/01-inbox"       -> "04-messaging01-inbox_0_<uuid>.png"
    #   "04-messaging/01-inbox.meta"  -> "04-messaging01-inbox_1_<uuid>.meta"
    # The PNG and its `.meta` sidecar share the exact same "<uuid>" (both
    # came from the same `capture()` call/activity) — that shared uuid,
    # not any string surgery on the name itself, is what pairs them.
    CORE_RE = re.compile(
        r"^(?P<core>.*)_(?P<index>\d+)_(?P<uuid>[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-"
        r"[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})\.(?P<ext>[^.]+)$"
    )

    by_uuid: dict[str, dict[str, dict]] = {}
    unrecognized = []
    for test_entry in xcresult_manifest:
        for att in test_entry.get("attachments", []):
            name = att.get("suggestedHumanReadableName", "")
            exported = att.get("exportedFileName", "")
            if not name or not exported:
                continue
            m = CORE_RE.match(name)
            if not m:
                continue  # framework-generated debug artifact (UI snapshot, screen recording, etc.) — not ours.
            ext = m.group("ext").lower()
            if ext not in ("png", "jpg", "jpeg", "heic", "meta"):
                continue
            kind = "meta" if ext == "meta" else "png"
            slot = by_uuid.setdefault(m.group("uuid"), {})
            if kind in slot:
                unrecognized.append(name)  # two attachments claiming the same uuid+kind
            slot[kind] = {**att, "core": m.group("core")}

    # Pair each png with its meta sidecar.
    entries = []
    unnamed = []
    missing_meta = []
    for uuid, slot in by_uuid.items():
        png = slot.get("png")
        meta_att = slot.get("meta")
        if not png:
            continue  # a stray `.meta` with no image (should not happen)
        core = png["core"]
        if not core:
            unnamed.append(core)
            continue
        if not meta_att:
            missing_meta.append(core)
            continue

        exported_path = export_dir / png["exportedFileName"]
        meta_path = export_dir / meta_att["exportedFileName"]
        try:
            meta = json.loads(meta_path.read_text())
        except Exception as e:  # noqa: BLE001
            fail(f"Could not parse metadata sidecar for '{core}' ({meta_path}): {e}")
            return

        entries.append({
            "group": meta["group"],
            "order": meta["order"],
            "slug": meta["slug"],
            "title": meta["title"],
            "description": meta["description"],
            "role": meta["role"],
            "testName": meta["testName"],
            "generatedAt": meta["generatedAt"],
            "sourcePngPath": exported_path,
        })

    duplicates = unrecognized

    if not entries:
        fail(
            "No screenshots were exported. Either ScreenshotCatalogTests "
            "failed before capturing anything, or the account state this "
            "run had made every capture opportunistically skip — check "
            "output/ios-screenshot-catalog/xcodebuild.log."
        )

    if duplicates:
        fail(f"Duplicate attachment name(s) exported: {sorted(set(duplicates))}")
    if unnamed:
        fail(f"Attachment(s) with no meaningful name: {unnamed}")
    if missing_meta:
        fail(f"Screenshot(s) missing their metadata sidecar: {missing_meta}")

    # group+order collisions (two different slugs claiming the same number).
    seen_slots: dict[tuple, str] = {}
    for e in entries:
        slot = (e["group"], e["order"])
        if slot in seen_slots and seen_slots[slot] != e["slug"]:
            fail(f"Duplicate order {e['order']} in group {e['group']}: "
                 f"'{seen_slots[slot]}' and '{e['slug']}' both claim it")
        seen_slots[slot] = e["slug"]

    # --- Write files -------------------------------------------------------
    if docs_dir.exists():
        for child in docs_dir.iterdir():
            if child.is_dir():
                shutil.rmtree(child)
            elif child.suffix.lower() in (".png", ".jpg", ".jpeg"):
                child.unlink()
    docs_dir.mkdir(parents=True, exist_ok=True)

    entries.sort(key=lambda e: (e["group"], e["order"]))
    manifest_out = []
    for e in entries:
        group_dir = docs_dir / e["group"]
        group_dir.mkdir(parents=True, exist_ok=True)
        slug_safe = re.sub(r"[^a-z0-9-]", "-", e["slug"].lower())
        filename = f"{e['order']:02d}-{slug_safe}.png"
        dest = group_dir / filename
        shutil.copyfile(e["sourcePngPath"], dest)

        manifest_out.append({
            "group": e["group"],
            "order": e["order"],
            "filename": f"{e['group']}/{filename}",
            "title": e["title"],
            "description": e["description"],
            "role": e["role"],
            "testName": e["testName"],
            "generatedAt": args.generated_at,
        })

    (docs_dir / "manifest.json").write_text(json.dumps(manifest_out, indent=2) + "\n")

    # --- README --------------------------------------------------------
    not_captured = [
        ("03-booking-payment", "Reserve flow, holding a seat, payment details/transfer, "
         "awaiting verification, confirmed ticket/QR, cancelled/declined booking",
         "Every state in this group requires actually reserving/paying for a real seat on "
         "the shared fast-suite test account. That would mutate shared fixture state other "
         "existing UI/Playwright suites depend on, which this ticket's \"do not alter "
         "production data\" rules out, and there is no read-only path to reach these states."),
        ("07-organizer", "Organizer dashboard, Check-in/Attendance",
         "Only reachable through DashboardView.swift/AttendanceView's own entry point on the "
         "Dashboard, which was outside this ticket's allowed read scope — no verified stable "
         "accessibility-identifier path exists to them from Account."),
        ("07-organizer", "Refund queue",
         "No refund-queue screen or accessibility identifier was found within this ticket's "
         "read scope; not implemented as a reachable flow here."),
        ("—", "Any state gated on the shared test account's CURRENT data "
         "(an unread thread, an active story, a chat image attachment, a non-empty "
         "notification list, organizer enrollment)",
         "Captured opportunistically when ScreenshotCatalogTests.swift ran — if that state "
         "did not exist on the account at run time, the flow was skipped (see this run's "
         "xcresult for the exact SKIPPED activity note) rather than faked. Re-run the suite "
         "after that state exists on the account to pick it up."),
    ]

    groups: dict[str, list[dict]] = {}
    for e in manifest_out:
        groups.setdefault(e["group"], []).append(e)

    lines = []
    lines.append("# Banbe iOS Screenshot Catalog")
    lines.append("")
    lines.append(f"Generated: {args.generated_at}")
    lines.append("")
    lines.append(f"Simulator: **{args.sim_name}**, iOS **{args.sim_os}**")
    lines.append("")
    lines.append("Regenerate with:")
    lines.append("")
    lines.append("```")
    lines.append("bash scripts/capture_ios_catalog.sh")
    lines.append("```")
    lines.append("")
    for group in sorted(groups):
        lines.append(f"## {group}")
        lines.append("")
        lines.append("| Screenshot | Screen/state | Role | Note |")
        lines.append("|---|---|---|---|")
        for e in groups[group]:
            img = f"{e['group']}/{Path(e['filename']).name}"
            lines.append(
                f"| ![{e['title']}]({img}) `{Path(e['filename']).name}` | {e['title']} | "
                f"{e['role']} | {e['description']} |"
            )
        lines.append("")

    lines.append("## Not captured yet")
    lines.append("")
    for group, flow, reason in not_captured:
        lines.append(f"- **{group} — {flow}**: {reason}")
    lines.append("")

    lines.append(
        "> Screenshots are produced by `BanbeAppUITests/ScreenshotCatalogTests.swift` "
        "running against deterministic onboarding fixtures (Groups A/B) and, for anything "
        "requiring a signed-in session, the same dedicated shared test account "
        "(`doqanh0906+banbe-fast-suite-shared@gmail.com`) `EventDetailOpenInMapUITests`/"
        "`MapExploreSelectionUITests` already use — never live production user data."
    )
    lines.append("")

    (docs_dir / "README.md").write_text("\n".join(lines))

    print(f"[build_screenshot_catalog] Wrote {len(entries)} screenshots across "
          f"{len(groups)} group(s) to {docs_dir}")


if __name__ == "__main__":
    main()

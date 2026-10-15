from __future__ import annotations

import tempfile

from .baseline import baseline_version_id, describe_game_version, load_baseline_md5s
from .common import *
from .deployment_paths import contained_game_path, deployment_relative_path
from .game import resolve_game_dir, steam_game_version
from .language import (
    normalize_preferred_language,
    resolve_user_preferred_lang_path,
    write_user_preferred_lang,
)
from .package import collect_package_deploy_files
from .project_json_guard import write_project_json
from .project_refs import project_path_or_absolute


def _write_last_applied_manifest(
    path: Optional[str],
    *,
    package_manifest_path: Path,
    package_root: Path,
    package_manifest: Dict[str, object],
    game_version: Dict[str, object],
    deploy_files: List[Dict[str, object]],
) -> None:
    if not path:
        return
    manifest_path = Path(path).expanduser()
    project_dir = (
        manifest_path.parent.parent if manifest_path.parent.name == ".fh-radio-studio" else None
    )
    package_files = []
    for item in deploy_files:
        package_md5 = item.get("package_md5")
        if not isinstance(package_md5, str) or not package_md5:
            continue
        package_files.append(
            {
                "kind": item.get("kind", "file"),
                "relative_path": item.get("relative_path"),
                "install_relative_path": item.get("install_relative_path"),
                "size": item.get("source_size"),
                "md5": package_md5,
            }
        )
    manifest = {
        "schema_version": 1,
        "kind": "last_applied_package",
        "created_at": datetime.now(timezone.utc).isoformat(),
        "source_package_manifest": (
            project_path_or_absolute(project_dir, package_manifest_path)
            if project_dir is not None
            else str(package_manifest_path.resolve())
        ),
        "package_root": (
            project_path_or_absolute(project_dir, package_root)
            if project_dir is not None
            else str(package_root.resolve())
        ),
        "game_version": game_version,
        "game_version_id": baseline_version_id(game_version),
        "supported_game_version_ids": [baseline_version_id(game_version)],
        "package_name": (
            package_manifest.get("package_name") if isinstance(package_manifest, dict) else None
        ),
        "package_files": package_files,
        "deployment_target": (
            "mediapc"
            if package_files
            and str(package_files[0].get("install_relative_path", "")).startswith("mediapc/")
            else "media"
        ),
    }
    write_project_json(manifest_path, manifest, project_dir=project_dir)


def _last_applied_md5s(path: Optional[str]) -> Dict[str, str]:
    if not path:
        return {}
    manifest_path = Path(path).expanduser()
    if not manifest_path.exists():
        return {}
    manifest = load_manifest(manifest_path)
    result: Dict[str, str] = {}

    def add_path(value: object, md5: object) -> None:
        if not isinstance(md5, str) or not md5:
            return
        text = str(value or "").replace("\\", "/").strip("/")
        if not text:
            return
        result[text] = md5
        if not text.startswith(("media/", "mediapc/")) and text != "UserPreferredLang":
            result[f"media/audio/{text}"] = md5

    def add_items(items: object) -> None:
        if not isinstance(items, list):
            return
        for item in items:
            if not isinstance(item, dict):
                continue
            md5 = item.get("md5") or item.get("package_md5") or item.get("source_md5")
            add_path(item.get("relative_path"), md5)
            add_path(item.get("install_relative_path"), md5)

    add_items(manifest.get("package_files"))
    add_items(manifest.get("files"))
    return result


def cmd_deploy_package(args: argparse.Namespace) -> int:
    game_dir = resolve_game_dir(args.game_dir)
    game_version = steam_game_version(game_dir)
    package_dir = Path(args.package_dir).expanduser()
    package_root = package_root_dir(package_dir)
    package_manifest_path = package_root / "fh_radio_studio_package_manifest.json"
    package_manifest = (
        load_manifest(package_manifest_path) if package_manifest_path.exists() else {}
    )
    files = collect_package_deploy_files(package_root)
    target_root = getattr(args, "target_root", "mediapc")
    for item in files:
        item["package_install_relative_path"] = item["install_relative_path"]
        item["install_relative_path"] = deployment_relative_path(
            str(item["install_relative_path"]), target_root
        )
    baseline_md5s = load_baseline_md5s(args.baseline_manifest)
    last_applied_md5s = _last_applied_md5s(getattr(args, "last_applied_manifest", None))
    if target_root == "media" and not args.force and not baseline_md5s:
        die(
            "A pristine baseline is required before deploy. Create one first, or pass --force explicitly."
        )
    print(f"Game dir   : {game_dir}")
    print(f"Game build : {describe_game_version(game_version)}")
    print(f"Package    : {package_root}")
    print(f"Write target: {target_root}")
    if args.baseline_manifest:
        print(f"Baseline   : {args.baseline_manifest}")
    if getattr(args, "last_applied_manifest", None):
        print(f"Fingerprint: {Path(args.last_applied_manifest).expanduser()}")
    print("Plan:")
    for item in files:
        src = Path(str(item["source"]))
        install_rel = Path(*str(item["install_relative_path"]).split("/"))
        print(f"  {src} -> {game_dir / install_rel}")

    # Validate the entire write set before changing any destination.
    manifest_files = []
    owned_overlay_removals = []
    for item in files:
        src = Path(str(item["source"]))
        rel_text = str(item["relative_path"]).replace("\\", "/")
        install_rel_text = str(item["install_relative_path"]).replace("\\", "/")
        dest = contained_game_path(game_dir, install_rel_text)
        source_md5 = md5_file(src)
        source_size = file_size(src)
        current_before_md5 = md5_file(dest)
        canonical_rel = str(item["package_install_relative_path"])
        baseline_md5 = baseline_md5s.get(canonical_rel) or baseline_md5s.get(rel_text)
        last_applied_md5 = last_applied_md5s.get(install_rel_text) or last_applied_md5s.get(
            rel_text
        )
        if not args.force and (target_root == "media" or dest.exists()):
            if baseline_md5 is None and target_root == "media":
                die(
                    f"Baseline is missing {install_rel_text}; recreate the baseline for this package."
                )
            trusted_md5s = {
                value
                for value in (baseline_md5, source_md5, last_applied_md5)
                if isinstance(value, str) and value
            }
            if current_before_md5 not in trusted_md5s:
                trusted_label = (
                    "pristine baseline, package, and last applied package"
                    if last_applied_md5
                    else "both pristine baseline and package"
                )
                die(
                    f"{install_rel_text} differs from {trusted_label}. "
                    "Use --force only when you intentionally want to overwrite an untrusted current game file."
                )
        if target_root == "media":
            overlay_rel = deployment_relative_path(canonical_rel, "mediapc")
            overlay = contained_game_path(game_dir, overlay_rel)
            overlay_md5 = md5_file(overlay)
            if overlay.exists():
                if overlay_md5 is None or last_applied_md5s.get(overlay_rel) != overlay_md5:
                    die(
                        f"{overlay_rel} would shadow the media write and is not owned by the last deployment. "
                        "Use mediapc, or remove that conflicting override before writing media."
                    )
                owned_overlay_removals.append(overlay)
        manifest_files.append(
            {
                "kind": item.get("kind", "file"),
                "relative_path": rel_text,
                "install_relative_path": install_rel_text,
                "source": str(src.resolve()),
                "destination": str(dest.resolve()),
                "source_size": source_size,
                "source_md5": source_md5,
                "package_md5": source_md5,
                "baseline_md5": baseline_md5,
                "last_applied_md5": last_applied_md5,
                "current_before_md5": current_before_md5,
                "force": args.force,
            }
        )
    if not args.yes:
        for overlay in owned_overlay_removals:
            print(f"  remove owned override after media write: {overlay}")
        print("\nDry run only. Re-run with --yes to write files.")
        return 0

    for item in manifest_files:
        src = Path(str(item["source"]))
        dest = Path(str(item["destination"]))
        dest.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(
            dir=dest.parent, prefix=f".{dest.name}.", suffix=".deploy-tmp", delete=False
        ) as handle:
            temp = Path(handle.name)
        try:
            shutil.copy2(src, temp)
            temp.replace(dest)
        finally:
            if temp.exists():
                temp.unlink()
        print(f"  copied {item['install_relative_path']}")
    for overlay in owned_overlay_removals:
        overlay.unlink()
        print(f"  removed owned override {overlay.relative_to(game_dir)}")

    language = package_manifest.get("language") if isinstance(package_manifest, dict) else None
    if isinstance(language, dict) and language.get("preferred_lang"):
        preferred_lang = normalize_preferred_language(str(language["preferred_lang"]))
        preferred_path = resolve_user_preferred_lang_path(getattr(args, "preferred_path", None))
        write_user_preferred_lang(preferred_path, preferred_lang)
        print(f"  wrote UserPreferredLang -> {preferred_lang}")

    _write_last_applied_manifest(
        getattr(args, "last_applied_manifest", None),
        package_manifest_path=package_manifest_path,
        package_root=package_root,
        package_manifest=package_manifest,
        game_version=game_version,
        deploy_files=manifest_files,
    )
    if getattr(args, "last_applied_manifest", None):
        print(f"Last applied fingerprint: {Path(args.last_applied_manifest).expanduser()}")
    return 0

#!/usr/bin/env python3
"""Generate docs/wiki/data/apps.json (+ apps.js) from kubernetes/apps manifests.

Never opens *.sops.yaml. Masks the real domain. Deterministic output.
"""
import argparse
import json
import re
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.exit("PyYAML is required: pip install pyyaml")

ROOT = Path(__file__).resolve().parent.parent
REAL_DOMAIN = "fabriciooml.dev"
DOMAIN_MASK = "<domain>"
WORKLOAD_KINDS = {"Deployment", "StatefulSet", "DaemonSet", "CronJob"}
HOST_RE = re.compile(r"Host\(`([^`]+)`\)")
DIGEST_RE = re.compile(r"@sha256:[0-9a-fA-F]+$")


def mask_host(host, domain):
    suffix = "." + domain
    if host.endswith(suffix):
        return host[: -len(suffix)] + "." + DOMAIN_MASK
    return "<external-host>"


def split_image(image):
    pinned = bool(DIGEST_RE.search(image))
    ref = DIGEST_RE.sub("", image)
    last = ref.rsplit("/", 1)[-1]
    if ":" in last:
        repo, tag = ref.rsplit(":", 1)
    else:
        repo, tag = ref, ("digest" if pinned else "latest")
    return {"repo": repo, "tag": tag, "pinned": pinned}


def collect_images(node, found):
    if isinstance(node, dict):
        for key in ("containers", "initContainers"):
            for c in node.get(key) or []:
                if isinstance(c, dict) and isinstance(c.get("image"), str):
                    found.append(c["image"])
        for value in node.values():
            collect_images(value, found)
    elif isinstance(node, list):
        for item in node:
            collect_images(item, found)


def load_docs(app_dir):
    for path in sorted(app_dir.glob("*.yaml")):
        if path.name.endswith(".sops.yaml") or path.name == "kustomization.yaml":
            continue
        try:
            for doc in yaml.safe_load_all(path.read_text()):
                if isinstance(doc, dict) and "kind" in doc:
                    yield doc
        except yaml.YAMLError as exc:
            sys.exit(f"cannot parse {path}: {exc}")


def build_app(app_dir, notes, domain):
    workloads, images, hosts, storage = [], [], {}, {}
    for doc in load_docs(app_dir):
        kind = doc["kind"]
        meta = doc.get("metadata") or {}
        if kind in WORKLOAD_KINDS:
            workloads.append(doc)
            collect_images(doc, images)
            for tmpl in (doc.get("spec") or {}).get("volumeClaimTemplates") or []:
                size = (((tmpl.get("spec") or {}).get("resources") or {}).get("requests") or {}).get("storage")
                if size:
                    storage[tmpl["metadata"]["name"]] = size
        elif kind == "PersistentVolumeClaim":
            size = (((doc.get("spec") or {}).get("resources") or {}).get("requests") or {}).get("storage")
            if size:
                storage[meta.get("name", "pvc")] = size
        elif kind == "IngressRoute":
            for route in (doc.get("spec") or {}).get("routes") or []:
                for raw in HOST_RE.findall(route.get("match", "")):
                    masked = mask_host(raw, domain)
                    vis = "lan" if masked.endswith(".local." + DOMAIN_MASK) else "public"
                    hosts[masked] = vis
    if not workloads:
        return None

    name = app_dir.name
    note = notes.get(name)
    if note is None:
        print(f"warning: no entry for '{name}' in notes file", file=sys.stderr)
        note = {}
    host_list = [{"host": h, "visibility": hosts[h]} for h in sorted(hosts)]
    return {
        "name": name,
        "namespace": (workloads[0].get("metadata") or {}).get("namespace", "default"),
        "category": note.get("category", "uncategorised"),
        "description": note.get("description", "No description yet."),
        "images": sorted((split_image(i) for i in set(images)), key=lambda i: (i["repo"], i["tag"])),
        "hosts": host_list,
        "storage": [{"name": n, "size": storage[n]} for n in sorted(storage)],
        "public": any(h["visibility"] == "public" for h in host_list),
        "lan": any(h["visibility"] == "lan" for h in host_list),
        "stateful": bool(storage),
    }


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--apps-dir", type=Path, default=ROOT / "kubernetes/apps")
    p.add_argument("--notes", type=Path, default=ROOT / "docs/wiki/data/app-notes.json")
    p.add_argument("--out", type=Path, default=ROOT / "docs/wiki/data/apps.json")
    p.add_argument("--domain", default=REAL_DOMAIN)
    args = p.parse_args()

    notes = json.loads(args.notes.read_text()) if args.notes.exists() else {}
    apps = []
    for app_dir in sorted(d for d in args.apps_dir.iterdir() if d.is_dir()):
        app = build_app(app_dir, notes, args.domain)
        if app:
            apps.append(app)

    payload = json.dumps({"apps": apps}, indent=2, sort_keys=True) + "\n"
    if args.domain in payload:
        sys.exit("real domain found in output; check app-notes.json")
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(payload)
    args.out.with_suffix(".js").write_text("window.WIKI_APPS = " + payload.rstrip("\n") + ";\n")
    print(f"wrote {len(apps)} apps to {args.out}")


if __name__ == "__main__":
    main()

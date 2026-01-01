#!/usr/bin/env python3
"""
analyze_maven_monorepo.py

Scans a Maven monorepo, infers module structure + inter-dependencies from pom.xml files,
optionally inspects source trees for overlapping packages/classes, and proposes a split
into 3 app repos + 1 common repo.

Outputs (to --out dir):
  - modules.csv        : module coordinates, packaging, paths
  - deps.csv           : internal dependency edges
  - graph.dot          : Graphviz DOT file (dependency graph)
  - code_overlap.csv   : packages/classes overlapping across modules (source scan)
  - proposal.md        : suggested new repo model and split plan
"""

from __future__ import annotations

import argparse
import csv
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple
import xml.etree.ElementTree as ET


# -----------------------------
# Helpers: XML namespace handling
# -----------------------------
def strip_ns(tag: str) -> str:
    return tag.split("}", 1)[1] if "}" in tag else tag


def find_child(elem: ET.Element, name: str) -> Optional[ET.Element]:
    for c in list(elem):
        if strip_ns(c.tag) == name:
            return c
    return None


def find_children(elem: ET.Element, name: str) -> List[ET.Element]:
    return [c for c in list(elem) if strip_ns(c.tag) == name]


def text_of(elem: Optional[ET.Element]) -> Optional[str]:
    if elem is None or elem.text is None:
        return None
    t = elem.text.strip()
    return t if t else None


def safe_relpath(path: Path, base: Path) -> str:
    """Path.relative_to() that works across python versions and non-subpaths."""
    try:
        return str(path.relative_to(base))
    except Exception:
        return str(path)


# -----------------------------
# Data models
# -----------------------------
@dataclass
class Dep:
    group_id: str
    artifact_id: str
    version: Optional[str] = None
    scope: Optional[str] = None
    dep_type: Optional[str] = None
    optional: Optional[bool] = None

    def ga(self) -> Tuple[str, str]:
        return (self.group_id, self.artifact_id)


@dataclass
class PomInfo:
    pom_path: Path
    module_dir: Path
    group_id: Optional[str]
    artifact_id: str
    version: Optional[str]
    packaging: str
    parent_group_id: Optional[str] = None
    parent_artifact_id: Optional[str] = None
    parent_version: Optional[str] = None
    parent_relative_path: Optional[str] = None
    modules: List[str] = field(default_factory=list)
    dependencies: List[Dep] = field(default_factory=list)

    # ✅ IMPORTANT FIX:
    # Make PomInfo hashable so it can be used as a dict key / in sets (graph building).
    # We hash by pom_path which uniquely identifies a module inside the repo.
    def __hash__(self) -> int:
        return hash(self.pom_path)

    def __eq__(self, other: object) -> bool:
        return isinstance(other, PomInfo) and self.pom_path == other.pom_path

    def ga(self) -> Tuple[str, str]:
        return ((self.group_id or ""), self.artifact_id)

    def gav(self) -> str:
        g = self.group_id or "UNKNOWN_GROUP"
        v = self.version or "UNKNOWN_VERSION"
        return f"{g}:{self.artifact_id}:{v}"


# -----------------------------
# POM parsing
# -----------------------------
def parse_pom(pom_path: Path) -> PomInfo:
    tree = ET.parse(pom_path)
    root = tree.getroot()

    gid = text_of(find_child(root, "groupId"))
    aid = text_of(find_child(root, "artifactId")) or ""
    ver = text_of(find_child(root, "version"))
    packaging = text_of(find_child(root, "packaging")) or "jar"

    parent = find_child(root, "parent")
    pgid = paid = pver = prel = None
    if parent is not None:
        pgid = text_of(find_child(parent, "groupId"))
        paid = text_of(find_child(parent, "artifactId"))
        pver = text_of(find_child(parent, "version"))
        prel = text_of(find_child(parent, "relativePath"))

    modules_elem = find_child(root, "modules")
    modules: List[str] = []
    if modules_elem is not None:
        for m in find_children(modules_elem, "module"):
            mt = text_of(m)
            if mt:
                modules.append(mt)

    deps: List[Dep] = []
    deps_elem = find_child(root, "dependencies")
    if deps_elem is not None:
        for d in find_children(deps_elem, "dependency"):
            dg = text_of(find_child(d, "groupId")) or ""
            da = text_of(find_child(d, "artifactId")) or ""
            dv = text_of(find_child(d, "version"))
            ds = text_of(find_child(d, "scope"))
            dt = text_of(find_child(d, "type"))
            dop = text_of(find_child(d, "optional"))
            deps.append(
                Dep(
                    group_id=dg,
                    artifact_id=da,
                    version=dv,
                    scope=ds,
                    dep_type=dt,
                    optional=(dop.lower() == "true") if dop else None,
                )
            )

    return PomInfo(
        pom_path=pom_path.resolve(),
        module_dir=pom_path.parent.resolve(),
        group_id=gid,
        artifact_id=aid,
        version=ver,
        packaging=packaging,
        parent_group_id=pgid,
        parent_artifact_id=paid,
        parent_version=pver,
        parent_relative_path=prel,
        modules=modules,
        dependencies=deps,
    )


def resolve_parent_pom_path(pom: PomInfo) -> Optional[Path]:
    if not pom.parent_artifact_id:
        return None
    rel = pom.parent_relative_path.strip() if pom.parent_relative_path else "../pom.xml"
    candidate = (pom.module_dir / rel).resolve()
    return candidate if candidate.exists() and candidate.is_file() else None


def finalize_coords(poms_by_path: Dict[Path, PomInfo]) -> None:
    """
    Fill missing groupId/version from parent where possible (best-effort).
    """
    changed = True
    while changed:
        changed = False
        for pom in list(poms_by_path.values()):
            parent_path = resolve_parent_pom_path(pom)
            if parent_path and parent_path in poms_by_path:
                parent = poms_by_path[parent_path]
                if pom.group_id is None and parent.group_id:
                    pom.group_id = parent.group_id
                    changed = True
                if pom.version is None and parent.version:
                    pom.version = parent.version
                    changed = True
            else:
                if pom.group_id is None and pom.parent_group_id:
                    pom.group_id = pom.parent_group_id
                    changed = True
                if pom.version is None and pom.parent_version:
                    pom.version = pom.parent_version
                    changed = True


# -----------------------------
# Source overlap analysis (optional)
# -----------------------------
def list_java_files(module_dir: Path) -> List[Path]:
    src = module_dir / "src" / "main" / "java"
    if not src.exists():
        return []
    return [p for p in src.rglob("*.java") if p.is_file()]


def infer_package_from_path(java_file: Path, module_dir: Path) -> Optional[str]:
    base = module_dir / "src" / "main" / "java"
    try:
        rel = java_file.relative_to(base)
    except Exception:
        return None
    if rel.parts[:-1]:
        return ".".join(rel.parts[:-1])
    return None


def infer_class_fqcn(java_file: Path, module_dir: Path) -> Optional[str]:
    pkg = infer_package_from_path(java_file, module_dir)
    cls = java_file.stem
    return f"{pkg}.{cls}" if pkg else cls


# -----------------------------
# Graph utilities
# -----------------------------
def build_internal_index(poms: List[PomInfo]) -> Dict[Tuple[str, str], PomInfo]:
    idx: Dict[Tuple[str, str], PomInfo] = {}
    for p in poms:
        if p.group_id:
            idx[(p.group_id, p.artifact_id)] = p
    return idx


def detect_apps(poms: List[PomInfo]) -> List[PomInfo]:
    apps: List[PomInfo] = []
    for p in poms:
        if p.packaging in ("war", "ear"):
            apps.append(p)
            continue
        if (p.module_dir / "src" / "main" / "webapp").exists():
            apps.append(p)
    return apps


def reverse_deps(edges: List[Tuple[PomInfo, PomInfo]]) -> Dict[PomInfo, Set[PomInfo]]:
    r: Dict[PomInfo, Set[PomInfo]] = {}
    for a, b in edges:
        r.setdefault(b, set()).add(a)
    return r


def closure(start: PomInfo, adj: Dict[PomInfo, Set[PomInfo]]) -> Set[PomInfo]:
    seen: Set[PomInfo] = set()
    stack = [start]
    while stack:
        cur = stack.pop()
        for nxt in adj.get(cur, set()):
            if nxt not in seen:
                seen.add(nxt)
                stack.append(nxt)
    return seen


def detect_cycles_note(poms: List[PomInfo], edges: List[Tuple[PomInfo, PomInfo]]) -> str:
    adj: Dict[PomInfo, Set[PomInfo]] = {}
    for a, b in edges:
        adj.setdefault(a, set()).add(b)

    visited: Set[PomInfo] = set()
    stack: Set[PomInfo] = set()
    cycles: List[List[PomInfo]] = []

    def dfs(node: PomInfo, path: List[PomInfo]) -> None:
        visited.add(node)
        stack.add(node)
        for nxt in adj.get(node, set()):
            if nxt not in visited:
                dfs(nxt, path + [nxt])
            elif nxt in stack:
                try:
                    idx = path.index(nxt)
                    cyc = path[idx:] + [nxt]
                except ValueError:
                    cyc = [node, nxt]
                cycles.append(cyc)
        stack.remove(node)

    for p in poms:
        if p not in visited:
            dfs(p, [p])

    if not cycles:
        return "- No internal Maven dependency cycles detected."

    uniq = []
    seen = set()
    for c in cycles:
        key = "->".join([x.gav() for x in c])
        if key not in seen:
            seen.add(key)
            uniq.append(c)

    lines = ["- ⚠️ Detected internal dependency cycle(s):"]
    for c in uniq[:10]:
        lines.append("  - " + " -> ".join([x.artifact_id for x in c]))
    if len(uniq) > 10:
        lines.append(f"  - (and {len(uniq) - 10} more)")
    lines.append("  - Break cycles before splitting repos (usually by extracting interfaces/models downward).")
    return "\n".join(lines)


# -----------------------------
# Proposal generation
# -----------------------------
def propose_split(poms: List[PomInfo], edges: List[Tuple[PomInfo, PomInfo]]) -> str:
    adj: Dict[PomInfo, Set[PomInfo]] = {}
    for a, b in edges:
        adj.setdefault(a, set()).add(b)

    apps = detect_apps(poms)
    libs = [p for p in poms if p not in apps]

    rev = reverse_deps(edges)

    app_closures: Dict[PomInfo, Set[PomInfo]] = {}
    for app in apps:
        app_closures[app] = closure(app, adj)

    lib_to_apps: Dict[PomInfo, Set[PomInfo]] = {l: set() for l in libs}
    for app, clos in app_closures.items():
        for m in clos:
            if m in lib_to_apps:
                lib_to_apps[m].add(app)

    shared_libs = sorted(
        [l for l in libs if len(lib_to_apps.get(l, set())) >= 2],
        key=lambda x: (-len(lib_to_apps.get(x, set())), x.gav()),
    )

    high_fanin = sorted(
        [l for l in libs if len(rev.get(l, set())) >= 2 and l not in shared_libs],
        key=lambda x: (-len(rev.get(x, set())), x.gav()),
    )

    app_specific: Dict[PomInfo, List[PomInfo]] = {a: [] for a in apps}
    for l in libs:
        apps_using = lib_to_apps.get(l, set())
        if len(apps_using) == 1:
            only_app = next(iter(apps_using))
            app_specific[only_app].append(l)

    lines: List[str] = []
    lines.append("# Proposed 4-Repo Model (Based on POM dependency graph)\n")

    if not apps:
        lines.append("⚠️ No WAR/EAR modules detected. You may have standalone WAR projects without a reactor parent.\n")
    else:
        lines.append("## Detected Applications (WAR/EAR)\n")
        for a in apps:
            lines.append(f"- **{a.artifact_id}** ({a.packaging}) — `{a.module_dir}`")

    lines.append("\n## Shared library candidates (best for `common-platform` repo)\n")
    if not shared_libs and not high_fanin:
        lines.append("- (None detected via internal Maven modules.)")
        lines.append("  - This often means shared code is duplicated inside the apps, not extracted into JAR modules.")
        lines.append("  - Use `code_overlap.csv` to spot common packages/classes to extract.\n")
    else:
        if shared_libs:
            lines.append("\n**Used by 2+ apps (strong signal):**")
            for l in shared_libs:
                used_by = ", ".join(sorted([a.artifact_id for a in lib_to_apps.get(l, set())]))
                lines.append(f"- {l.gav()} — used by: {used_by}")
        if high_fanin:
            lines.append("\n**High fan-in libs (2+ internal dependents):**")
            for l in high_fanin:
                dependents = ", ".join(sorted([a.artifact_id for a in rev.get(l, set())]))
                lines.append(f"- {l.gav()} — internal dependents: {dependents}")

    lines.append("\n## App-specific module candidates (can live with each app repo)\n")
    if apps:
        for a in apps:
            mods = sorted(app_specific.get(a, []), key=lambda x: x.gav())
            lines.append(f"\n### {a.artifact_id}\n")
            if not mods:
                lines.append("- (No app-exclusive internal modules detected.)")
            else:
                for m in mods:
                    lines.append(f"- {m.gav()} — `{m.module_dir}`")

    lines.append("\n## Recommended Repo Split\n")
    lines.append("### Repo A: `common-platform` (publish Maven artifacts)\n")
    lines.append("- Move all **shared** modules (above) into this repo.")
    lines.append("- Add a **BOM** (recommended) to centralize versions for all apps.")
    lines.append("- CI publishes artifacts to Nexus/Artifactory/GitHub Packages.\n")

    lines.append("### Repo B/C/D: `app1-web`, `app2-web`, `app3-web`\n")
    lines.append("- Each repo contains one WAR (and any app-exclusive modules).")
    lines.append("- Each imports `platform-bom` (or uses a shared parent POM) and depends on `common-*`.\n")

    lines.append("## Notes / Risks Detected\n")
    lines.append(detect_cycles_note(poms, edges))

    if len(apps) > 3:
        lines.append(f"\nℹ️ Detected **{len(apps)}** app-like modules. Same pattern applies: 1 common repo + 1 repo per WAR.\n")

    return "\n".join(lines)


# -----------------------------
# Output writers
# -----------------------------
def write_modules_csv(path: Path, poms: List[PomInfo], repo: Path) -> None:
    with path.open("w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["artifact", "groupId", "artifactId", "version", "packaging", "moduleDir", "pomPath"])
        for p in sorted(poms, key=lambda x: x.gav()):
            w.writerow([
                p.gav(),
                p.group_id or "",
                p.artifact_id,
                p.version or "",
                p.packaging,
                safe_relpath(p.module_dir, repo),
                safe_relpath(p.pom_path, repo),
            ])


def write_deps_csv(path: Path, edges: List[Tuple[PomInfo, PomInfo]], repo: Path) -> None:
    with path.open("w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["from", "to", "fromPath", "toPath"])
        for a, b in sorted(edges, key=lambda e: (e[0].gav(), e[1].gav())):
            w.writerow([
                a.gav(),
                b.gav(),
                safe_relpath(a.module_dir, repo),
                safe_relpath(b.module_dir, repo),
            ])


def write_graph_dot(path: Path, poms: List[PomInfo], edges: List[Tuple[PomInfo, PomInfo]]) -> None:
    node_id: Dict[PomInfo, str] = {}
    for i, p in enumerate(sorted(poms, key=lambda x: x.gav())):
        node_id[p] = f"n{i}"

    lines = ["digraph G {", '  rankdir="LR";', "  node [shape=box];"]
    for p, nid in node_id.items():
        label = f"{p.artifact_id}\\n({p.packaging})"
        lines.append(f'  {nid} [label="{label}"];')
    for a, b in edges:
        lines.append(f"  {node_id[a]} -> {node_id[b]};")
    lines.append("}")
    path.write_text("\n".join(lines), encoding="utf-8")


def compute_code_overlap(poms: List[PomInfo]) -> List[Tuple[str, str, int, str]]:
    pkg_map: Dict[str, Dict[str, int]] = {}  # package -> {artifactId: file_count}
    cls_map: Dict[str, Set[str]] = {}        # fqcn -> {artifactId}

    for p in poms:
        files = list_java_files(p.module_dir)
        if not files:
            continue
        for jf in files:
            pkg = infer_package_from_path(jf, p.module_dir)
            if pkg:
                pkg_map.setdefault(pkg, {}).setdefault(p.artifact_id, 0)
                pkg_map[pkg][p.artifact_id] += 1
            fqcn = infer_class_fqcn(jf, p.module_dir)
            if fqcn:
                cls_map.setdefault(fqcn, set()).add(p.artifact_id)

    rows: List[Tuple[str, str, int, str]] = []

    for pkg, per_mod in pkg_map.items():
        if len(per_mod) >= 2:
            mods = ", ".join([f"{m}({c})" for m, c in sorted(per_mod.items())])
            rows.append(("package", pkg, len(per_mod), mods))

    for cls, mods in cls_map.items():
        if len(mods) >= 2:
            rows.append(("class", cls, len(mods), ", ".join(sorted(mods))))

    rows.sort(key=lambda r: (-r[2], r[0], r[1]))
    return rows


def write_code_overlap_csv(path: Path, rows: List[Tuple[str, str, int, str]]) -> None:
    with path.open("w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["kind", "name", "moduleCount", "modules"])
        for r in rows:
            w.writerow(list(r))


# -----------------------------
# Main analysis
# -----------------------------
def analyze(repo: Path, out_dir: Path, scan_sources: bool = True) -> None:
    pom_paths = [p for p in repo.rglob("pom.xml") if p.is_file()]
    pom_paths = [p for p in pom_paths if "target" not in p.parts]

    if not pom_paths:
        raise SystemExit(f"No pom.xml found under {repo}")

    poms_by_path: Dict[Path, PomInfo] = {}
    for p in pom_paths:
        try:
            info = parse_pom(p)
            poms_by_path[info.pom_path] = info
        except Exception as e:
            print(f"[WARN] Failed to parse {p}: {e}", file=sys.stderr)

    if not poms_by_path:
        raise SystemExit("No valid pom.xml files could be parsed.")

    finalize_coords(poms_by_path)
    poms = list(poms_by_path.values())

    idx = build_internal_index(poms)

    edges: List[Tuple[PomInfo, PomInfo]] = []
    for p in poms:
        for d in p.dependencies:
            target = idx.get(d.ga())
            if target:
                if d.scope and d.scope.strip() == "test":
                    continue
                edges.append((p, target))

    out_dir.mkdir(parents=True, exist_ok=True)

    write_modules_csv(out_dir / "modules.csv", poms, repo)
    write_deps_csv(out_dir / "deps.csv", edges, repo)
    write_graph_dot(out_dir / "graph.dot", poms, edges)

    if scan_sources:
        overlap_rows = compute_code_overlap(poms)
        write_code_overlap_csv(out_dir / "code_overlap.csv", overlap_rows)

    proposal = propose_split(poms, edges)
    (out_dir / "proposal.md").write_text(proposal, encoding="utf-8")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default=".", help="Path to monorepo root")
    ap.add_argument("--out", default="./monorepo-analysis", help="Output directory for reports")
    ap.add_argument("--no-source-scan", action="store_true", help="Disable src/main/java overlap scan")
    args = ap.parse_args()

    repo = Path(args.repo).resolve()
    out_dir = Path(args.out).resolve()

    analyze(repo, out_dir, scan_sources=(not args.no_source_scan))

    print(f"Done. Reports written to: {out_dir}")
    print(f"- proposal: {out_dir / 'proposal.md'}")
    print(f"- graph:    {out_dir / 'graph.dot'} (render: dot -Tpng graph.dot -o graph.png)")
    print(f"- modules:  {out_dir / 'modules.csv'}")
    print(f"- deps:     {out_dir / 'deps.csv'}")
    if not args.no_source_scan:
        print(f"- overlap:  {out_dir / 'code_overlap.csv'}")


if __name__ == "__main__":
    main()

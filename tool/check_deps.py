#!/usr/bin/env python3
"""Dependency-direction check for the dsh-flutter workspace.

dsh's own layering (docs/subsystems/web-client.md, "Layers and ownership") is
one-way, and so is ours:

    client  <-  models  <-  conversation  <-  slots
                                              features/*   (never each other)
    theme   <-  ui                                         (never client)
    i18n    leaf                                           (imports nothing)
    highlight  leaf                                        (imports nothing; ui may use it)
    apps/*  composition root: may import everything

The check reads two sources of truth and fails on any edge not listed in
ALLOWED: the `dsh_*` entries of each package's pubspec.yaml, and every
`package:dsh_*` import/export in its Dart files (lib, test, bin, ...). Tools
under tool/ are exempt. It also fails on dependency cycles and on a relative
import that leaves the package.

    tool/check_deps.py [--root DIR]      exit 1 and list violations
"""
import argparse
import pathlib
import re
import sys

# layer -> layers it may depend on (besides itself)
ALLOWED = {
    'client': set(),
    'models': {'client'},
    'conversation': {'models', 'client'},
    'slots': {'conversation', 'models', 'client'},
    'theme': set(),
    'ui': {'theme', 'i18n', 'highlight'},
    'i18n': set(),
    'highlight': set(),
    'feature': {'slots', 'conversation', 'models', 'client', 'ui', 'theme', 'i18n'},
    'app': {'client', 'models', 'conversation', 'slots', 'theme', 'ui', 'i18n', 'highlight', 'feature'},
}

LAYER_OF_PACKAGE = {
    'dsh_client': 'client',
    'dsh_models': 'models',
    'dsh_conversation': 'conversation',
    'dsh_slots': 'slots',
    'dsh_theme': 'theme',
    'dsh_ui': 'ui',
    'dsh_i18n': 'i18n',
    'dsh_highlight': 'highlight',
}

# Statements of intent, checked explicitly so a future edit of ALLOWED cannot
# silently weaken them.
NEVER = [
    ('ui', 'client', 'ui must never import client'),
    ('theme', 'client', 'theme must never import client'),
    ('ui', 'models', 'ui must never import models'),
    ('theme', 'models', 'theme must never import models'),
    ('feature', 'feature', 'features never import each other (go through slots and injected services)'),
]

IMPORT = re.compile(r'''^\s*(?:import|export)\s+['"]package:(dsh_[a-z0-9_]+)/''')
RELATIVE = re.compile(r'''^\s*(?:import|export)\s+['"]((?:\.\./)+[^'"]*)['"]''')
DEP = re.compile(r'^  (dsh_[a-z0-9_]+):')
NAME = re.compile(r'^name:\s*([a-z0-9_]+)\s*$')
# Dev tooling under tool/ (the parity capture harness): packages may depend on it from test/parity only.
TOOL_PACKAGES = {'dsh_parity'}
SKIP_DIRS = {'.dart_tool', 'build', '.git', 'node_modules', '.local'}


class Package:
    def __init__(self, directory, name, layer):
        self.directory = directory
        self.name = name
        self.layer = layer


def discover(root):
    packages = {}
    for sub in ('packages', 'features', 'apps'):
        base = root / sub
        if not base.is_dir():
            continue
        for pubspec in sorted(base.glob('*/pubspec.yaml')):
            name = None
            for line in pubspec.read_text().splitlines():
                m = NAME.match(line)
                if m:
                    name = m.group(1)
                    break
            if name is None:
                continue
            if sub == 'features':
                layer = 'feature'
            elif sub == 'apps':
                layer = 'app'
            else:
                layer = LAYER_OF_PACKAGE.get(name)
            packages[name] = Package(pubspec.parent, name, layer)
    return packages


def pubspec_edges(pkg):
    edges = []
    in_deps = False
    for number, line in enumerate((pkg.directory / 'pubspec.yaml').read_text().splitlines(), 1):
        if re.match(r'^(dependencies|dev_dependencies|dependency_overrides):', line):
            in_deps = True
            continue
        if re.match(r'^\S', line):
            in_deps = False
        if in_deps:
            m = DEP.match(line)
            if m:
                edges.append((m.group(1), 'pubspec.yaml', number))
    return edges


def import_edges(pkg, root):
    edges = []
    problems = []
    for path in sorted(pkg.directory.rglob('*.dart')):
        rel = path.relative_to(pkg.directory)
        if SKIP_DIRS & set(rel.parts):
            continue
        for number, line in enumerate(path.read_text().splitlines(), 1):
            m = IMPORT.match(line)
            if m:
                edges.append((m.group(1), str(path.relative_to(root)), number))
                continue
            r = RELATIVE.match(line)
            if r:
                target = (path.parent / r.group(1)).resolve()
                try:
                    target.relative_to(pkg.directory.resolve())
                except ValueError:
                    problems.append('%s:%d relative import leaves the package: %s' % (
                        path.relative_to(root), number, r.group(1)))
    return edges, problems


def check(root):
    packages = discover(root)
    violations = []
    graph = {name: set() for name in packages}
    for pkg in packages.values():
        if pkg.layer is None:
            violations.append('%s: package is not classified in tool/check_deps.py' % pkg.name)
            continue
        found, problems = import_edges(pkg, root)
        violations += problems
        for target_name, where, number in pubspec_edges(pkg) + found:
            if target_name == pkg.name or target_name in TOOL_PACKAGES:
                continue
            target = packages.get(target_name)
            if target is None:
                violations.append('%s:%d %s depends on unknown workspace package %s' % (
                    where, number, pkg.name, target_name))
                continue
            graph[pkg.name].add(target_name)
            if target.layer is None:
                continue
            for src_layer, dst_layer, why in NEVER:
                if pkg.layer == src_layer and target.layer == dst_layer:
                    violations.append('%s:%d %s -> %s: %s' % (where, number, pkg.name, target_name, why))
                    break
            else:
                same_layer_ok = pkg.layer == target.layer and pkg.layer not in ('feature',)
                if target.layer not in ALLOWED[pkg.layer] and not same_layer_ok:
                    violations.append('%s:%d %s (%s) must not depend on %s (%s)' % (
                        where, number, pkg.name, pkg.layer, target_name, target.layer))
    # cycles
    state = {}

    def visit(name, stack):
        state[name] = 1
        for nxt in sorted(graph.get(name, ())):
            if state.get(nxt) == 1:
                violations.append('dependency cycle: ' + ' -> '.join(stack + [name, nxt]))
            elif nxt not in state:
                visit(nxt, stack + [name])
        state[name] = 2

    for name in sorted(graph):
        if name not in state:
            visit(name, [])
    return packages, sorted(set(violations))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--root', default=str(pathlib.Path(__file__).resolve().parent.parent))
    args = ap.parse_args()
    packages, violations = check(pathlib.Path(args.root))
    if violations:
        print('check_deps: %d violation(s)' % len(violations))
        for v in violations:
            print('  ' + v)
        return 1
    print('check_deps: OK, %d packages, layering respected' % len(packages))
    return 0


if __name__ == '__main__':
    sys.exit(main())

import os, re, sys

root = 'lib'
files = []
for d, _, fs in os.walk(root):
    for f in fs:
        if f.endswith('.dart'):
            files.append(os.path.join(d, f))

decl_re = re.compile(r'^(?:abstract\s+|sealed\s+|final\s+|base\s+|mixin\s+)*(?:class|enum|mixin|extension type|typedef)\s+([A-Za-z_]\w*)', re.M)
func_re = re.compile(r'^(?:Future<[^>]*>|Future|void|bool|int|double|String|[A-Z]\w*(?:<[^>]*>)?\??|List<[^>]*>|Map<[^>]*>)\s+([a-zA-Z_]\w*)\s*(?:<[^>]*>)?\(', re.M)
var_re = re.compile(r'^(?:final|const)\s+(?:[\w<>?,\s]+\s)?([a-zA-Z_]\w*)\s*=', re.M)

declared = {}
for f in files:
    s = open(f).read()
    names = set(decl_re.findall(s))
    names |= set(func_re.findall(s))
    names |= set(var_re.findall(s))
    declared[f] = {n for n in names if not n.startswith('_')}

problems = 0
imp_re = re.compile(r"^import\s+'([^']+)'(?:\s+(?:as\s+\w+|show\s+[^;]+|hide\s+[^;]+))?;", re.M)
for f in files:
    s = open(f).read()
    visible = set(declared[f])
    for m in imp_re.finditer(s):
        target = m.group(1)
        if target.startswith('package:onyx') or target.startswith('package:com'):
            continue
        if target.startswith('package:') or target.startswith('dart:'):
            continue
        path = os.path.normpath(os.path.join(os.path.dirname(f), target))
        if not os.path.exists(path):
            print(f'{f}: import tidak ditemukan {target}')
            problems += 1
            continue
        visible |= declared.get(path, set())
    used = set(re.findall(r'\b([A-Z][A-Za-z0-9_]*)\b', re.sub(r"'[^'\n]*'", "''", s)))
    all_local = set()
    for v in declared.values():
        all_local |= v
    for name in sorted(used):
        if name in all_local and name not in visible:
            owners = [g for g, v in declared.items() if name in v]
            print(f'{f}: {name} dipakai tanpa impor (ada di {owners[0]})')
            problems += 1

for f in files:
    s = open(f).read()
    if s.count('{') != s.count('}') or s.count('(') != s.count(')') or s.count('[') != s.count(']'):
        stripped = re.sub(r"'(?:\\.|[^'\\\n])*'", "''", s)
        stripped = re.sub(r'"(?:\\.|[^"\\\n])*"', '""', stripped)
        if stripped.count('{') != stripped.count('}') or stripped.count('(') != stripped.count(')') or stripped.count('[') != stripped.count(']'):
            print(f'{f}: kurung tidak seimbang {{{stripped.count("{")}/{stripped.count("}")} (({stripped.count("(")}/{stripped.count(")")} [[{stripped.count("[")}/{stripped.count("]")}')
            problems += 1

print('selesai, masalah:', problems)
sys.exit(1 if problems else 0)

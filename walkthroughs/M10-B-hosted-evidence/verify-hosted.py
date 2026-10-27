import json, re, sys, hashlib
from pathlib import Path
from collections import Counter
root=Path(sys.argv[1])
sha=sys.argv[2]
local=Path(sys.argv[3])
summary=json.loads((root/'summary.metrics.json').read_text())
gates=summary['gates']
expected={'guard','guard-fixtures','swift-build','isolation-gate','full-test-suite','build-dev-app','packaging'}
assert {g['gate'] for g in gates}==expected
assert all(g['state']=='passed' and g['producer_exit']==0 and g['verification_exit']==0 and not g['verification_problems'] for g in gates)
assert 'github_sha: '+sha in (root/'runner-and-toolchain.txt').read_text()
metrics={name:json.loads((root/(name+'.metrics.json')).read_text()) for name in expected}
assert all(m['effective_exit']==0 and m['skipped']==0 for m in metrics.values())
streams='\n'.join((root/('full-test-suite.'+x)).read_text() for x in ['stdout','stderr'])
events=re.findall(r'^.*?✔ Test (?!run with)([^\s(]+).*?passed',streams,re.M)
local_events=json.loads(local.read_text())
counts=Counter(events); local_counts=Counter(local_events)
assert len(events)==468, len(events)
assert counts==local_counts, {'missing':list((local_counts-counts).elements()),'extra':list((counts-local_counts).elements())}
assert metrics['guard-fixtures']['parsed']['tests']==21
assert metrics['packaging']['parsed']['tests']==9
assert '-load-plugin' not in (root/'full-test-suite.command.txt').read_text()
receipt={'sha':sha,'all_seven_gates_pass':True,'hosted_test_events':len(events),'local_hosted_event_multisets_equal':True,'guard_fixtures':21,'packaging_checks':9,'skipped':0,'native_macro_loading':True,'artifact_files':len([p for p in root.iterdir() if p.is_file()]),'files_sha256':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(root.iterdir()) if p.is_file()}}
(root.parent/'hosted-verification.json').write_text(json.dumps(receipt,indent=2)+'\n')
print(json.dumps({k:v for k,v in receipt.items() if k!='files_sha256'},indent=2))
print((root/'summary.txt').read_text())

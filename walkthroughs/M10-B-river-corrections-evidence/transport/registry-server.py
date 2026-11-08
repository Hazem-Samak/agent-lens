import json,sys,threading,subprocess,time
from pathlib import Path
from http.server import ThreadingHTTPServer,BaseHTTPRequestHandler
F=Path(__file__).parent
class Registry(BaseHTTPRequestHandler):
 def do_GET(self):
  with (F/'registry-requests.jsonl').open('a') as out:out.write(json.dumps({'path':self.path,'time':time.time()})+'\n')
  if self.path.lower()!='/@openai%2fcodex':self.send_error(404);return
  doc={'name':'@openai/codex','dist-tags':{'latest':'2.0.0','next':'3.0.0-beta.1'},'versions':{'1.0.0':{'name':'@openai/codex','version':'1.0.0'},'2.0.0':{'name':'@openai/codex','version':'2.0.0'},'3.0.0-beta.1':{'name':'@openai/codex','version':'3.0.0-beta.1'}}}
  data=json.dumps(doc).encode();self.send_response(200);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(data)));self.end_headers();self.wfile.write(data)
 def log_message(self,*args):pass
server=ThreadingHTTPServer(('127.0.0.1',0),Registry);url=f'http://127.0.0.1:{server.server_port}/';(F/'registry-url.txt').write_text(url)
print(url,flush=True)
if '--probe' in sys.argv:
 threading.Thread(target=server.serve_forever,daemon=True).start();env=json.loads((F/'environment.json').read_text());args=[str(F/'manager-bin/npm'),'view','@openai/codex@latest','name','version','dist-tags.latest','--json','--global',f'--registry={url}',f'--@openai:registry={url}','--prefer-online','--offline=false','--fetch-retries=0','--fetch-timeout=10000']
 p=subprocess.run(args,cwd=F,env=env,capture_output=True,text=True,timeout=20);(F/'worker-controlled-registry-readiness.json').write_text(json.dumps({'argv':args,'exit':p.returncode,'stdout':p.stdout,'stderr':p.stderr},indent=2));print(p.returncode,p.stdout,flush=True);server.shutdown();raise SystemExit(p.returncode)
try:server.serve_forever()
except KeyboardInterrupt:pass
finally:server.server_close()

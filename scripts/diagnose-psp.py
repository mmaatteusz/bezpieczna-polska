"""Bounded transparent HTTP diagnostics. No proxies, spoofing, retries or bypasses."""
import subprocess,json,pathlib,sys,tempfile,datetime,re
out=pathlib.Path(sys.argv[1] if len(sys.argv)>1 else 'docs/validation/psp-http');out.mkdir(parents=True,exist_ok=True)
urls=[('catalog','https://gdziesieukryc.pl/PS_XML/punkty_schronienia.xml'),('dataset','https://api.dane.gov.pl/1.4/datasets/28058'),('mirror','https://api.dane.gov.pl/resources/1393918,punkty-schronienia-dane-csv/file')]
results=[]
for name,url in urls:
 for protocol in (['--http1.1','--http2'] if name=='catalog' else ['--http2']):
  with tempfile.TemporaryDirectory() as tmp:
   p=pathlib.Path(tmp);args=['curl','--silent','--show-error','--max-time','25','--max-filesize','1000000',protocol,'-A','BezpiecznaPolska-preview/0.1 (official data connectivity diagnosis)','-H','Accept: application/xml,application/json,text/csv,text/html','-D',str(p/'headers'),'-o',str(p/'body'),'-w','%{http_code} %{http_version} %{num_redirects}',url]
   r=subprocess.run(args,capture_output=True,text=True)
   headers=(p/'headers').read_text() if (p/'headers').exists() else ''
   keep=[line for line in headers.splitlines() if re.match(r'^(HTTP/|server:|via:|cf-ray:|cf-cache-status:|retry-after:|location:|content-type:|x-ratelimit)',line,re.I)]
   body=(p/'body').read_text(errors='replace') if (p/'body').exists() else ''
   title=re.search(r'<title>(.*?)</title>',body,re.S|re.I)
   item={'name':name,'url':url,'requestedProtocol':protocol,'curlResult':r.stdout,'exitCode':r.returncode,'headers':keep,'title':title.group(1) if title else None,'bodyPreview':re.sub('<[^>]+>',' ',body[:20000]).strip()[:2000] if 'text/html' in headers else None}
   results.append(item);print(json.dumps(item,ensure_ascii=False),flush=True)
report={'observedAt':datetime.datetime.now(datetime.timezone.utc).isoformat(),'observations':results,'note':'No automatic redirect following; no changed identity/network; at most two catalog GETs. Server-side policy cannot be proven without owner logs.'}
(out/'psp-http.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))

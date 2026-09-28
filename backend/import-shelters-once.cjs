const crypto=require('node:crypto');
const zlib=require('node:zlib');

(async()=>{
  const shas=(process.env.IMPORT_SHAS||'').split(',').filter(Boolean);
  if(shas.length!==16)throw new Error('IMPORT_SHA_COUNT_'+shas.length);

  let b64='';
  for(const sha of shas){
    const response=await fetch('https://api.github.com/repos/mmaatteusz/bezpieczna-polska/git/blobs/'+sha,{
      headers:{accept:'application/vnd.github+json','user-agent':'BezpiecznaPolska-shelter-import/2.0'},
      signal:AbortSignal.timeout(30000)
    });
    if(!response.ok)throw new Error('GITHUB_BLOB_'+sha+'_'+response.status);
    const payload=await response.json();
    if(payload.encoding!=='base64')throw new Error('GITHUB_BLOB_ENCODING_'+sha);
    b64+=Buffer.from(String(payload.content||'').replace(/\s/g,''),'base64').toString('utf8');
  }

  const csv=zlib.gunzipSync(Buffer.from(b64,'base64')).toString('utf8');
  const lines=(csv.match(/\n/g)||[]).length;
  const rows=lines-1;
  const sha256=crypto.createHash('sha256').update(csv).digest('hex');

  if(lines!==Number(process.env.IMPORT_EXPECTED_LINES))throw new Error('LINE_COUNT_'+lines);
  if(rows!==Number(process.env.IMPORT_EXPECTED_ROWS))throw new Error('ROW_COUNT_'+rows);
  if(sha256!==process.env.IMPORT_EXPECTED_SHA256)throw new Error('SHA256_'+sha256);
  const normalizedCsv=csv.replace(/^\uFEFF/,'');
  if(!normalizedCsv.startsWith('Identyfikator publiczny,Nazwa,Rodzaj obiektu'))throw new Error('CSV_HEADER_INVALID');

  console.log('IMPORT_ASSEMBLED',JSON.stringify({lines,rows,bytes:Buffer.byteLength(csv),sha256}));

  const token=process.env.IMPORT_ADMIN_TOKEN||'';
  if(token.length<32)throw new Error('IMPORT_TOKEN_MISSING');
  const target=(process.env.IMPORT_API_BASE_URL||'').replace(/\/+$/,'')+'/admin/shelters/import';
  const response=await fetch(target,{
    method:'POST',
    headers:{authorization:'Bearer '+token,'content-type':'text/csv; charset=utf-8'},
    body:csv,
    signal:AbortSignal.timeout(180000)
  });
  const raw=await response.text();
  let body;
  try{body=JSON.parse(raw)}catch{body={raw:raw.slice(0,500)}}
  console.log('IMPORT_RESPONSE',JSON.stringify({status:response.status,body}));
  if(!response.ok||!body?.ok)throw new Error('IMPORT_HTTP_'+response.status);
  if(Number(body.itemCount)!==rows)throw new Error('IMPORT_ITEM_COUNT_'+body.itemCount);
  console.log('IMPORT_OK',JSON.stringify({
    itemCount:body.itemCount,
    dataDate:body.dataDate,
    sourceUpdatedAt:body.sourceUpdatedAt,
    sourceContentHash:body.sourceContentHash,
    provenance:body.provenance
  }));
})().catch(error=>{console.error('IMPORT_FAILED',error&&error.stack||error);process.exit(1)});

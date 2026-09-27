const urls=[
 'https://api.dane.gov.pl/1.4/resources/1393918/data',
 'https://api.dane.gov.pl/1.4/resources/1393918/data?page=1&per_page=1',
 'https://api.dane.gov.pl/1.4/resources/1393918/data?page[number]=1&page[size]=1',
 'https://api.dane.gov.pl/1.4/resources/1393918/data?limit=1&offset=0',
 'https://api.dane.gov.pl/1.4/resources/1393918/data?page=1&per_page=100',
 'https://api.dane.gov.pl/1.4/resources/1393918/data?page=1&per_page=500',
 'https://api.dane.gov.pl/1.4/resources/1393918/data?page=1&per_page=1000',
 'https://api.dane.gov.pl/1.4/resources/1393918/data?page=1&per_page=5000',
];
for(const url of urls){
 try{
  const response=await fetch(url,{redirect:'manual',signal:AbortSignal.timeout(15000),headers:{'User-Agent':'BezpiecznaPolska-contract-probe/1.0','Accept':'application/json'}});
  const text=await response.text();
  let parsed=null;try{parsed=JSON.parse(text);}catch{}
  const summary=parsed?{
   topKeys:Object.keys(parsed),
   meta:parsed.meta??null,
   links:parsed.links??null,
   dataType:Array.isArray(parsed.data)?'array':typeof parsed.data,
   dataLength:Array.isArray(parsed.data)?parsed.data.length:null,
   first:Array.isArray(parsed.data)?parsed.data[0]??null:parsed.data??null,
  }:{bodyPrefix:text.slice(0,1500)};
  console.log('PROBE',JSON.stringify({url,status:response.status,contentType:response.headers.get('content-type'),location:response.headers.get('location'),summary}));
 }catch(error){console.log('PROBE',JSON.stringify({url,error:error instanceof Error?error.message:String(error)}));}
}

for(const url of [
 'https://api.dane.gov.pl/resources/1393918,punkty-schronienia-dane-csv/jsonld',
 'https://api.dane.gov.pl/media/resources/20260310/punkty_schronienia_875cc428.jsonld'
]){
 try{
  const response=await fetch(url,{method:'GET',redirect:'manual',signal:AbortSignal.timeout(15000),headers:{'User-Agent':'BezpiecznaPolska-contract-probe/1.0','Accept':'application/ld+json,application/json,*/*','Range':'bytes=0-2047'}});
  const body=await response.text();
  console.log('JSONLD_PROBE',JSON.stringify({url,status:response.status,location:response.headers.get('location'),contentType:response.headers.get('content-type'),contentLength:response.headers.get('content-length'),contentRange:response.headers.get('content-range'),lastModified:response.headers.get('last-modified'),bodyPrefix:body.slice(0,1000).replace(/\s+/g,' ')}));
 }catch(error){console.log('JSONLD_PROBE',JSON.stringify({url,error:error instanceof Error?error.message:String(error)}));}
}

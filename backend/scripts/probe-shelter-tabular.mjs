const urls=[
 'https://api.dane.gov.pl/1.4/resources/1393918/data',
 'https://api.dane.gov.pl/1.4/resources/1393918/data?page=1&per_page=1',
 'https://api.dane.gov.pl/1.4/resources/1393918/data?page[number]=1&page[size]=1',
 'https://api.dane.gov.pl/1.4/resources/1393918/data?limit=1&offset=0',
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

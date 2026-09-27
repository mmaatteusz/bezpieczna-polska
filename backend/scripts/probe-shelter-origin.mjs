const targets=[
  'https://gdziesieukryc.pl/PS_XML/punkty_schronienia.csv',
  'https://api.dane.gov.pl/resources/1393918,punkty-schronienia-dane-csv/file',
];
const profiles=[
  {name:'app',headers:{'User-Agent':'BezpiecznaPolska-preview/0.1 (source contract evaluation)','Accept':'text/csv,*/*'}},
  {name:'browser',headers:{'User-Agent':'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/152.0.0.0 Safari/537.36','Accept':'text/csv,text/plain,*/*','Accept-Language':'pl-PL,pl;q=0.9,en;q=0.8'}},
  {name:'browser-referer',headers:{'User-Agent':'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/152.0.0.0 Safari/537.36','Accept':'text/csv,text/plain,*/*','Accept-Language':'pl-PL,pl;q=0.9,en;q=0.8','Referer':'https://gdziesieukryc.pl/'}},
];
for(const url of targets){
 for(const profile of profiles){
  try{
   const response=await fetch(url,{redirect:'follow',signal:AbortSignal.timeout(30000),headers:{...profile.headers,Range:'bytes=0-4095'}});
   const finalUrl=response.url;
   const reader=response.body?.getReader();
   let first='';
   if(reader){
    const {value}=await reader.read();
    if(value)first=new TextDecoder('utf-8',{fatal:false}).decode(value).slice(0,300);
    await reader.cancel();
   }
   console.log('ORIGIN_PROBE',JSON.stringify({
    url,profile:profile.name,status:response.status,finalUrl,
    contentType:response.headers.get('content-type'),
    contentLength:response.headers.get('content-length'),
    contentRange:response.headers.get('content-range'),
    first:first.replace(/[\r\n]+/g,' '),
   }));
  }catch(error){
   console.log('ORIGIN_PROBE',JSON.stringify({url,profile:profile.name,error:error instanceof Error?error.message:String(error)}));
  }
 }
}

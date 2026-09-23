import {writeFile,mkdir} from 'node:fs/promises';
import {dirname} from 'node:path';
import {fetchPublic} from '../dist/adapters.js';
import {imgwMeteoAdapter,imgwHydroAdapter,IMGW_METEO_URL,IMGW_HYDRO_URL} from '../dist/imgw-adapter.js';
const out=process.argv[2]??'imgw-live.json',now=new Date();
const meteo=await imgwMeteoAdapter.sync({now,fetchText:fetchPublic}),hydro=await imgwHydroAdapter.sync({now,fetchText:fetchPublic});
const report={retrievedAt:now.toISOString(),sourceAttribution:'Źródłem pochodzenia danych jest Instytut Meteorologii i Gospodarki Wodnej – Państwowy Instytut Badawczy',processingNotice:'Dane Instytutu Meteorologii i Gospodarki Wodnej – Państwowego Instytutu Badawczego zostały przetworzone',meteo:{url:IMGW_METEO_URL,adapterVersion:imgwMeteoAdapter.version,complete:meteo.complete,eventCount:meteo.events.length,events:meteo.events},hydro:{url:IMGW_HYDRO_URL,adapterVersion:imgwHydroAdapter.version,complete:hydro.complete,eventCount:hydro.events.length,events:hydro.events}};
await mkdir(dirname(out),{recursive:true});await writeFile(out,JSON.stringify(report,null,2));console.log(JSON.stringify({meteo:report.meteo.eventCount,hydro:report.hydro.eventCount,complete:meteo.complete&&hydro.complete}));

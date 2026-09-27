import {createHash} from 'node:crypto';
import {gunzipSync} from 'node:zlib';

const sha256=(value:Buffer|string)=>createHash('sha256').update(value).digest('hex');

export function decodeShelterSnapshot(parts:string[],expectedGzipSha256:string,expectedCsvSha256:string){
 if(!parts.length)throw new Error('SHELTER_BOOTSTRAP_NO_PARTS');
 if(!/^[a-f0-9]{64}$/.test(expectedGzipSha256)||!/^[a-f0-9]{64}$/.test(expectedCsvSha256))throw new Error('SHELTER_BOOTSTRAP_INVALID_HASH');
 const encoded=parts.join('');
 if(!encoded||!/^[A-Za-z0-9+/=]+$/.test(encoded))throw new Error('SHELTER_BOOTSTRAP_INVALID_BASE64');
 const gzip=Buffer.from(encoded,'base64');
 if(sha256(gzip)!==expectedGzipSha256)throw new Error('SHELTER_BOOTSTRAP_GZIP_HASH_MISMATCH');
 let csv:Buffer;
 try{csv=gunzipSync(gzip);}catch{throw new Error('SHELTER_BOOTSTRAP_GZIP_INVALID');}
 if(sha256(csv)!==expectedCsvSha256)throw new Error('SHELTER_BOOTSTRAP_CSV_HASH_MISMATCH');
 const text=csv.toString('utf8');
 if(!text.includes('\n'))throw new Error('SHELTER_BOOTSTRAP_CSV_EMPTY');
 return text;
}

export function validateBootstrapBaseUrl(value:string){
 const url=new URL(value.endsWith('/')?value:value+'/');
 if(url.protocol!=='https:'||url.hostname!=='raw.githubusercontent.com'||url.username||url.password||url.search||url.hash)throw new Error('SHELTER_BOOTSTRAP_URL_DENIED');
 if(!url.pathname.startsWith('/mmaatteusz/bezpieczna-polska/')||!url.pathname.includes('/ops/shelters/parts/'))throw new Error('SHELTER_BOOTSTRAP_URL_DENIED');
 return url;
}

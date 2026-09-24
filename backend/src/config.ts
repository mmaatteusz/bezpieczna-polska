export const APP_VERSION='0.1.0-alpha.21';
export type AppEnv='development'|'preview'|'production';
export function publicHttpsUrl(value:string):URL{
 const url=new URL(value);
 const host=url.hostname.toLowerCase();
 if(url.protocol!=='https:'||url.username||url.password||url.search||url.hash||url.pathname!=='/'||
    !host.includes('.')||host==='localhost'||host.endsWith('.localhost')||
    /(?:^|\.)(?:local|test|example|invalid|example\.(?:com|org|net))$/.test(host)||
    /(?:^|[.-])(?:dev|development|staging|preview)(?:[.-]|$)/.test(host)||
    /^(?:127\.|10\.|192\.168\.|169\.254\.|0\.|172\.(?:1[6-9]|2\d|3[01])\.)/.test(host)||
    host.includes(':'))throw new Error('Production requires a public HTTPS backend hostname');
 return url;
}
export function serverConfig(env:NodeJS.ProcessEnv=process.env){
 const stage=env.APP_ENV??'development';
 if(!['development','preview','production'].includes(stage))throw new Error('Invalid APP_ENV');
 const production=stage==='production';
 if(production){
  if(env.NODE_ENV!=='production')throw new Error('Production requires NODE_ENV=production');
  if(!env.DATABASE_URL||!/^postgres(?:ql)?:\/\//.test(env.DATABASE_URL))throw new Error('Production requires PostgreSQL');
  if(!env.ADMIN_TOKEN||env.ADMIN_TOKEN.length<32||new Set(env.ADMIN_TOKEN).size<12)throw new Error('Production requires a strong ADMIN_TOKEN');
  publicHttpsUrl(env.PUBLIC_BASE_URL??'');
  if(!/^[a-f0-9]{40}$/.test(env.BUILD_SHA??''))throw new Error('Production requires a 40-character BUILD_SHA');
  if(env.TRUST_PROXY!=='true')throw new Error('Production reverse proxy must be trusted explicitly');
  const pushKey=env.PUSH_TOKEN_ENCRYPTION_KEY;
  const pushKeyBytes=pushKey?Buffer.from(pushKey,/^[a-f0-9]{64}$/i.test(pushKey)?'hex':'base64'):null;
  if(pushKey&&pushKeyBytes?.length!==32)throw new Error('Invalid push encryption key');
  if(env.FCM_SERVICE_ACCOUNT_JSON){
   if(!pushKey)throw new Error('FCM requires push token encryption');
   try{const f=JSON.parse(env.FCM_SERVICE_ACCOUNT_JSON);if(!f.project_id||!f.client_email||!f.private_key)throw new Error();}
   catch{throw new Error('Invalid FCM credential configuration');}
  }
  const apns=['APNS_KEY_ID','APNS_TEAM_ID','APNS_BUNDLE_ID','APNS_PRIVATE_KEY_P8'] as const;
  if(apns.some(k=>!!env[k])&&(!pushKey||apns.some(k=>!env[k])||env.APNS_ENV==='sandbox'))
   throw new Error('Incomplete production APNs credential configuration');
 }
 const port=Number(env.PORT??8080);
 if(!Number.isInteger(port)||port<1||port>65535)throw new Error('Invalid PORT');
 const poolMax=Number(env.PG_POOL_MAX??10);
 if(!Number.isInteger(poolMax)||poolMax<1||poolMax>50)throw new Error('Invalid PG_POOL_MAX');
 return {stage:stage as AppEnv,production,port,host:env.HOST??(production?'0.0.0.0':'127.0.0.1'),buildSha:env.BUILD_SHA??'unknown'};
}

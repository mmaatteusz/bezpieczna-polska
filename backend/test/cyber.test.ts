import test from 'node:test';
import assert from 'node:assert/strict';
import {parseCertFeed,parseCsirtGovRssLanding,certAdapter,CERT_FEED} from '../src/cyber-adapter.js';
import {canCorrelate,correlate} from '../src/correlation.js';
import {computeStatus,type Event,type Health} from '../src/domain.js';

const now=new Date('2026-09-21T12:00:00Z');
const feed=`<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0"><channel>
<title>moje.cert.pl - komunikaty bezpieczeństwa</title>
<link>https://moje.cert.pl/komunikaty/</link>
<item>
<title>Krytyczna podatność CVE-2026-12345 w Example Gateway</title>
<link>https://moje.cert.pl/komunikaty/2026/200/krytyczna-podatnosc-cve-2026-12345-w-example-gateway/</link>
<description><![CDATA[Zespół CERT Polska informuje o krytycznej podatności CVE-2026-12345. Wymagana jest pilna aktualizacja.]]></description>
<pubDate>Mon, 21 Sep 2026 12:00:00 +0200</pubDate>
<category>Dla administratorów</category>
</item>
<item>
<title>Uwaga na kampanię phishingową</title>
<link>https://moje.cert.pl/komunikaty/2026/201/uwaga-na-kampanie-phishingowa/</link>
<description><![CDATA[CERT Polska obserwuje kampanię phishingową wymierzoną w użytkowników poczty.]]></description>
<pubDate>Mon, 21 Sep 2026 11:00:00 +0200</pubDate>
<category>Dla użytkowników</category>
</item>
<item>
<title>Raport miesięczny za sierpień 2026</title>
<link>https://moje.cert.pl/komunikaty/2026/202/raport-miesieczny-za-sierpien-2026/</link>
<description>Raport statystyczny.</description>
<pubDate>Mon, 21 Sep 2026 10:00:00 +0200</pubDate>
<category>Raporty miesięczne CERT Polska</category>
</item>
</channel></rss>`;

test('CERT RSS normalizes actionable cyber advisories conservatively',()=>{
 const events=parseCertFeed(feed,now);
 assert.equal(events.length,2);
 const critical=events[0];
 assert.equal(critical.id,'CERT-2026-200');
 assert.equal(critical.eventType,'CYBER');
 assert.equal(critical.severity,'HIGH');
 assert.equal(critical.verification,'CONFIRMED');
 assert.equal(critical.lifecycle,'UNKNOWN');
 assert.equal(critical.officialWarning,false);
 assert.deepEqual(critical.regions,[]);
 assert.equal(critical.geometry,null);
 assert.equal(critical.sources[0].id,'CERT');
 assert.equal(critical.publicationDate,'2026-09-21');
 assert.equal(events[1].severity,'NORMAL');
});

test('CERT RSS rejects unsafe XML, invalid URLs and empty actionable feed',()=>{
 assert.throws(()=>parseCertFeed('<!DOCTYPE x [<!ENTITY y "z">]>'+feed,now),/UNSAFE_XML/);
 assert.throws(()=>parseCertFeed(feed.replace('https://moje.cert.pl/komunikaty/2026/200/','https://evil.example/komunikaty/2026/200/'),now),/URL_DENIED/);
 const reportOnly=feed.replace(/<item>[\s\S]*?<\/item>\s*<item>[\s\S]*?<\/item>\s*/,'');
 assert.throws(()=>parseCertFeed(reportOnly,now),/NO_ACTIONABLE/);
});

test('CERT adapter uses only the official feed and reports recent-publication coverage',async()=>{
 const seen:string[]=[];
 const batch=await certAdapter.sync({now,fetchText:async url=>{seen.push(url);return feed;}});
 assert.deepEqual(seen,[CERT_FEED]);
 assert.equal(batch.events.length,2);
 assert.equal(batch.complete,false);
 assert.equal(batch.coverage,'RECENT_PUBLICATIONS');
});

test('CSIRT GOV RSS landing is validated and an empty public channel list stays empty',()=>{
 const html=`<main><section><h3>Co to jest RSS?</h3><p>Opis</p><h3>Podłączanie kanałów RSS</h3><div class="box-default"><h3>Lista</h3><ul></ul></div></section></main>`;
 assert.deepEqual(parseCsirtGovRssLanding(html),[]);
 assert.throws(()=>parseCsirtGovRssLanding('<main>changed</main>'),/CONTRACT/);
});

function asCsirt(cert:Event,cve='CVE-2026-12345'):Event{
 return {
  ...cert,
  id:'CSIRT-GOV-test',
  title:`Ostrzeżenie dotyczące ${cve} w Example Gateway`,
  description:`CSIRT GOV ostrzega o podatności ${cve} w Example Gateway.`,
  publishedAt:'2026-09-21T11:00:00Z',
  sources:[{id:'CSIRT_GOV',name:'CSIRT GOV',url:'https://www.csirt.gov.pl/cer/test',tier:1}],
  revision:1
 };
}

test('CERT and CSIRT GOV correlate only on strong cyber evidence',()=>{
 const cert=parseCertFeed(feed,now)[0];
 const same=asCsirt(cert);
 assert.equal(canCorrelate(cert,same),true);
 assert.equal(correlate([cert,same]).filter(i=>i.relatedEventIds.length===2).length,1);
 assert.equal(canCorrelate(cert,asCsirt(cert,'CVE-2026-99999')),false);
 const unrelated={...asCsirt(cert),title:'Inny incydent bez wspólnego identyfikatora',description:'Inny produkt i inny wektor ataku.',publishedAt:'2026-09-21T11:00:00Z'};
 assert.equal(canCorrelate(cert,unrelated),false);
});

test('Cyber source health does not redefine physical-safety coverage',()=>{
 const base:Health={id:'RCB',name:'RCB',url:'https://www.gov.pl/web/rcb/komunikaty',state:'HEALTHY',lastSuccess:now.toISOString(),lastFailure:null,lastItemTime:null,failureCount:0,responseTime:1,maxAgeSeconds:900,complete:true,enabled:true,lastAttempt:now.toISOString(),coverage:'ACTIVE_WARNINGS'};
 const cert:Health={...base,id:'CERT',name:'CERT Polska',url:'https://moje.cert.pl/komunikaty/',state:'BROKEN',complete:false,lastFailure:now.toISOString(),errorCode:'SOURCE_HTTP_503'};
 const status=computeStatus([], [base,cert], 'PL', now);
 assert.equal(status.coverageState,'COMPLETE_FOR_CONFIGURED_SCOPE');
 assert.equal(status.hazardLevel,'NO_ACTIVE_WARNINGS');
});

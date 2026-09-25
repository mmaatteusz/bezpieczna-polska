// Authority URLs re-verified on 2026-09-25.
// RSO is the nationwide transport used by WCZK. These 16 registry entries
// describe publishers/coverage, not 16 independent feeds or 16 health checks.
const authorities:[string,string,string][]=[
 ['02','Dolnośląskie','https://www.gov.pl/web/dolnoslaski-uw'],
 ['04','Kujawsko-pomorskie','https://www.gov.pl/web/uw-kujawsko-pomorski'],
 ['06','Lubelskie','https://www.lublin.uw.gov.pl/'],
 ['08','Lubuskie','https://www.lubuskie.uw.gov.pl/'],
 ['10','Łódzkie','https://www.gov.pl/web/uw-lodzki'],
 ['12','Małopolskie','https://www.malopolska.uw.gov.pl/'],
 ['14','Mazowieckie','https://www.gov.pl/web/uw-mazowiecki'],
 ['16','Opolskie','https://www.gov.pl/web/uw-opolski'],
 ['18','Podkarpackie','https://rzeszow.uw.gov.pl/wczk/ostrzezenia'],
 ['20','Podlaskie','https://www.gov.pl/web/uw-podlaski'],
 ['22','Pomorskie','https://www.gdansk.uw.gov.pl/'],
 ['24','Śląskie','https://www.katowice.uw.gov.pl/usluga/ostrzezenia-i-raporty-wczk'],
 ['26','Świętokrzyskie','https://www.gov.pl/web/uw-swietokrzyski/'],
 ['28','Warmińsko-mazurskie','https://www.gov.pl/web/uw-warminsko-mazurski'],
 ['30','Wielkopolskie','https://www.poznan.uw.gov.pl/'],
 ['32','Zachodniopomorskie','https://www.szczecin.uw.gov.pl/'],
];

export const WCZK_SOURCES=authorities.map(([regionId,regionName,url])=>({
 id:'WCZK-'+regionId,
 name:'WCZK — '+regionName,
 url,
 regionId,
 coveredBy:'RSO' as const,
 deliveryChannel:regionId==='18'?'RSO_AND_OFFICIAL_PAGE':'RSO',
 directAdapterEnabled:regionId==='18',
 // Only the separate Podkarpackie HTML mirror has its own adapter. Other
 // provinces are already covered by the nationwide RSO adapter and must not
 // create duplicate NOT_CONFIGURED sources.
 enabled:regionId==='18',
 implementation:regionId==='18'?'DIRECT_OFFICIAL_PAGE_MIRROR':'RSO_TRANSPORT',
 independentSource:false,
 maxAgeSeconds:1800,
 adapterVersion:regionId==='18'?'1.1.0':null,
 integrationNote:regionId==='18'
  ?'WCZK publikuje przez RSO i równolegle na oficjalnej stronie PUW. Strona PUW jest dodatkowym kanałem tego samego wydawcy, nie niezależnym potwierdzeniem.'
  :'Komunikaty WCZK dla województwa są pobierane przez ogólnopolski kanał RSO. Ten wpis nie jest osobnym źródłem health ani niezależnym potwierdzeniem.',
}));

// Authority URLs verified against https://www.gov.pl/web/gov/uw on 2026-09-21.
// A registry entry is not an enabled adapter. No guessed feed endpoints.
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
 id:`WCZK-${regionId}`,name:`WCZK — ${regionName}`,url,regionId,enabled:regionId==='18',
 implementation:regionId==='18'?'IMPLEMENTED':'NOT_IMPLEMENTED',maxAgeSeconds:1800,
 adapterVersion:regionId==='18'?'1.0.0':null,
 integrationNote:regionId==='04'?'Oficjalna strona prezentuje kanał RSO autorstwa WCZK. Nie jest to drugie niezależne źródło. Osobny kanał WCZK nie został zweryfikowany.':regionId==='18'?'Oficjalny wykaz ostrzeżeń HTML. Brak daty publikacji pozostaje jawny; SVG nie jest geometrią geograficzną.':'Osobny maszynowy kanał WCZK nie został zweryfikowany. Rejestr nie potwierdza działającej integracji.',
}));

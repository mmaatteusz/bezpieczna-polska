import {WCZK_SOURCES} from './wczk-registry.js';
import type {Event} from './domain.js';
import type {Shelter} from './shelter.js';
import type {RadiationMeasurement} from './radiation.js';

export type SourceContext = {now: Date; previousEvents?: Event[]; fetchText: (url: string) => Promise<string>; fetchBytes?: (url: string) => Promise<Uint8Array>};
export type SourceBatch = {
  events: Event[];
  uaMetadata?: NonNullable<import('./domain.js').Health['uaMetadata']>;
  neptunMetadata?: NonNullable<import('./domain.js').Health['neptunMetadata']>;
  shelters?: Shelter[];
  radiationMeasurements?: RadiationMeasurement[];
  metadata?: {dataDate:string;sourceUpdatedAt:string;sourceContentHash:string;sourceUrl:string;datasetUrl:string;license:string;fallbackSelected?:'PRIMARY_OFFICIAL_SOURCE'|'SECONDARY_OFFICIAL_CURRENT_RESOURCE'|'TERTIARY_OFFICIAL_ARCHIVE';fallbackReason?:string|null};
  // A publication archive is never proof that there are no active warnings.
  complete: boolean;
  coverage: 'RECENT_PUBLICATIONS' | 'ACTIVE_WARNINGS' | 'FACILITY_CATALOG' | 'MEASUREMENT_NETWORK';
  pagesFetched: number;
};
export interface SourceAdapter {
  readonly id: string;
  readonly version: string;
  readonly minSyncIntervalSeconds?: number;
  sync(context: SourceContext): Promise<SourceBatch>;
}

export type SourceClass='STATUS'|'CONTEXT'|'REFERENCE'|'SITUATIONAL';
export type AbsenceSemantics='AUTHORITATIVE_EMPTY_SET'|'NOT_PROVABLE';

// A source may detect a warning without being able to prove that no warning exists.
// Only an authoritative current-state contract (for example IMGW ACTIVE_WARNINGS)
// may use AUTHORITATIVE_EMPTY_SET. Publication archives and filtered news stay
// NOT_PROVABLE even when their last synchronization was technically successful.
const contract=<T extends Record<string,unknown>>(source:T,sourceClass:SourceClass,absenceSemantics:AbsenceSemantics)=>
  ({...source,sourceClass,absenceSemantics});

// Enable sources one by one, in the agreed integration order.
export const SOURCES = [
  ...WCZK_SOURCES.filter(source=>source.directAdapterEnabled),
  contract({id: 'RCB', name: 'Rządowe Centrum Bezpieczeństwa', url: 'https://www.gov.pl/web/rcb/komunikaty', enabled: true},'STATUS','NOT_PROVABLE'),
  contract({id: 'SHELTERS', name: 'Punkty schronienia PSP / dane.gov.pl', url: 'https://dane.gov.pl/pl/dataset/28058,punkty-schronienia-w-polsce', enabled: true},'REFERENCE','NOT_PROVABLE'),
  contract({id: 'LEVELS', name: 'Stopnie alarmowe RP', url: 'https://www.gov.pl/web/rcb/komunikaty', enabled: true},'CONTEXT','NOT_PROVABLE'),
  contract({id: 'RSO', name: 'Regionalny System Ostrzegania — komunikaty WCZK', url: 'https://komunikaty.tvp.pl/', enabled: true, implementation:'NATIONWIDE_WCZK_TRANSPORT_XML', integrationNote:'RSO jest ogólnopolskim kanałem dystrybucji komunikatów wprowadzanych przez WCZK. Wojewódzkie wpisy WCZK są traktowane jako ten sam wydawca/transport, a nie niezależne potwierdzenia. Publiczny XML nie jest traktowany jako kompletny kontrakt aktywnych alarmów.'},'STATUS','NOT_PROVABLE'),
  contract({id: 'IMGW_METEO', name: 'IMGW-PIB — ostrzeżenia meteorologiczne', url: 'https://danepubliczne.imgw.pl/api/data/warningsmeteo', enabled: true, implementation:'OFFICIAL_PUBLIC_WARNINGS_API', integrationNote:'Bieżący oficjalny feed ostrzeżeń. Dokładny komunikat 404 No products were found jest normalizowany do pustej listy; każdy inny błąd pozostaje błędem źródła.'},'STATUS','AUTHORITATIVE_EMPTY_SET'),
  contract({id: 'IMGW_HYDRO', name: 'IMGW-PIB — ostrzeżenia hydrologiczne', url: 'https://danepubliczne.imgw.pl/api/data/warningshydro', enabled: true, implementation:'OFFICIAL_PUBLIC_WARNINGS_API', integrationNote:'Bieżący oficjalny feed ostrzeżeń hydrologicznych; archiwum nie jest używane jako dowód bieżącego stanu.'},'STATUS','AUTHORITATIVE_EMPTY_SET'),
  contract({id: 'PAA', name: 'PAA — komunikaty', url: 'https://www.gov.pl/web/paa/aktualnosci2', enabled: true},'STATUS','NOT_PROVABLE'),
  contract({id: 'PAA_MEASUREMENTS', name: 'PAA — pomiary mocy dawki', url: 'https://monitoring.paa.gov.pl/maps-portal/', enabled: true, implementation:'OFFICIAL_PAA_WFS_GEOJSON', integrationNote:'Bieżące punkty PMS z oficjalnego GeoServera PAA. Pomiary są warstwą informacyjną i nigdy samodzielnie nie tworzą alarmu.'},'REFERENCE','NOT_PROVABLE'),
  contract({id: 'CERT', name: 'CERT Polska — komunikaty bezpieczeństwa', url: 'https://moje.cert.pl/komunikaty/', enabled: true},'CONTEXT','NOT_PROVABLE'),
  contract({id: 'CSIRT_GOV', name: 'CSIRT GOV — ostrzeżenia publiczne', url: 'https://www.csirt.gov.pl/cer/rss', enabled: false, implementation:'RSS_CHANNEL_LIST_EMPTY', integrationNote:'Oficjalna strona usługi RSS działa, ale publiczna lista kanałów jest obecnie pusta. Nie importujemy raportów historycznych jako bieżących ostrzeżeń.'},'CONTEXT','NOT_PROVABLE'),
  contract({id: 'SG', name: 'Straż Graniczna — operacyjne informacje graniczne', url: 'https://www.strazgraniczna.pl/pl/aktualnosci', enabled: true, implementation:'OFFICIAL_NEWS_OPERATIONAL_FILTER', integrationNote:'Publiczna lista RSS KGSG jest pusta. Integracja używa oficjalnych Aktualności z konserwatywnym filtrem zamknięć, ograniczeń, kontroli i utrudnień granicznych.'},'CONTEXT','NOT_PROVABLE'),
  contract({id: 'POLICE', name: 'Policja — istotne zdarzenia', url: 'https://policja.pl/pol/aktualnosci', enabled: true, implementation:'OFFICIAL_RSS_INCIDENT_FILTER', integrationNote:'Oficjalny RSS Aktualności Policji. Importowane są wyłącznie zdarzenia o znaczeniu sytuacyjnym; zwykłe zatrzymania, kradzieże, przemyt, statystyki i materiały PR są odrzucane.'},'CONTEXT','NOT_PROVABLE'),
  contract({id: 'PSP_INCIDENTS', name: 'PSP — istotne zdarzenia', url: 'https://www.gov.pl/web/kgpsp/aktualnosci', enabled: true, implementation:'OFFICIAL_NEWS_INCIDENT_FILTER', integrationNote:'Centralne Aktualności KG PSP na gov.pl z konserwatywnym filtrem zdarzeń. Brak zweryfikowanego krajowego live API/RSS incydentów; lista publikacji nie oznacza pełnego pokrycia.'},'CONTEXT','NOT_PROVABLE'),
  contract({id: 'UA', name: 'UkraineAlarm — oficjalne alarmy Ukrainy', url: 'https://map.ukrainealarm.com/', enabled: false, implementation:'DORMANT_REQUIRES_EXTERNAL_API_KEY', integrationNote:'Adapter pozostaje w backendzie, ale publiczna aplikacja go nie reklamuje i domyślny worker go nie uruchamia do czasu skonfigurowania zweryfikowanego klucza API. Alarmy UA nie wpływają na status Polski.'},'SITUATIONAL','NOT_PROVABLE'),
  contract({id: 'NEPTUN', name: 'NEPTUN — bieżące zagrożenia powietrzne', url: 'https://neptun.in.ua/', enabled: true, implementation:'NEPTUN_PUBLIC_API_V1', integrationNote:'Otwarty feed live. Publicznie przekazujemy wyłącznie zgrubną pozycję (minimum 10 km), bez kursu, prędkości i predykcji ruchu. NEPTUN jest agregatorem informacyjnym i nie zastępuje oficjalnych alarmów.'},'SITUATIONAL','NOT_PROVABLE'),
];

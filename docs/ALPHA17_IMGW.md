# Alpha.17 — IMGW: ostrzeżenia meteorologiczne i hydrologiczne

Etap dodaje dwa niezależne oficjalne źródła IMGW-PIB: `IMGW_METEO` i `IMGW_HYDRO`, oparte odpowiednio o `/api/data/warningsmeteo` i `/api/data/warningshydro`.

Parser nie zgaduje geometrii. TERYT i obszary źródłowe są mapowane do województw, ale `geometry` pozostaje `null`. Stopień 1 mapuje się na NORMAL, 2 na HIGH, 3 na CRITICAL; hydrologiczna susza ze stopniem -1 na NORMAL. Czas ważności pochodzi wyłącznie ze źródła i jest interpretowany w Europe/Warsaw.

HTTP 404 nie oznacza automatycznie braku ostrzeżeń. Wyjątek dotyczy tylko dokładnej odpowiedzi IMGW `{"status":false,"message":"No products were found"}`; każdy inny błąd pozostaje błędem źródła. Nieznany stopień, TERYT, województwo albo błędna data powodują fail-closed.

Warunki IMGW wymagają wskazania źródła i faktu przetworzenia. UI i raport kontraktu używają wymaganych komunikatów:
- „Źródłem pochodzenia danych jest Instytut Meteorologii i Gospodarki Wodnej – Państwowy Instytut Badawczy”.
- „Dane Instytutu Meteorologii i Gospodarki Wodnej – Państwowego Instytutu Badawczego zostały przetworzone”.

Testy kontraktu obejmują hydro, meteo, TERYT, ważność, brak geometrii, dokładny wariant pustej odpowiedzi, fail-closed oraz wpływ aktywnego ostrzeżenia tier 1 na status regionu. `backend/scripts/live-imgw.mjs` wykonuje advisory live check obu endpointów.

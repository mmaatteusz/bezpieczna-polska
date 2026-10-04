# Aktualizacja poprzedniego wydania i zgodność kanałów

Istniejący `android-update-compat.yml` sprawdza PackageManager na dwóch
debug APK tego samego kodu preview na x86_64. Sentinel potwierdza zachowanie
pliku; nie potwierdza odczytu danych przez nowy kod ani rejestracji FCM.

## Warunki testu

Użyć oryginalnego APK udostępnionego użytkownikom (zanotować tag, nazwę assetu
i SHA-256) oraz dokładnego kandydata do publikacji. Nie przebudowywać starego
kodu nowymi zależnościami i nie podpisywać ponownie starego APK.
Sprawdzić rzeczywiste versionCode z APK: wariant arm64 split ma przesunięcie
ABI, więc numer z pubspec nie wystarcza.

W obecnej konfiguracji Gradle preview to `pl.bezpiecznapolska.preview`,
production to `pl.bezpiecznapolska`. Preview → production instaluje osobną
aplikację; nie jest aktualizacją i nie przenosi prywatnych danych automatycznie.
Testować preview → preview oraz production → production osobno. Przenoszenie
ustawień pomiędzy nimi wymaga osobnej, jawnej funkcji eksportu/importu.

Przykład kontroli dwóch oryginalnych APK (Android SDK build-tools w PATH):

```bash
python3 scripts/verify-released-apk-pair.py previous.apk candidate.apk \
  --package pl.bezpiecznapolska \
  --play-signing-sha256 "$PLAY_APP_SIGNING_SHA256"
```

Raport zawiera hashe obu plików, package, versionCode i SHA-256 podpisów.
Brak fingerprintu Play oznacza NOT_CHECKED. PASS dotyczy wyłącznie artefaktów.
Różne podpisy blokują ten konserwatywny check; legalna rotacja klucza wymaga
osobnego testu lineage i obsługiwanych wersji Androida.

## Test na fizycznym Androidzie ARM64

1. Na urządzeniu testowym zainstalować poprzedni publiczny APK. Uruchomić
   aplikację, ustawić miejscowość i region, dodać dwie obserwowane lokalizacje
   z różnymi promieniami, zmienić preferencje push i warstwy mapy. Pobrać region
   offline. Zapisać wartości i zrzuty ekranu jako oczekiwany stan.
2. Włączyć powiadomienia i potwierdzić odebranie kontrolnego push przed
   aktualizacją. W autoryzowanej diagnostyce backendu zanotować installationId
   i subskrypcje; nie zapisywać tokenu FCM ani sekretu zarządzania w raporcie.
3. Zamknąć aplikację i wykonać `adb install -r candidate.apk`. Bez uninstall,
   czyszczenia danych i flagi downgrade. Błąd podpisu/package kończy test.
4. Uruchomić nową aplikację i sprawdzić wszystkie wartości z kroku 1 w UI,
   nie tylko obecność plików. Zweryfikować odczyt pakietu offline po restarcie
   telefonu w trybie samolotowym oraz brak crasha podczas migracji.
5. Przywrócić internet. Potwierdzić ten sam installationId, zachowanie
   preferencji i możliwość aktualizacji subskrypcji (sprawdza dostęp do
   sekretu w secure storage). Token FCM może ulec zmianie: musi być skutecznie
   zarejestrowany na backendzie, bez podwójnej aktywnej subskrypcji.
6. Wysłać kontrolny push do tego urządzenia i potwierdzić odbiór w tle oraz
   otwarcie właściwego komunikatu. Akceptacja przez FCM nie jest dowodem odbioru.

Nie edytować plików aplikacji przez root/run-as, aby zasymulować stare dane.
Produkcyjny APK zwykle nie pozwala na run-as; dane mają powstać w starym UI.

## Google Play i GitHub

W Play Console odczytać SHA-256 **App signing key certificate**, osobno od
**Upload key certificate**. Porównać pierwszy z podpisem APK GitHub oraz
rzeczywistego APK dostarczonego przez Play. Sam podpis AAB kluczem upload
nie potwierdza zgodności APK na telefonie.

Jeżeli Google generuje odmienny klucz app signing, publikować poza sklepem
APK podpisany przez Play pobrany z App Bundle Explorer, albo ustalić wspólny
klucz podpisywania przy konfiguracji Play. Nie obiecywać aktualizacji między
kanałami bez zgodnego package, podpisu/lineage i większego versionCode.

Test sklepu wykonać na normalnym torze internal/closed testing, następnie
sprawdzić aktualizację GitHub → Play i Play → GitHub, każdorazowo do wyższego
versionCode. Internal App Sharing może używać osobnego certyfikatu i nie
stanowi dowodu zgodności z wydaniem sklepowym.

Raport wydania: oba tagi i hashe APK, model/ABI/API urządzenia, package,
versionCode, podpisy, wynik instalacji, porównanie ustawień, offline po
restarcie, ciągłość installationId, odbiór push i otwarcie alertu. Każda
niewykonana część ma status NOT_TESTED, a nie PASS.

Źródła: https://developer.android.com/studio/publish/app-signing
oraz https://support.google.com/googleplay/android-developer/answer/9842756.

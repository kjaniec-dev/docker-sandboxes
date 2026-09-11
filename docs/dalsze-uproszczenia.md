# Dalsze uproszczenia sandboxów — do omówienia

Notatka z rozmowy 10 września 2026. To propozycje do przejrzenia jutro,
nie zatwierdzony plan wdrożenia.

Aktualizacja 11 września: zakres zatwierdzony do realizacji. Poniżej pozostaje
oryginalna notatka; wyniki wykonania są w ostatniej sekcji.

## Cel

Ułatwić utrzymanie pięciu harnessów i ograniczyć miejsce zajmowane przez
sandboxy. Sama mniejsza liczba plików nie jest celem: zmiana ma usuwać
powieloną pracę lub realnie zmniejszać obrazy.

## Co już zrobiono

Zmiany są w [PR #4](https://github.com/kjaniec-dev/docker-sandboxes/pull/4),
w tym commit `34b6b53`.

- Wspólny launcher tworzy brakujące instancje przez `sbx create`, a do
  istniejących dołącza przez `sbx run --name`.
- Usunięto generowanie `sbxenv.yaml` i interpolację argumentów środowiska.
- Bootstrap działa przy tworzeniu przez natywne `setup.install`, bez markerów
  i ponawiania instalacji przy każdym dołączeniu.
- Superpowers, przypięty Caveman i Playwright korzystają ze wspólnego magazynu
  skillsów. Aktualizacje obsługuje `bin/sbx-skills --update`.
- Dodano minimalny `.dockerignore` oraz czyszczenie cache Go, uv i npm
  podczas budowania obrazów.
- Naprawiono odczyt wersji Javy przy komunikatach proxy `JAVA_TOOL_OPTIONS`.

Cały PR względem ówczesnego `main`: 6 plików usuniętych, 9 dodanych,
317 linii mniej. To przede wszystkim usunięcie duplikacji, a nie maksymalne
odchudzenie struktury katalogów.

Testy hostowe i weryfikacja wewnątrz Codex przeszły. Sprawdzono również
tworzenie, ponowne dołączanie i rzeczywistą odpowiedź modelu po zatwierdzeniu
bindingu istniejącego OAuth OpenAI. Pozostałe agenty nie miały pełnego testu
uruchomienia. Obrazów nie przebudowano dla zmian czyszczących cache;
oszczędność miejsca pozostaje niezmierzona.

## Co warto zrobić dalej

### 1. Połączyć wspólną weryfikację narzędzi

Wyciągnąć powtarzające się sprawdzenia z pięciu `verify.sh` do wspólnego
skryptu. Dotyczy to m.in. Node, Go, Javy, Maven, Gradle i wspólnych komend.
Przy harnessach zostawić sprawdzanie konkretnego agenta, jego MCP, pluginów
i ścieżek odkrywania skillsów.

Korzyść: poprawka sposobu sprawdzania narzędzia powstaje raz i obejmuje
wszystkich agentów. Zmniejsza to ryzyko rozjazdów, takich jak ostatni problem
z Javą. Samo wydzielenie wspólnego skryptu nie gwarantuje mniejszej liczby
plików — powinno przede wszystkim ograniczyć powielony kod.

### 2. Ocenić pozostałe duplikaty konfiguracji

Sprawdzić, które ustawienia są rzeczywiście wspólne, a które różnią się
między agentami. Współdzielić tylko te pierwsze. Nie zastępować czytelnych
plików jednym dużym skryptem z wyjątkami dla każdego agenta.

### 3. Zmierzyć i zmniejszyć obrazy

Zapisać rozmiar wybranego obrazu przed zmianą, przebudować go z czyszczeniem
cache, porównać rozmiar i uruchomić weryfikację w odtworzonym sandboxie.
Sprawdzić także dostępność Playwright i przeglądarki po czyszczeniu.

Osobno ocenić miejsce zajmowane przez stare obrazy, archiwa `.build` i stare
instancje. Porządki w tych zasobach są oddzielną decyzją od refaktoryzacji
skryptów. Mniejszy kontekst budowania nie oznacza automatycznie mniejszego
obrazu wynikowego.

## Co zostawić na razie

- Osobne kity i bootstrapy: agenty mają różne integracje i uwierzytelnianie.
- Wygodne komendy `codex-sbx`, `claude-sbx` itd.
- Małe wrappery, jeśli ich jedyną wadą jest liczba plików. Ich usunięcie nie
  daje istotnej oszczędności miejsca ani czasu startu.
- Obecny zestaw narzędzi, dopóki nie zdecydujemy świadomie, które są zbędne.

## Kolejność do rozważenia jutro

1. Zdecydować, czy ważniejsze jest teraz utrzymanie kodu, czy miejsce na dysku.
2. Dla utrzymania: zacząć od wspólnej weryfikacji narzędzi.
3. Dla miejsca: przebudować jeden obraz i zmierzyć efekt czyszczenia cache.
4. Dopiero po wynikach zdecydować o dalszym scalaniu plików i usuwaniu zasobów.

Codzienne używanie powinno pozostać takie samo: wpisujemy `codex-sbx`
i pracujemy. Główna korzyść refaktoryzacji to prostsze aktualizacje i mniej
miejsc wymagających tej samej poprawki.

## Realizacja — 11 września 2026

- Wspólne sprawdzanie komend i wersji trafiło do
  `shared/verify-toolchain.sh`; pięć skryptów harnessów zachowuje sprawdzanie
  swoich agentów, integracji i skillsów.
- Przegląd kitów: wspólna lista domen narzędziowych i instrukcje worktree
  są powielone, ale uprawnienia dostawców, dziedziczenie agentów, entrypointy
  i bootstrapy różnią się. Pozostają jawne kity, bez generatora i nowego
  mechanizmu składania konfiguracji. Wspólna instalacja narzędzi i lifecycle
  są już wydzielone; dalsze scalanie małych Dockerfile i wrapperów nie daje
  istotnego uproszczenia.
- Test obrazu Codex wykazał, że Chromium było instalowane w cache roota,
  podczas gdy agent szukał go w swoim katalogu. Instalator systemowy teraz
  instaluje tylko zależności przeglądarki; instalator użytkownika instaluje
  Chromium przez tę samą wersję Playwright, której używa globalne CLI.
- `make verify-browser` uruchamia Chromium jako bieżący użytkownik, tworzy
  lokalną stronę i klika przycisk. Nie pobiera pakietów ani nie używa sieci.
- Wyjściowy obraz Codex: `bd4a8d26423c`, odczyt Docker `.Size`
  **1 784 259 425 B**, odczyt sbx template `.size` **2 070 842 554 B**.
  To różne miary; porównanie przed/po musi korzystać z tego samego narzędzia.
  Wczorajsze obrazy zawierają już czyszczenie Go i uv, więc dzisiejszy wynik
  nie mierzy pierwotnej oszczędności z ich usunięcia.
- Archiwa `.build` zajmowały **9,7 GiB** przed przebudową. Nie usuwano
  archiwów, starych obrazów ani istniejących sandboxów w ramach porządków.
  Rebuild standardowo zastępuje archiwum i zarejestrowany szablon Codex.

Przebudowano i załadowano `codex-sbx:local` (`d82c9231e125`). Docker `.Size`
wynosi teraz **1 780 595 010 B**: mniej o **3 664 415 B**, czyli **0,205%**.
`sbx template ls --json` podaje **1 780 597 403 B**; spadek tej metryki jest
znacznie większy niż w Docker, dlatego nie traktujemy go jako zmierzonej
oszczędności cache. Build używa też zależności `latest`, więc wynik całej
przebudowy nie izoluje wpływu jednej operacji czyszczenia. Cache odziedziczony
z obrazu bazowego może nadal zajmować miejsce w niższych warstwach.

Weryfikacja:

- `SBX_TEST_CLI=sbx make test` przeszedł w całości, łącznie z regresjami
  brakujących komend, niewłaściwych wersji, błędów narzędzi i source guardów.
- Test Chromium nie przechodził na starym obrazie (brak pliku wykonywalnego
  w cache agenta), a przeszedł na przebudowanym obrazie.
- Świeży sandbox Codex utworzony z pełnego kitu przeszedł bootstrap,
  weryfikację wspólnego toolchainu i skillsów oraz test Chromium.
- ShellCheck dla zmienionych skryptów przeszedł z `-x -P SCRIPTDIR -e SC2317`
  (wyłączenie istniejących ostrzeżeń o kodzie za guardami source).
  `shfmt -d -i 2` przeszedł.
- Walidacja pięciu kitów przez rzeczywiste `sbx` przeszła.
- Testowy sandbox usunięto po udanej weryfikacji.

Zmiany wspólnego verifiera są dostępne dla istniejących sandboxów przez
montowany checkout. Poprawka instalacji Chromium wymaga przebudowy pozostałych
czterech obrazów oraz odtworzenia używanych sandboxów. W ramach tego pomiaru
przebudowano tylko Codex; istniejących sandboxów użytkownika nie odtwarzano.

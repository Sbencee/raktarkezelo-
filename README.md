# Raktár Cloud – Vállalati Készletirányítási és Bizonylatoló Rendszer

A **Raktár Cloud** egy kritikus üzleti folyamatokat támogató  vállalatirányítási modul, amely a fizikai eszközpark digitális transzformációját valósítja meg Flutter és Firebase technológiák segítségével.

## Főbb funkciók és Mérnöki Megoldások

* **Hardver-szoftver Integráció (Computer Vision):** Az eszközök azonosítása nem manuális bevitelre épül, hanem a telefon kameráját használó **élő vonalkód- és QR-kód feldolgozó motorra**.
* **Intelligens Készletmozgási Logika:**
    * **Tranzakció-kezelés:** A bevételezés és kiadás során a rendszer atomi módon frissíti a készletet, rögzíti a mozgást a naplóban és archiválja a bizonylat-adatokat.
    **Tömeges SN Parser:** Beépített algoritmus, amely képes nyers szöveges listákból (pl. Excel export) automatikusan kinyerni és validálni az egyedi gyári számokat.
* **Dinamikus PDF Dokumentum-motor:** Alacsony szintű grafikus rajzolás segítségével az alkalmazás **natív, nyomtatható PDF bizonylatokat** generál a memóriában:
    * *Belső Kiadási Bizonylat* (QR-kóddal ellátott hitelesítő dokumentum)
    * *Átvételi Nyilatkozat* (Személyi felelősségvállaláshoz, jogi záradékkal)
    * *Bevételi Bizonylat* (Zöld jelzésű, beérkező áru dokumentáció)
* **Vezetői Analytics & Leltár:** Teljes raktárvagyon-összesítés PDF-ben, amely tartalmazza:
    ** Kategóriánkénti sávdiagramos vizualizációt.
    **Pénzügyi modul:** Automatikus teljes készletérték számítás (Ft).
    * **Prediktív hiányjelzés:** [HIÁNY] riasztás a minLimit alá eső kritikus eszközöknél.
* **Hibrid Adatkezelés:** Valós idejű NoSQL szinkronizáció (Firestore) és dokumentum-alapú archiválás.

## Technológiák és Architektúra

* **Flutter (Dart)** — Reaktív, keresztplatformos keretrendszer.
* **Firebase Ecosystem** — Firestore (adatbázis) és Auth (biztonság).
* **OS-szintű Fájlkezelés** — Natív fájlrendszer-elérés (File Saver/Path Provider), amely áthidalja a Web és Android közötti különbségeket.
* **PDF/Printing Engine** — Bináris dokumentum-előállítás.
* **RegExp & Data Parsing** — Algoritmikus karakterlánc-feldolgozás a tömeges adatbevitelhez.

## Fejlesztési módszertan — AI-Driven Development (Gemini 1.5 Pro)

Az alkalmazás **AI-vezérelt szoftverfejlesztési ciklusban** készült, ahol az AI nemcsak kódgenerátor, hanem architektúra-tervező és minőségbiztosítási eszköz is volt.

1.  **Iteratív Funkciófejlesztés:** A modulok (pl. vonalkód-olvasó, PDF motor) izolált fejlesztése után az AI segített az operációs rendszer szintű fájlkezelési korlátok (Scoped Storage) feloldásában.
2.  **Algoritmus Optimalizálás:** A PDF generálás során felmerülő karakterkódolási kihívások (ő/ű kezelés) és a reszponzív UI elrendezések finomhangolása AI-asszisztenciával történt.
3.  **Üzleti Logika Validálása:** A készletkezelési algoritmusok tesztelése és a tranzakcionális biztonság (pl. ne lehessen több árut kiadni, mint amennyi van) AI-vezérelt kód-analízissel lett biztosítva.

## Futtatási útmutató

1.  Klónozd a tárolót: `git clone https://github.com/Sbencee/raktarkezelo-.git`
2.  Frissítsd a csomagokat: `flutter pub get`
3.  Konfiguráld a Firebase kapcsolatot: `flutterfire configure`
4.  Futtatás: `flutter run`

---
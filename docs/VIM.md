# Vim-näppäimet — suunnitelma

Tila: **luonnos katselmointia varten** · 2026-11-27 · haara `vim-spec`

Natiivi, Vimium-tasoinen näppäimistöohjaus koko selaimeen: verkkosivuille ja
selaimen omiin näkymiin (asetukset, historia, lataukset, kirjanmerkit,
välilehtilista, ⌘K, osoitekenttä, popoverit ja dialogit). Ominaisuus on
kytkimen takana ja oletuksena pois päältä.

## 1. Miksi natiivi eikä Vimium-laajennus

Vimium toimii Searchissa laajennuksena (upstream ROADMAP: *"Vim mode — Vimium
works"*), mutta vain sivun sisällä. Asetuksiin, paneeleihin, välilehtilistaan
ja dialogeihin laajennus ei ylety. Se on tämän työn ydin.

Upstreamin vastaava yritys [driceroland/Search#160](https://github.com/driceroland/Search/pull/160)
suljettiin kolmesta syystä. Suunnitelma välttää ne kaikki:

| #160:n ongelma | Tässä suunnitelmassa |
|---|---|
| Skriptit injektoitiin jokaiselle sivulle ja kehykseen, myös kun ominaisuus oli pois päältä | Käyttäjäskriptejä ei ole lainkaan. Näppäimet luetaan Swiftissä. Sivulle ajetaan koodia vain komennon hetkellä (`evaluateInSearch` / `callInSearch`). Kun ominaisuus on pois, sen hinta on yksi `if`. |
| Vaati macOS 27 SDK:n (suljetut shadow rootit) | Ei uusia SDK-vaatimuksia. Suljetut shadow rootit jäävät v1:n ulkopuolelle. |
| Vimium hoitaa jo saman | Natiivit näkymät hoitaa vain natiivi toteutus. |

Koodi on MIT-lisensoitua, joten #160:n `Vim.swift` (haara `upstream-pr-160`
paikallisesti) kelpaa lähteeksi esimerkiksi vihjeiden suodatukseen ja
kehysten käsittelyyn. Sen arkkitehtuuria (näppäimet JS:ssä) ei kopioida.

## 2. Haastattelun päätökset

| Kysymys | Päätös |
|---|---|
| Missä toimii | Sivut, Asetukset, historia/lataukset/kirjanmerkit, välilehtilista ja ⌘K, dialogit ja popoverit |
| Näppäimistöasettelu | **Kirjoitetun merkin mukaan.** Suomalaisella näppäimistöllä `/` on ⇧7 ja `[` on ⌥8, kuten Vimiumissa. |
| Oletus | Kytkin Settings › Keyboard & Mouse, **oletuksena pois** |
| Tilan näyttö | Pieni merkki ikkunan alakulmassa, vain kun tila ei ole normal |
| Komennot v1 | Perus + Avaaminen (taulukko kohdassa 5). Visual/caret, merkit, `[[ ]]` ja numerotoisto tulevat myöhemmin. |
| Muokattavuus | Tekstikenttä asetuksissa: `map` / `unmap` / `unmapAll` |
| Sivun omat pikanäppäimet | **Vim voittaa aina.** Sivun näppäimet saa käyttöön `i`-tilassa. Sivustokohtaista poissulkulistaa ei tehdä. |
| Vihjemerkit | `sadfjklewcmpgh` (Vimiumin oletus), vaihdettavissa asetuksissa |
| Insert-tila | Alkaa automaattisesti, kun tekstikenttä saa fokuksen. Esc poistuu kentästä. |
| Ehdotuslistat | ⌃J/⌃K ja ⌃N/⌃P liikuttavat valintaa |
| Korostus natiivissa | Oma aksenttiväriin perustuva korostus, ei järjestelmän fokusrengasta |
| Eteneminen | Tämä spec, sen jälkeen vaiheittaiset PR:t (kohta 9) |

**Poikkeama haastattelusta:** näppäinkartoitusten iCloud-synkkaa ei tehdä v1:ssä.
Search synkkaa vain `SharedSettings`-joukon (ICloudSync.swift:96), joka on
yhteinen sopimus iOS-sovelluksen kanssa (SYNC.md). Uusi avain vaatisi
muutoksen molempiin repoihin. Kartoitus tallennetaan paikallisesti
`Store.settings`iin samaan tapaan kuin `ShortcutStore`.

## 3. Tilat

```
            i                         f / F
 INSERT ◀──────── NORMAL ────────────────────▶ HINT
 (pass)  ──Esc──▶   ▲  ▲ ──── Esc / valinta ◀────┘
                    │  │
  kenttä saa fokuksen│  └── Esc (blur)
                    ▼
                 TYPING   (automaattinen insert: tekstikenttä fokuksessa)
```

- **NORMAL**: kartoitetut näppäimet ovat Vimin. Kartoittamattomat menevät
  sivulle tai näkymälle sellaisinaan.
- **TYPING**: tekstikenttä on fokuksessa (`ContentView.caretIn()` /
  `Tab.typing`). Kaikki menee kenttään. Esc poistaa fokuksen (sivulla
  `document.activeElement.blur()`, natiivissa `makeFirstResponder(nil)`) ja
  palauttaa NORMALiin. Ehdotuslistoissa ⌃J/⌃K/⌃N/⌃P toimivat tässäkin tilassa.
- **INSERT** (`i`): kaikki näppäimet menevät sivulle Esciin asti. Näin
  Gmailin ja GitHubin omat pikanäppäimet saa käyttöön.
- **HINT**: vihjeet näkyvät. Kirjaimet suodattavat, Esc peruu ja ⌫ poistaa
  viimeisen merkin.
- **Haku** (`/`) käyttää olemassa olevaa FindBaria (`browser.openFind()`),
  joten omaa tilaa ei tarvita.

⌘-yhdistelmiin ei kosketa missään tilassa. Kaikki nykyiset pikanäppäimet
toimivat kuten ennenkin.

Tilamerkki (`-- INSERT --`, `-- HINT --`, kesken oleva sarja kuten `g`) on
pieni SwiftUI-overlay ikkunan oikeassa alakulmassa. NORMALissa se ei näy.

## 4. Arkkitehtuuri

### 4.1 Yksi koukku, ei uusia monitoreja

Kaikki selainikkunan näppäimet kulkevat jo `ContentView.take(_:)`:n kautta
(App.swift:1933) ennen WebKitiä, SwiftUI:ta ja valikkoja. Koukku lisätään sinne,
modaalien ja sheettien ohituksen jälkeen ja ennen ⌘-switchiä:

```swift
if prefs.vimKeys, let handled = vim.take(event, surface: vimSurface()), handled { return nil }
```

Kun `prefs.vimKeys` on pois, mitään muuta ei ajeta. Erillisillä
monitoreilla on omat koukkunsa:
`Little.swift:256` (pienet ikkunat), `Launcher.swift:242` ja
`LinkChooserPanel.swift:225`. Niihin lisätään sama yksirivinen kutsu.

### 4.2 Uudet tiedostot

| Tiedosto | Vastuu |
|---|---|
| `Vim.swift` | `VimKeys`: tila, sarjapuskuri (`gg`, `yy`, `gt`), aikakatkaisu, kartoitustaulu, komentojen ajo. Puhdas logiikka, joten se on yksikkötestattava ilman ikkunoita. |
| `VimMap.swift` | Kartoitustiedoston jäsennys (`map`/`unmap`/`unmapAll`, kommentit `"` ja `#`), Vimiumin komentonimet ↔ omat toiminnot, virheet rivinumeroineen |
| `VimPage.swift` | Sivulla ajettavat skriptit: vieritys, vihjeet, `gi`. Ajetaan pyydettäessä `Web.world`issa. |
| `VimSurface.swift` | Natiivien näkymien protokolla ja SwiftUI-korostusmodifieri (4.5) |
| `VimBadge.swift` | Tilamerkki ja `?`-ohjeikkuna |

Olemassa oleviin tiedostoihin tulee vain kytkentöjä: koukku `take()`:ssa,
`Preferences.vimKeys`, asetusrivit ja `VimList`-kytkennät paneeleihin.
Näin upstreamin muutokset on helppo yhdistää forkkiin.

### 4.3 Näppäimen lukeminen

- Näppäin on `event.characters` eli asettelun tuottama merkki. Siihen sisältyvät
  ⇧ ja ⌥, joten suomalaisella näppäimistöllä ⇧7 → `/` ja ⌥8 → `[`.
- Jos ⌘ on pohjassa, Vim ohittaa tapahtuman aina.
- ⌃ + kirjain luetaan `KeyCombo`n kautta, eli `<c-j>`.
- Erikoisnäppäimet saavat nimen keyCodesta (`<esc>`, `<cr>`, `<space>`,
  `<bs>`, `<tab>`), kuten `KeyCombo` jo tekee (Shortcuts.swift:45).
- Kuolleet näppäimet (`¨`, `´`, `^`) odottavat yhdistelmää. `^` saadaan
  vasta toisella painalluksella. Tämä hyväksytään, ja käyttäjä voi
  kartoittaa toisen näppäimen.
- Ei-latinalaiset asettelut (venäjä, heprea) eivät kuulu v1:een.
  `KeyLayout` ei käännä muuntimettomia näppäimiä (KeyLayout.swift:97). Myöhemmin
  `KeyLayout`iin voi lisätä plain-version.

### 4.4 Sivut

Sivulle ei injektoida mitään pysyvää. Jokainen komento on yksi kutsu:

- **Vieritys** (`j k h l d u gg G`): `callInSearch` ajaa pienen funktion, joka
  vierittää aktiivista vieritettävää elementtiä (lähimmän
  fokusoidun/klikatun vieritettävän esivanhemman, muuten suurimman näkyvän
  vieritettävän elementin, muuten ikkunan). Pohjana on `PageScripts.scroll`
  (PageHands.swift:386). Pidetty `j` toistuu `isARepeat`-tapahtumina, ja
  vieritys on sileää (`behavior: 'smooth'` vain ensimmäisellä painalluksella).
- **Vihjeet** (`f F`): yksi kutsu kerää ehdokkaat (`PageScripts.helpers`:n
  `SEL` + `visible()`) ja piirtää merkit suljettuun shadow rootiin samalla
  z-indeksillä kuin ⇧⌘H-tila (Curtain.swift:425). Swift pitää vihjetilan, ja
  jokainen kirjain on yksi `callInSearch('filter', …)`. Valinta klikataan
  oikealla hiirellä `PageHands.click`illä (PageHands.swift:409), jotta
  sivu näkee aidon klikkauksen ja zoom toimii. `F` avaa linkin taustavälilehteen
  `href`in kautta. Kehykset: pääkehys ja saman alkuperän iframet v1:ssä,
  ristialkuperäiset myöhemmin (#160:n kehyskoodi on mallina).
- **`gi`**: fokusoi ensimmäisen näkyvän kirjoitettavan kentän. `Forms.swift`in
  `focusin` vaihtaa tilan TYPINGiin itsestään.
- **Insert-tunnistus**: `Tab.typing` (Forms.swift:56) on jo olemassa, eikä se
  vaadi uutta skriptiä.
- Sivut, joilla `Web.world`-skriptit eivät toimi (PDF, laajennussivut):
  vieritys tehdään natiivisti vierityspyörätapahtumilla ja vihjeet
  ohitetaan.

### 4.5 Natiivit näkymät

Asetukset, historia, lataukset ja kirjanmerkit ovat välilehtiä pääikkunassa
(InternalPages.swift). Kaikki ovat SwiftUI:n `ScrollView` + `LazyVStack`,
eikä niissä ole valintatilaa. Siksi tehdään yksi yhteinen malli:

```swift
@MainActor protocol VimList: AnyObject {
    var vimRows: [AnyHashable] { get }        // näkyvät rivit järjestyksessä
    var vimSelected: AnyHashable? { get set } // korostettu rivi
    func vimActivate(_ row: AnyHashable, background: Bool) // Enter / o / O
    func vimAction(_ key: String, on row: AnyHashable) -> Bool // dd, yy, x, p …
    func vimFind()                            // /
    func vimSection(_ step: Int) -> Bool      // h / l, jos näkymällä on osioita
}
```

Rivit merkitään modifierilla `.vimRow(id, in: list)`. Se piirtää korostuksen
(aksenttivärin tausta ja reunus, sama tyyli molemmissa teemoissa) ja vierittää
rivin näkyviin `ScrollViewReader`illa. `VimKeys` kysyy `vimSurface()`:lta,
mikä näkymä on päällimmäisenä, tässä järjestyksessä: dialogi/sheet → popover
→ ⌘K / osoitekenttä → välilehtilista (jos fokuksessa) → sisäinen sivu → verkkosivu.

| Näkymä | Näppäimet |
|---|---|
| **Asetukset** | `j/k` rivi, `h/l` osio, `gg/G`, `/` hakukenttä (nykyinen ⌘F), `<cr>`/`<space>` vaihtaa kytkimen tai avaa valinnan, `Esc` poistaa valinnan |
| **Historia, lataukset, kirjanmerkit** | `j/k`, `gg/G`, `/` suodatus, `<cr>` avaa, `O` avaa uuteen välilehteen, `yy` kopioi osoitteen, `dd` poistaa (kirjanmerkeissä vahvistus), `h/l` sulkee/avaa kansion (kirjanmerkit) |
| **Välilehtilista** (sivupalkki tai ylärivi) | `gs` siirtää fokuksen listaan, sitten `j/k`, `<cr>` valitsee, `x` sulkee, `p` kiinnittää/irrottaa, `Esc` palaa sivulle |
| **⌘K ja osoitekenttä** | ⌃J/⌃K/⌃N/⌃P → `browser.walk(±1)`, kirjaimet kirjoittuvat normaalisti |
| **Välilehtivaihdin (⌃Tab)** | `j/k` siirtää `selectedID`:tä (`TabSwitcher.move`) |
| **Popoverit** (sivustokortti, lataukset) | `j/k` rivit, `<cr>`/`<space>` aktivoi, `Esc` sulkee. Sivustokortti (`SiteCardPanel`) ei koskaan ota näppäimistöä (SiteCard.swift:323), joten näppäimet välitetään sille pääikkunan koukusta, kun kortti on auki. |
| **Dialogit** (NSAlert, sheetit) | `h/l` tai `j/k` siirtää oletuspainiketta, `<cr>` hyväksyy, `Esc` peruu. Sheetit ohitetaan nykyään (App.swift:1937), joten niille tulee oma pieni haara. |

## 5. Komennot (v1)

Nimet ovat Vimiumin, jotta Vimium-konfiguraation `map`-rivit voi liittää
sellaisinaan.

**Perus**

| Näppäin | Vimium-komento | Toteutus |
|---|---|---|
| `j` `k` | scrollDown / scrollUp | VimPage scroll, 60 pt |
| `h` `l` | scrollLeft / scrollRight | VimPage scroll |
| `d` `u` | scrollPageDown / scrollPageUp | puoli näkymää |
| `gg` `G` | scrollToTop / scrollToBottom | |
| `f` `F` | LinkHints.activateMode / activateModeToOpenInNewTab | VimPage hints |
| `K` `gt` | nextTab | `browser.step(1)` |
| `J` `gT` | previousTab | `browser.step(-1)` |
| `g0` `g$` | firstTab / lastTab | `browser.select(index:)` |
| `x` | removeTab | `browser.closeFront()` |
| `X` | restoreTab | `browser.reopen()` |
| `t` | createTab | `browser.launch()` |
| `yt` | duplicateTab | `browser.duplicate()` |
| `H` `L` | goBack / goForward | `browser.back()` / `forward()` |
| `r` | reload | `browser.reload()` |
| `/` | enterFindMode | `browser.openFind()` |
| `n` `N` | performFind / performBackwardsFind | `browser.look(forward:)` |
| `yy` | copyCurrentUrl | `browser.copyAddress()` |
| `gi` | focusInput | VimPage |
| `i` | enterInsertMode | INSERT |
| `?` | showHelp | VimBadge: nykyinen kartoitus ryhmiteltynä |
| `gs` | *(oma)* focusTabList | välilehtilistan fokus |

**Avaaminen**

| Näppäin | Vimium-komento | Toteutus |
|---|---|---|
| `o` | Vomnibar.activate | `browser.edit()` (⌘L) |
| `O` | Vomnibar.activateInNewTab | `browser.launch()` + kenttä |
| `b` `B` | Vomnibar.activateBookmarks(InNewTab) | osoitekenttä kirjanmerkkirajauksella |
| `T` | Vomnibar.activateTabSelection | `browser.searchTabsKey()` (⌘K) |
| `ge` `gE` | Vomnibar.activateEditUrl(InNewTab) | kenttä esitäytettynä nykyisellä osoitteella |

Sarjan aikakatkaisu on 1 s. `g` jää tilamerkkiin näkyviin, kunnes sarja
valmistuu tai aikakatkaisu umpeutuu.

## 6. Asetukset

Settings › Keyboard & Mouse, uusi ryhmä **Vim keys**:

- **Vim keys** – kytkin, oletus pois (`Preferences.vimKeys`)
- **Link hint characters** – tekstikenttä, oletus `sadfjklewcmpgh` (näkyy vain kun kytkin on päällä)
- **Custom key mappings** – monirivinen kenttä, virheet rivinumeroineen kentän alla
  ```
  " Vimium-yhteensopiva
  map <c-d> scrollPageDown
  unmap x
  ```
- **Show all keys** – avaa `?`-ohjeen

Jokaisesta rivistä tehdään `SettingsItem` (SettingsIndex.swift), jotta asetusten
haku löytää ne. Lisäksi CHANGELOG-rivi kohtaan Unreleased.

## 7. Testaus

- **Yksikkötestit** (`Tests/SearchTests/VimTests.swift`, `swift test`): sarjat ja
  aikakatkaisu, tilasiirtymät, kartoitusjäsennin (virheet ja `unmapAll`),
  suomalaisen asettelun merkit (`/` ⇧7:stä, `[` ⌥8:sta) synteettisillä
  `NSEvent`eillä.
- **Probe-testit** (`Tests/vim_*.py`, ajetaan buildatulla sovelluksella kuten
  muutkin): pois päältä mitään ei tapahdu; vieritys; vihjeet ja valinta;
  välilehtikomennot; insert-tila kentässä ja Esc; ⌘-näppäimet koskemattomia;
  asetusten j/k; historian `dd`.
- Käsin: Gmail, GitHub, YouTube, Google Docs (contenteditable), PDF ja jaettu
  näkymä (komennot menevät korostettuun ruutuun).

## 8. Riskit ja avoimet kysymykset

1. **Upstream ei ota tätä vastaan** (ROADMAP: not planned). Työ jää forkkiin.
   Muutokset pidetään omissa tiedostoissaan, jotta `git merge upstream/main`
   pysyy kivuttomana.
2. **`gs` välilehtilistan fokukselle** on oma keksintö, koska Vimiumissa vastaavaa ei ole.
   Vaihtoehto on `T` (⌘K) ainoana tapana valita välilehti näppäimistöllä.
3. **SwiftUI-korostus ilman oikeaa fokusta** ei näy VoiceOverille. Se on
   hyväksytty valinta, mutta `accessibilityAddTraits(.isSelected)` lisätään silti.
4. **Ristialkuperäiset iframet ja suljetut shadow rootit** puuttuvat v1:n vihjeistä.
5. **Vim voittaa aina:** Gmailissa `j/k` vierittää eikä liiku viestilistassa,
   ellei käyttäjä paina `i`. Jos tämä alkaa haitata, sivustokohtainen
   poissulku on helppo lisätä myöhemmin.
6. **Sivustokortti ei ota näppäimistöä.** Näppäinten välitys pääikkunasta
   on varmistettava käytännössä ennen vaihetta 7.

## 9. Vaiheet

Jokainen vaihe on oma PR `dmuko/Vieb`iin, ja jokainen jättää sovelluksen
toimivaksi kytkin pois päältä.

| # | PR | Sisältö |
|---|---|---|
| 1 | Spec | Tämä dokumentti |
| 2 | Ydin | `Vim.swift`, koukku `take()`:ssa, kytkin, tilamerkki, vieritys, välilehti-, historia- ja hakukomennot, `yy`, `r`, `i`/Esc, `?`. Yksikkö- ja probe-testit. |
| 3 | Vihjeet | `f` `F` `gi`, vihjemerkkiasetus |
| 4 | Avaaminen | `o O b B T ge gE`, ⌃J/⌃K/⌃N/⌃P ehdotuslistoissa |
| 5 | Natiivikehys + Asetukset | `VimList`, `.vimRow`, Settings-sivu |
| 6 | Paneelit | Historia, lataukset, kirjanmerkit |
| 7 | Välilehdet ja popoverit | `gs`, välilehtilista, ⌃Tab-vaihdin, sivustokortti, latauskelluke, dialogit |
| 8 | Kartoitukset | `map`/`unmap`-kenttä, Vimium-nimet |

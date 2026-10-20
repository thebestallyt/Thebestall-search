# Event-Bot (Discord)

Ein Discord-Bot für **alle Arten von Events**: Video-Contests, Einsendungs-Contests mit Voting, Giveaways,
Anmeldungen für Turniere – oder komplett eigene Events. Fast alles lässt sich direkt in Discord über ein
**Setup-Menü mit Knöpfen** einstellen. Alle Texte im Bot sind auf **Englisch**.

## Event-Typen (Vorlagen)

| Typ | Wofür | Standard |
|---|---|---|
| 🎥 **Video views contest** | Wer hat die meisten Aufrufe auf YouTube/TikTok? | Formular: Kanalname, Kanal-Link, Video-Links · Hashtag-Pflicht · Rangliste nach Aufrufen |
| 🎨 **Submission contest** | Builds, Art, Clips, Screenshots … | Formular: Link + Notiz · optional **Voting** (während oder nach der Deadline) |
| 🎁 **Giveaway** | Gewinnspiel | kein Formular, ein Klick zum Mitmachen · **zufällige Auslosung** |
| 📋 **Sign-up** | Turniere, Treffen, Tryouts | Formular: Roblox-Name · **begrenzte Plätze** · keine Gewinner |
| ⚙️ **Custom event** | alles andere | frei einstellbar |

Die Vorlage ist nur der Startpunkt – jede Einstellung kann danach geändert werden.

## So erstellst du ein Event

1. `/event create type:…` → es öffnet sich (nur für dich sichtbar) das **Setup-Menü**.
2. Einstellungen anpassen (siehe unten), mit **👁️ Preview** anschauen.
3. **🚀 Publish** → das Event wird im gewählten Kanal gepostet (sofort oder zur geplanten Startzeit).
4. Mitglieder klicken auf den Knopf (z. B. **Join**), füllen das Formular aus – fertig.
5. Am Ende beendet der Bot das Event **automatisch**, postet die Ergebnisse und ermittelt die Gewinner
   (oder zeigt dem Staff ein Auswahlmenü).

### Was man im Setup-Menü einstellen kann

| Knopf | Einstellungen |
|---|---|
| 📝 **Text & look** | Titel, Beschreibung/Regeln, Preis, Bild (URL), Farbe |
| ⏰ **Time & limits** | Start (sofort, z. B. `2h` später oder Datum `2026-10-31 18:00`), Ende (Dauer wie `10d` oder Datum), max. Teilnehmer, Erinnerungen vor dem Ende (z. B. `24, 1` Stunden) |
| 🧾 **Join form** | bis zu **5 eigene Fragen** – Typ: Text, langer Text, Link, Zahl (bei Video-Contests auch Kanal-Link und Video-Links), Pflicht ja/nein. Keine Fragen = ein Klick zum Mitmachen |
| 📢 **Channels & roles** | Event-Kanal, Ergebnis-Kanal (z. B. Staff-Kanal), Rolle zum Pingen, **Rolle die man zum Mitmachen braucht** |
| 🏆 **Winners & results** | Gewinner-Modus (keine / Staff wählt / Zufall / meiste Votes / meiste Views), Anzahl Gewinner, Format der Teilnehmerliste, Text auf dem Join-Knopf, Teilnehmerliste öffentlich ja/nein, Austreten/Bearbeiten erlaubt ja/nein |
| 🎥 **Video settings** | Pflicht-Hashtag (leer = jedes Video), YouTube/TikTok, nur Videos nach dem Start |
| 🗳️ **Voting** | aus / während des Events / nach der Deadline (+ Dauer), für sich selbst voten ja/nein |

**Listen-Format:** Platzhalter `{user}` (Erwähnung), `{username}` und die Schlüssel deiner Fragen, die im Menü
angezeigt werden, z. B. `{name} - {link}` ergibt `Luxon Studios - https://…`.

Laufende Events lassen sich mit `/event edit` weiter anpassen – die Event-Nachricht wird sofort aktualisiert.

## Befehle

| Befehl | Wer | Was |
|---|---|---|
| `/event create type:` | Staff | Neues Event anlegen (Setup-Menü) |
| `/event edit event:` | Staff | Setup-Menü eines Events öffnen |
| `/event copy event:` | Staff | Einstellungen eines Events als neuen Entwurf kopieren (für wiederkehrende Events) |
| `/event list` | alle | Alle Events des Servers |
| `/event participants event:` | alle* | Teilnehmerliste (*wenn öffentlich, Staff immer) |
| `/event ranking event:` | alle | Aufrufe- oder Vote-Rangliste (`refresh:True` = Staff prüft Videos sofort neu) |
| `/event vote event: entry:` | alle | Abstimmen (Alternative zum 🗳️-Knopf, auch bei mehr als 25 Einträgen) |
| `/event end event:` | Staff | Event (oder Voting) sofort beenden |
| `/event cancel event:` | Staff | Event absagen (Entwürfe werden gelöscht) |
| `/event winner event: user: …` | Staff | Gewinner selbst festlegen (bis zu 3 auf einmal) |
| `/event reroll event:` | Staff | Neu auslosen (andere Gewinner als vorher) |
| `/event remove event: user:` | Staff | Teilnehmer entfernen |
| `/event export event:` | Staff | Alle Einträge als Tabelle (CSV) + Textliste herunterladen |
| `/event config` | Staff | Server-Einstellungen: Staff-Rollen, Standard-Ergebniskanal, Zeitzone |

Bei `event:` einfach anfangen zu tippen – der Bot schlägt passende Events vor.
Auf der Event-Nachricht gibt es je nach Einstellung die Knöpfe **Join**, **Leave**, **🗳️ Vote**, **📊 Ranking** und **👥 Participants**.

**Staff** = Server-Besitzer, alle mit *Administrator* oder *Server verwalten*, und die Rollen aus `/event config`.
Solange dort keine Rollen gewählt sind, zählen auch Rollen namens `Owner`, `Developer`, `Admin` (änderbar in `.env`).

## Gewinner-Modi

- **No winners** – nur Anmeldungen sammeln (z. B. Turnier).
- **Staff picks** – am Ende erscheint im Ergebnis-Kanal ein Auswahlmenü (bei Video-/Vote-Events nach Rang sortiert).
- **Random draw** – der Bot lost automatisch aus und verkündet die Gewinner; `/event reroll` lost neu.
- **Most votes** – Mitglieder stimmen ab (1 Stimme pro Person, änderbar), die meisten Stimmen gewinnen. Stimmen sind bis zum Ende geheim.
- **Most views** – nur Video-Contests: die meisten Aufrufe gewinnen automatisch.

## Video-Contests

- **YouTube**: mit API-Key findet der Bot die Videos **automatisch**; ohne Key tragen Teilnehmer ihre Video-Links ein
  und der Bot liest die Aufrufe von der Videoseite.
- **TikTok**: Teilnehmer tragen ihre Video-Links ein (TikTok blockt so etwas manchmal – dann steht „could not read …“ in der Rangliste).
- Es zählen nur Videos mit dem Hashtag (falls gesetzt), vom eingetragenen Kanal und – wenn eingestellt – nach dem Start.

## Einrichtung

Voraussetzung: [Node.js](https://nodejs.org) 18 oder neuer.

### 1. Bot bei Discord anlegen
1. <https://discord.com/developers/applications> → **New Application**.
2. **Bot** → *Reset Token* → Token kopieren (= `DISCORD_TOKEN`).
3. **General Information** → *Application ID* kopieren (= `CLIENT_ID`).
4. **OAuth2 → URL Generator**: Scopes `bot` + `applications.commands`, Bot-Rechte
   *View Channels*, *Send Messages*, *Embed Links*, *Attach Files*, *Mention Everyone* (nur zum Pingen von @everyone/Rollen).
   Link öffnen und den Bot auf deinen Server einladen.

### 2. YouTube-API-Key (optional)
Nur für Video-Contests nötig, damit YouTube-Videos automatisch gefunden werden.
1. <https://console.cloud.google.com> → neues Projekt anlegen.
2. *APIs & Services → Library* → **YouTube Data API v3** → *Enable*.
3. *APIs & Services → Credentials* → *Create credentials → API key* → Key kopieren (= `YOUTUBE_API_KEY`).
4. Key anklicken → *API restrictions* → nur **YouTube Data API v3** → *Save*. Den Key nirgends öffentlich posten.

### 3. Starten

**Windows:** Im Ordner `discord-bot` auf **`start.bat`** doppelklicken.
- Beim ersten Mal öffnet sich die `.env` im Editor → Token, Client-ID und Server-ID eintragen → Strg+S → schließen.
- Nochmal `start.bat` doppelklicken → der Bot installiert sich, registriert die Befehle und startet.
- Das schwarze Fenster offen lassen, solange der Bot laufen soll.

**Manuell / Mac / Linux:**
```bash
cd discord-bot
npm install
cp .env.example .env      # dann .env ausfüllen
npm run deploy            # Slash-Commands registrieren (nach jedem Update nötig)
npm start                 # Bot starten
```

Danach im Server `/event config` aufrufen und die **Staff-Rollen** und die **Zeitzone** einstellen.

Der Bot muss dauerhaft laufen, damit Events automatisch starten und enden. War er offline, holt er verpasste
Starts, Erinnerungen und Enden beim nächsten Start nach. Alle Daten liegen in `data/events.json`.

### Update von der alten `/contest`-Version
Einfach die neuen Dateien übernehmen und `start.bat` starten (bzw. `npm run deploy` + `npm start`).
Alte Contests aus `data/contests.json` werden **automatisch übernommen** (als Video-Contest), laufende Contest-Nachrichten
bekommen die neuen Knöpfe, und `/contest` wird durch `/event` ersetzt.

## Dateien

```
src/index.js            Befehle, Knöpfe, Formulare, Setup-Menü
src/lifecycle.js        Ablauf: veröffentlichen, starten, erinnern, beenden, Voting, Gewinner
src/render.js           Event-Nachricht, Setup-Menü, Server-Einstellungen
src/types.js            Event-Typen (Vorlagen), Fragetypen, Gewinner-Modi
src/videos.js           YouTube-/TikTok-Prüfung (Hashtag, Aufrufe, Rangliste)
src/time.js             Dauer/Datum mit Zeitzone
src/store.js            Speichern in data/events.json (+ Übernahme alter Contests)
src/util.js             Rechte, Links, Listen-Format
src/commands.js         Slash-Commands
src/deploy-commands.js  registriert die Slash-Commands bei Discord
```

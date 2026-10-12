# Weak Spot CC-Contest-Bot (Discord)

Discord-Bot für Content-Creator-Contests zu **Weak Spot** (Roblox): Wer macht das Video mit den meisten Aufrufen?
Alle Texte im Bot sind auf **Englisch**.

## Ablauf

1. **Admin / Developer / Owner** startet einen Contest: `/contest start duration:10d`
   → es öffnet sich ein Formular für **Titel**, **Beschreibung/Regeln** (mehrzeilig) und **Preis**.
   Optional: `channel:` (wo gepostet wird) und `ping:` (Rolle, die erwähnt wird).
2. Im Kanal erscheint eine Contest-Nachricht mit **Join Contest**-Knopf. Wer mitmacht, gibt ein:
   - **Channel name** (z. B. `Luxon Studios`)
   - **YouTube- oder TikTok-Kanal-Link**
   - optional die **Video-Links** (bei TikTok Pflicht, siehe unten)

   Nochmal auf *Join Contest* klicken = Eintrag bearbeiten / Videos hinzufügen. *Leave* = austreten.
3. Nach Ablauf (z. B. 10 Tage) schließt der Bot den Contest **automatisch**, prüft alle Videos und postet:
   - die **Rangliste nach Aufrufen** (nur Videos mit **#weakspot**),
   - die **Teilnehmerliste** im gewünschten Format (+ als `.txt`-Datei):
     ```
     Luxon Studios - https://www.youtube.com/@LuxonStudios,
     Thebestall - https://www.tiktok.com/@thebestall
     ```
   - ein **Auswahlmenü**, in dem du den **Gewinner** auswählst (nur Staff kann es benutzen).
4. Der Bot verkündet den Gewinner im Contest-Kanal.

## Befehle

| Befehl | Wer | Was |
|---|---|---|
| `/contest start duration:10d` | Staff | Neuen Contest starten (Formular für Titel/Beschreibung/Preis). Dauer z. B. `10d`, `12h`, `1d12h`, `2w` |
| `/contest edit` | Staff | Titel, Beschreibung und Preis nachträglich ändern |
| `/contest list` | alle | Teilnehmerliste anzeigen |
| `/contest leaderboard` | alle | YouTube/TikTok prüfen: wer hat die meisten Aufrufe? (Staff: `refresh:True` = sofort neu prüfen, sonst 10 Min. Cache; Staff sieht auch, warum Videos nicht zählen) |
| `/contest end` | Staff | Contest sofort beenden |
| `/contest winner user:@…` | Staff | Gewinner wählen (Alternative zum Auswahlmenü) |
| `/contest remove user:@…` | Staff | Teilnehmer entfernen (z. B. bei Fake-Views) |

**Staff** = Server-Besitzer, alle mit *Administrator*-Recht und alle mit einer Rolle namens
`Owner`, `Developer` oder `Admin` (einstellbar in `.env` → `STAFF_ROLE_NAMES` / `STAFF_ROLE_IDS`).
Es kann immer nur **ein** Contest gleichzeitig laufen.

## Wie die Videos geprüft werden

Ein Video zählt nur, wenn
- **#weakspot** im Titel, in der Beschreibung oder in den Tags steht (Hashtag in `.env` → `HASHTAG` änderbar),
- es **nach dem Contest-Start** hochgeladen wurde (`ONLY_NEW_VIDEOS=false` schaltet das ab),
- es **vom eingetragenen Kanal** stammt (fremde Videos werden ignoriert).

Pro Teilnehmer zählt das **Video mit den meisten Aufrufen**.

- **YouTube** (inkl. Shorts): Der Bot findet die Videos **automatisch** über die offizielle YouTube Data API
  (braucht einen kostenlosen API-Key, siehe unten).
- **TikTok**: TikTok hat keine öffentliche API für fremde Profile. Teilnehmer müssen deshalb ihre
  **Video-Links im Join-Formular eintragen**; der Bot liest die Aufrufe dann von der öffentlichen Videoseite.
  TikTok blockt so etwas manchmal (vor allem von Server-/Hosting-IPs) – dann steht in der Rangliste
  „could not read …“ und du musst die Aufrufe bei diesem Video selbst nachschauen.

Den Gewinner wählst am Ende immer **du** aus – die Rangliste ist die Entscheidungshilfe.

## Einrichtung

Voraussetzung: [Node.js](https://nodejs.org) 18 oder neuer.

### 1. Bot bei Discord anlegen
1. <https://discord.com/developers/applications> → **New Application**.
2. **Bot** → *Reset Token* → Token kopieren (= `DISCORD_TOKEN`).
3. **General Information** → *Application ID* kopieren (= `CLIENT_ID`).
4. **OAuth2 → URL Generator**: Scopes `bot` + `applications.commands`, Bot-Rechte
   *View Channels*, *Send Messages*, *Embed Links*, *Attach Files*, *Mention Everyone* (nur für `ping:`).
   Link öffnen und den Bot auf deinen Server einladen.

### 2. YouTube-API-Key holen (kostenlos)
1. <https://console.cloud.google.com> → neues Projekt anlegen.
2. *APIs & Services → Library* → **YouTube Data API v3** → *Enable*.
3. *APIs & Services → Credentials* → *Create credentials → API key* → Key kopieren (= `YOUTUBE_API_KEY`).

Das kostenlose Kontingent (10.000 Einheiten/Tag) reicht locker: eine Prüfung kostet ca. 2–3 Einheiten pro Teilnehmer.

### 3. Konfigurieren und starten
```bash
cd discord-bot
npm install
cp .env.example .env      # dann .env ausfüllen
npm run deploy            # Slash-Commands registrieren (einmalig bzw. nach Änderungen an den Befehlen)
npm start                 # Bot starten
```

Mit `GUILD_ID` in der `.env` sind die Befehle sofort auf deinem Server da; ohne `GUILD_ID` werden sie global
registriert (kann bis zu 1 Stunde dauern).

Der Bot muss dauerhaft laufen, damit Contests automatisch enden (z. B. auf einem VPS, Raspberry Pi oder bei einem
Bot-Hoster). Wenn er zwischendurch offline war, schließt er abgelaufene Contests beim nächsten Start sofort.
Alle Daten liegen in `data/contests.json`.

## Dateien

```
src/index.js            Bot: Contest-Nachricht, Knöpfe, Formulare, automatisches Beenden, Gewinner
src/videos.js           YouTube-/TikTok-Prüfung (#weakspot, Aufrufe, Rangliste)
src/commands.js         Slash-Commands
src/deploy-commands.js  registriert die Slash-Commands bei Discord
src/store.js            Speichern in data/contests.json
src/util.js             Rechte-Check, Dauer, Listen-Format
```

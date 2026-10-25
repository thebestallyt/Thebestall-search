# Event-Bot (Yapin')

Derselbe Event-Bot wie im Ordner `discord-bot`, aber für **Yapin'** (früher Yapper, <https://www.yapper.website>).
Er kann **alle Arten von Events**: Video-Contests, Einsendungs-Contests mit Voting, Giveaways, Anmeldungen für
Turniere oder komplett eigene Events. Alle Texte im Bot sind auf **Englisch**.

## Was anders ist als bei Discord

Yapin' hat (noch) keine Pop-up-Formulare, Auswahlmenüs und Slash-Befehle mit Auswahlfeldern. Deshalb:

| Discord-Version | Yapin'-Version |
|---|---|
| Slash-Befehle mit Auswahlfeldern | Textbefehle, z. B. `/event set 5 end 7d` (auch mit `!` statt `/`) |
| Setup-Menü mit Knöpfen | Übersicht aller Einstellungen + `/event set <id> <einstellung> <wert>` |
| Formular (Pop-up) zum Mitmachen | Der Bot stellt die Fragen **per Direktnachricht** nacheinander |
| Auswahlmenüs (Voting, Gewinner) | **Knöpfe** für jeden Eintrag (mit Blättern bei vielen Einträgen) |
| Zeitstempel, die sich selbst aktualisieren | Datum und Uhrzeit in der Zeitzone des Servers + „in 3 days“ |
| Datei-Export | Liste/CSV als Text per Direktnachricht |

Alles andere ist gleich: die 5 Event-Typen, Voting, Auslosen, Video-Ranking (YouTube/TikTok), Erinnerungen,
geplanter Start, automatisches Ende.

## Event-Typen

| Typ | Befehl | Standard |
|---|---|---|
| 🎥 Video views contest | `/event create views` | Fragen: Kanalname, Kanal-Link, Video-Links · Hashtag · Rangliste nach Aufrufen |
| 🎨 Submission contest | `/event create submission` | Fragen: Link + Notiz · optional Voting |
| 🎁 Giveaway | `/event create giveaway` | keine Fragen, ein Klick · zufällige Auslosung |
| 📋 Sign-up | `/event create signup` | Frage: Roblox-Name · begrenzte Plätze · keine Gewinner |
| ⚙️ Custom event | `/event create custom` | frei einstellbar |

## So erstellst du ein Event

1. In einem Staff-Kanal: `/event create views` → der Bot postet eine **Übersicht** mit allen Einstellungen und der Event-Nummer (z. B. **#5**).
2. Einstellungen ändern, z. B.:
   ```
   /event set 5 title Weak Spot Video Contest
   /event set 5 description Make a Weak Spot video with #weakspot – most views wins!
   /event set 5 end 10d
   /event set 5 prize 1000 Robux
   /event set 5 channel #events
   /event set 5 results #staff
   ```
   Die Übersicht aktualisiert sich nach jeder Änderung von selbst.
3. **👁️ Preview** drücken (oder `/event preview 5`), dann **🚀 Publish** (oder `/event publish 5`).
4. Mitglieder drücken **Join** unter dem Event – der Bot schreibt ihnen eine **Direktnachricht** und fragt alles nacheinander ab.
   Wer keine DMs bekommt, kann auch tippen: `/event join 5 Luxon Studios | https://youtube.com/@luxonstudios`
5. Am Ende beendet der Bot das Event automatisch, postet die Ergebnisse und ermittelt die Gewinner
   (oder zeigt dem Staff im Ergebnis-Kanal Knöpfe zum Auswählen).

### Alle Einstellungen (`/event set <id> <einstellung> <wert>`)

| Einstellung | Beispiel | Bedeutung |
|---|---|---|
| `title` | `Weak Spot Contest` | Titel |
| `description` | `Rules: …` | Beschreibung/Regeln (mehrere Zeilen erlaubt) |
| `prize` | `1000 Robux` | Preis |
| `image` | `https://…/banner.png` | Bild |
| `color` | `#ff2e3e` | Farbe |
| `start` | `2h` · `2026-10-31 18:00` · `now` | Start (leer/`now` = beim Veröffentlichen) |
| `end` | `10d` · `1d12h` · `2026-11-07 20:00` | Ende (Dauer ab Start oder Datum) |
| `max` | `16` · `none` | max. Teilnehmer |
| `reminders` | `24, 1` · `off` | Erinnerungen x Stunden vor dem Ende |
| `channel` | `#events` | Kanal, in dem das Event gepostet wird |
| `results` | `#staff` | Kanal für Ergebnisse und Gewinner-Auswahl |
| `ping` | `everyone` · `@Gamer` | Rolle, die beim Start gepingt wird |
| `role` | `VIP` | Rolle, die man zum Mitmachen braucht |
| `mode` | `none` / `manual` / `random` / `votes` / `views` | Wie die Gewinner bestimmt werden |
| `winners` | `3` | Anzahl Gewinner |
| `format` | `{name} - {link}` | Format der Teilnehmerliste |
| `button` | `Join Contest` | Text auf dem Mitmachen-Knopf |
| `public` | `yes` / `no` | Teilnehmerliste für alle sichtbar |
| `leave` | `yes` / `no` | Austreten / Eintrag ändern erlaubt |
| `hashtag` | `weakspot` · `none` | Pflicht-Hashtag (nur Video-Contests) |
| `platforms` | `youtube, tiktok` | erlaubte Plattformen (nur Video-Contests) |
| `onlynew` | `yes` / `no` | nur Videos nach dem Start zählen |
| `voting` | `off` / `during` / `after` | Voting aus / während des Events / nach der Deadline |
| `votetime` | `1d` | Dauer des Votings bei `after` |
| `selfvote` | `yes` / `no` | für sich selbst voten erlaubt |

Mit `none` löschst du optionale Einstellungen wieder (z. B. `/event set 5 prize none`).

**Listen-Format:** `{user}` (@Name), `{username}` und die Schlüssel deiner Fragen (stehen in der Übersicht),
z. B. `{name} - {link}` ergibt `Luxon Studios - https://…`.

### Fragen zum Mitmachen (`/event question <id> …`)

```
/event question 5                                         → alle Fragen anzeigen
/event question 5 add Roblox username | text | yes | e.g. Builderman
/event question 5 edit 2 | link                           → nur den Typ von Frage 2 ändern
/event question 5 remove 3
/event question 5 clear                                   → keine Fragen = ein Klick zum Mitmachen
```
Typen: `text`, `long`, `link`, `number` – bei Video-Contests zusätzlich `channel` (YouTube/TikTok-Kanal) und `videos` (Video-Links).
Bis zu 10 Fragen.

## Befehle

| Befehl | Wer | Was |
|---|---|---|
| `/event help` | alle | Übersicht aller Befehle |
| `/event list` | alle | Alle Events des Servers |
| `/event join <id> [antworten]` | alle | Mitmachen (wie der Join-Knopf) |
| `/event leave <id>` | alle | Austreten |
| `/event participants <id>` | alle* | Teilnehmerliste (*wenn öffentlich; Staff bekommt private Listen per DM) |
| `/event ranking <id>` | alle | Aufrufe- oder Vote-Rangliste (`/event ranking 5 refresh` = Staff prüft sofort neu) |
| `/event vote <id> <nummer>` | alle | Abstimmen (Nummer aus der Liste, oder `@name`) |
| `/event create <typ>` | Staff | Neues Event (Entwurf) |
| `/event set …` / `/event question …` | Staff | Einstellungen und Fragen ändern |
| `/event show <id>` | Staff | Übersicht der Einstellungen neu posten |
| `/event preview <id>` · `/event publish <id>` | Staff | Vorschau · veröffentlichen |
| `/event copy <id>` | Staff | Einstellungen als neuen Entwurf kopieren |
| `/event end <id>` | Staff | Event (oder Voting) sofort beenden |
| `/event cancel <id>` | Staff | Absagen (Entwürfe werden gelöscht) |
| `/event winner <id> <nummer/@name> …` | Staff | Gewinner selbst festlegen |
| `/event reroll <id> [anzahl]` | Staff | Neu auslosen |
| `/event remove <id> <nummer/@name>` | Staff | Teilnehmer entfernen |
| `/event export <id>` | Staff | CSV + Liste per Direktnachricht |
| `/event config` | Staff | Staff-Rollen, Ergebnis-Kanal, Zeitzone |

**Staff** = Server-Besitzer, Rollen mit dem Recht „Server verwalten“ und die Rollen aus `/event config staff Mod, Event Team`.
Solange dort keine Rollen eingestellt sind, zählen auch Rollen namens `Owner`, `Developer`, `Admin` (änderbar in `.env`).

Weil Yapin' keine „nur für dich sichtbaren“ Antworten auf Textbefehle kennt, antwortet der Bot auf Befehle im Kanal.
Nur bei Knöpfen sind die Antworten privat. Richte Events deshalb am besten in einem Staff-Kanal ein.

## Einrichtung

Voraussetzung: [Node.js](https://nodejs.org) 18 oder neuer.

### 1. Bot bei Yapin' anlegen
1. Auf <https://www.yapper.website/developers> einen Bot erstellen und den **Bot-Token** kopieren (beginnt mit `yb_`).
2. Den Bot auf deinen Server einladen. Er braucht die Rechte, Kanäle zu sehen, Nachrichten zu senden/bearbeiten
   und Direktnachrichten zu schicken.
3. Den Token **niemals** öffentlich posten (auch nicht auf Screenshots). Falls doch: sofort neu erstellen.

### 2. YouTube-API-Key (optional)
Wie beim Discord-Bot – nur für Video-Contests nötig, damit YouTube-Videos automatisch gefunden werden.
Du kannst denselben Key wie beim Discord-Bot benutzen.

### 3. Starten

**Windows:** Im Ordner `yapper-bot` auf **`start.bat`** doppelklicken.
- Beim ersten Mal öffnet sich die `.env` im Editor → `YAPPER_BOT_TOKEN` (und optional `YOUTUBE_API_KEY`) eintragen → Strg+S → schließen.
- Nochmal `start.bat` doppelklicken → der Bot installiert sich und startet.
- Das schwarze Fenster offen lassen, solange der Bot laufen soll.

**Manuell / Mac / Linux:**
```bash
cd yapper-bot
npm install
cp .env.example .env      # dann .env ausfüllen
npm start
```

Danach im Server `/event config` aufrufen und die **Staff-Rollen** und die **Zeitzone** einstellen.

Der Bot muss dauerhaft laufen, damit Events automatisch starten und enden. War er offline, holt er verpasste
Starts, Erinnerungen und Enden beim nächsten Start nach. Befehle, die älter als 10 Minuten sind, führt er nach
einer Pause nicht mehr aus. Alle Daten liegen in `data/events.json`.

## Noch nicht getestet (Yapin' ist neu)

Der Bot wurde gegen eine nachgebaute Yapin'-Schnittstelle getestet, nicht gegen den echten Server.
Falls etwas nicht klappt, sind das die wahrscheinlichsten Stellen:
- **Antworten per Direktnachricht** – falls der Bot DM-Antworten nicht bekommt, steht in der ersten DM der Ersatzbefehl `/event join <id> a | b`.
- **Rollen-Ping** (`<@&id>`) – falls Yapin' das nicht als Ping anzeigt, `ping everyone` benutzen.
- **Knopf-Antworten, die eine Nachricht ändern** (Voting-Liste, Gewinner-Auswahl) – falls das fehlschlägt, schickt der Bot stattdessen eine neue private Antwort.

## Dateien

```
src/index.js      Start, Ereignis-Schleife (Long-Polling), Zeitsteuerung
src/handlers.js   Textbefehle und Knöpfe
src/join.js       Mitmachen: Fragen per DM oder alles auf einmal
src/lifecycle.js  Ablauf: veröffentlichen, starten, erinnern, beenden, Voting, Gewinner
src/render.js     Event-Nachricht, Übersicht, Voting- und Gewinner-Knöpfe, Hilfe
src/api.js        Verbindung zur Yapin' Bot API
src/perms.js      Staff-Rechte, Rollen und Kanäle finden
src/types.js      Event-Typen (Vorlagen), Fragetypen, Gewinner-Modi   (gleich wie Discord)
src/videos.js     YouTube-/TikTok-Prüfung                              (gleich wie Discord)
src/time.js       Dauer/Datum mit Zeitzone                             (gleich wie Discord)
src/store.js      Speichern in data/events.json
src/util.js       Links, Listen-Format, Datum
```

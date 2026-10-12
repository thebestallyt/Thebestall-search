# NOVA CLASH – Roblox Fighting Game

Ein Roblox-Kampfspiel mit Rundensystem, in dem sich alles um **Fähigkeiten mit aufwendigen VFX** dreht.
Fähigkeiten bekommt man aus **Lootboxen (Kisten)** – je seltener, desto spektakulärer. Die mächtigsten
Fähigkeiten haben eine eigene **Kino-Cutscene**. Die exklusive **BLACK HOLE**-Fähigkeit gibt es im Robux-Shop.

Die Texte im Spiel sind auf **Englisch**, die Kommentare im Code auf Deutsch.

---

## Schnellstart (ohne Programmieren)

1. Öffne **`NovaClash.rbxl`** in Roblox Studio (Doppelklick oder *Datei → Öffnen*).
2. Drücke **Play** (F5). Die komplette Welt (Terrain-Landschaft, Lobby, Arena, Licht) wird beim Start automatisch per Code gebaut – das dauert ein paar Sekunden.
3. Zum Speichern von Spielerdaten: Spiel veröffentlichen und unter
   *Game Settings → Security → „Enable Studio Access to API Services“* aktivieren.

> Tipp zum Testen: Runden starten auch alleine – leere Plätze werden mit KI-Bots aufgefüllt
> (`Config.Round.FillWithBots`). In der Lobby stehen außerdem Trainingspuppen.

## Steuerung

| Taste | Aktion |
|---|---|
| Linksklick (gedrückt halten) | M1-Kombo (4 Schläge, der 4. schleudert weg und bricht Blocks) |
| F (halten) | Blocken (–75 % Schaden) |
| Q | Dash |
| 1 / 2 / 3 / 4 | Fähigkeiten-Slots |
| E | Kisten-Altar / Black-Hole-Schrein in der Lobby |

Auf Handy/Tablet erscheinen große Kampf-Knöpfe, die Fähigkeiten-Slots sind antippbar. Controller wird ebenfalls unterstützt.

## Features

- **Rundensystem**: Lobby → Countdown → Kampf in der Arena (letzter Überlebender gewinnt) → Sieger-Ehrung → zurück in die Lobby.
  Münzen für Kills, Siege und Teilnahme. Wer ausgeschieden ist, kann **zuschauen**.
- **15 Fähigkeiten in 8 Seltenheiten** (Common → Divine + exklusiv), jede mit eigenen Effekten:
  Feuerfaust, Felsen-Smash, Windstoß, Eissplitter, Blitz-Dash, Feuerring, Wasserstrudel, Gewitter,
  Schattenschritt, Meteor, Drachenatem (Geisterdrache), …
- **Cutscene-Fähigkeiten** mit Letterbox, Titelkarte und Kamerafahrten:
  - *Celestial Judgment* (Mythic) – ein gigantisches Lichtschwert fällt vom Himmel
  - *Blood Moon* (Mythic) – roter Himmel, aufgehender Blutmond, Blitzschnitte
  - *Supernova* (Divine) – ein Stern entsteht über dem Spieler und explodiert
  - *Black Hole* (Robux-exklusiv) – Singularität mit Akkretionsscheibe saugt alle ein und implodiert
- **Kisten-Öffnung in 3D**: Die Kiste fällt auf eine Bühne, man tippt 3× drauf, sie bekommt leuchtende Risse und
  **wechselt die Farbe, wenn die Seltenheit steigt**. Bei Mythic/Divine schwebt sie, Blitze zucken, dann platzt sie auf.
  Danach erscheint eine Ergebnis-Karte mit Vorschau-Knopf.
- **Startmenü mit Intro-Animation** (beim ersten Beitritt ein längeres Intro mit Energiering) und **interaktives Tutorial**
  (Leuchtpfad zu den Trainingspuppen, Pfeile auf HUD-Knöpfe, Gratis-Starterkiste).
- **Welt**: grüne Terrain-Landschaft mit Hügeln, schneebedeckten Bergen, See und Bach, Kiefern und Eichen,
  ein Dorf-Platz als Lobby (Kisten-Altar, Black-Hole-Schrein, Trainingsplatz, Lagerfeuer, Zelte, Hütten)
  und ein altes Stein-Kolosseum als Arena.
- **GUI**: „Chunky Game UI“ – satte Farben, dicke Umrisse, 3D-Buttons zum Eindrücken, runde Schrift,
  Shop mit 3D-Vorschau (Schwarzes Loch, Münzhaufen), Kombo-Zähler, Schadenszahlen, Killfeed, Lebensbalken über Kämpfern.
- **Bot-Runden**: Ist niemand bereit, kämpfen Bots gegeneinander (zuschauen möglich); sobald ein Spieler bereit ist,
  startet eine echte Runde.
- **Admin-System**: siehe unten.

## Admin (RealThebestall)

In `src/shared/Config.luau` → `Config.Admins`:

```lua
Config.Admins = {
	Usernames = { "RealThebestall" },
	UserIds = {},
	Title = "👑 ADMIN",
}
```

Admins (und automatisch der Ersteller des Spiels) bekommen:
- einen **animierten „👑 ADMIN“-Titel** über dem Kopf und einen **[👑 ADMIN]-Tag im Chat**,
- einen **👑-Knopf** links im HUD → Admin-Panel (Münzen, alles freischalten, Runde starten/beenden,
  Cooldowns zurücksetzen, heilen, Tutorial zurücksetzen, Bots entfernen, Ansage an alle),
- **Chat-Befehle**: `/coins 1000`, `/unlockall`, `/start`, `/end`, `/cd`, `/heal`, `/resettutorial`, `/killbots`, `/announce Text`.

Alle Admin-Befehle werden auf dem Server geprüft.

## Robux-Shop einrichten

1. Auf create.roblox.com einen **Game Pass** „Black Hole“ und (optional) drei **Developer Products** für Münzpakete anlegen.
2. Die IDs in `src/shared/Config.luau` → `Config.Shop` eintragen (`BlackHoleGamePassId`, `CoinPacks[i].ProductId`).
3. Solange eine ID `0` ist, wird der Kauf **in Studio simuliert** (zum Testen). Im Live-Spiel erscheint dann ein Hinweis.

## Anpassen

| Was | Wo |
|---|---|
| Rundenzeiten, Belohnungen, Bots, Schaden, Dash … | `src/shared/Config.luau` |
| Fähigkeiten (Schaden, Cooldown, Timing, Beschreibung) | `src/shared/Abilities.luau` |
| Kisten (Preis, Chancen) | `src/shared/Crates.luau` |
| Sounds | `src/shared/Sounds.luau` – standardmäßig eingebaute Roblox-Sounds; für noch mehr Wucht eigene Sound-IDs aus dem Creator Store eintragen |
| Server-Logik der Fähigkeiten | `src/server/Services/AbilityService.luau` |
| Effekte der Fähigkeiten | `src/client/VFX/AbilitiesBasic.luau`, `src/client/VFX/AbilitiesCinematic.luau` |
| Landschaft / Map | `src/server/Services/WorldBuilder.luau` |
| Design (Farben, Schriften, Buttons) | `src/client/UI/Theme.luau`, `src/client/UI/UI.luau` |

Eine neue Fähigkeit braucht drei Dinge: einen Eintrag in `Abilities.luau`, einen Handler in `AbilityService.luau`
und eine VFX-Funktion mit derselben Id in `AbilitiesBasic.luau` (oder `AbilitiesCinematic.luau`).

## Projektstruktur (Rojo)

```
default.project.json        Rojo-Projekt (Services + Eigenschaften wie Future-Lighting)
NovaClash.rbxl              fertig gebaute Place-Datei
src/shared/   -> ReplicatedStorage.Shared       Config, Fähigkeiten, Kisten, Seltenheiten, Sounds, Netzwerk
src/server/   -> ServerScriptService.Server     Main + Services (Daten, Welt, Kampf, Fähigkeiten, Runden, Kisten, Shop, Bots, Admin)
src/client/   -> StarterPlayerScripts.Client    Main + Controllers (HUD, Menü, Tutorial, Kisten, Inventar, Shop, Admin …),
                                                UI (Theme + Bausteine), VFX (Effekte, Cutscenes, Kistenmodell)
```

Mit [Rojo](https://rojo.space) neu bauen bzw. live synchronisieren:

```bash
rojo build default.project.json -o NovaClash.rbxl   # Place-Datei bauen
rojo serve                                           # Live-Sync mit dem Rojo-Plugin in Studio
```

## Hinweise

- Alle Effekte werden auf den Clients gerendert, der Server entscheidet über Treffer und Schaden (keine Cheats durch Client-Manipulation).
- Ohne veröffentlichte Place/API-Zugriff funktionieren DataStores in Studio nicht – das Spiel läuft trotzdem, speichert aber nichts.
- Der Code wurde gegen die aktuelle Roblox-API typgeprüft. Bitte trotzdem in Studio ausgiebig testen
  (Play-Test mit mehreren Spielern über *Test → Clients and Servers*).

## Discord-Bot für CC-Contests

Im Ordner [`discord-bot/`](discord-bot/README.md) liegt ein Discord-Bot für Content-Creator-Contests
(meiste Aufrufe auf ein Weak-Spot-Video mit #weakspot, YouTube + TikTok). Einrichtung siehe dort.

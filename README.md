# n8nmining

Solar Mining ROI Dashboard – ein n8n-Workflow, der den Stromverbrauch einer
PV-gesteuerten Bitcoin-Miner-Flotte (Avalon Nano 3S x2, BitAxe x2) dem
Mining-Ertrag gegenüberstellt (Tag/Woche/Jahresprognose) und als HTML-Seite
über einen Webhook ausliefert.

## Architektur

Workflow: `workflows/solar-mining-roi-dashboard.json` (n8n Workflow SDK / Nodes)

1. **Home Assistant** – Leistungs-Historie (7 Tage) der 4 Miner + Ein/Aus-Historie
   der Steckdosen-Schalter (echte Laufzeiten) + Arbeitsmodus der Avalons.
   Per Trapezregel zu kWh integriert (24h und 7 Tage, rollierend).
2. **Braiins Pool API** – Profile + tägliche Rewards (Avalon #1+#2, BitAxe #2).
3. **CoinGecko** – aktueller BTC/EUR-Kurs.
4. **pool.powermining.io** – Lottery-Check für BitAxe #1 (solo, öffentliche API
   unter Port 40557, reverse-engineered aus dem `public-pool`-Frontend-Bundle).
5. **ocean.xyz** – Zusatzertrag für BitAxe #2 (läuft zeitweise dort statt
   Braiins). Keine offizielle JSON-API vorhanden, Werte werden per Regex aus
   der öffentlichen Stats-Seite extrahiert (`/stats/<btc-adresse>`) – etwas
   fragil, kann brechen wenn Ocean das Seitenlayout ändert.
6. **aWATTar SUNNY** – aktueller Einspeisetarif (live von der Website
   geparst), verwendet als Opportunitätskosten-Basis: die Miner laufen nur
   bei PV-Überschuss, "Kosten" = entgangene Einspeisevergütung, NICHT der
   Netzbezugspreis.
7. **Claude (Anthropic API)** – liest den fertigen Report als JSON und schreibt
   eine kurze, sachliche Einschätzung (lohnt sich Mining aktuell? Haupttreiber?
   Lottery-Chance?), landet oben im Dashboard. ~9 Sek. Laufzeit, ~0,007 $ pro
   Aufruf bei `claude-sonnet-5`.
8. **HTML-Report** – wird bei jedem Aufruf frisch aus allen obigen Quellen
   gebaut und über einen Webhook ausgeliefert.

## Setup

### 1. n8n starten

```bash
docker compose up -d
```

`docker-compose.yml` bindet den bestehenden Windows-Datenordner
(`C:\Users\kraemhel\.n8n`) ein, in dem Workflows, Credentials und Executions
liegen. Das ist bewusst so gewählt: falls der Container mal komplett
verschwindet (ist uns passiert – vermutlich durch einen Docker-Desktop-Reset,
nicht nur gestoppt, sondern weg), stellt `docker compose up -d` ihn ohne
Datenverlust wieder her, weil die Daten nie *im* Container lagen. `restart:
unless-stopped` sorgt zusätzlich dafür, dass Docker ihn nach einem Docker-
Neustart selbst wieder hochfährt.

### 2. Workflow importieren

n8n-UI → Workflows → Import from File → `workflows/solar-mining-roi-dashboard.json`

### 3. Credentials anlegen (nicht im Export enthalten, aus Sicherheitsgründen)

| Credential-Name | Typ | Verwendet für |
|---|---|---|
| Home Assistant account | Home Assistant API | (aktuell ungenutzt seit History-Umstieg, kann bleiben) |
| Home Assistant Bearer | Bearer Auth | HA REST History-API (`/api/history/period/...`) |
| Braiins Pool API | Header Auth (`Pool-Auth-Token`) | Braiins Profile + Rewards |
| Anthropic account | Anthropic API | KI-Einschätzung im Dashboard (Claude, Modell `claude-sonnet-5`) |

Nach dem Import müssen die betroffenen HTTP-Request- und Home-Assistant-Nodes
manuell auf die neu angelegten Credentials verweisen (n8n behält Credential-
Zuordnungen beim Import nicht bei, da die IDs pro Instanz unterschiedlich sind).

Home Assistant Long-Lived Access Token: Profil → Sicherheit → Long-Lived
Access Tokens, in Home Assistant erstellen.

Braiins Pool Access Token: pool.braiins.com → Account Settings → API Access
→ Access Profile für BTC.

Anthropic API Key: console.anthropic.com → API Keys → Create Key.

**Wichtiger HA-Stolperstein:** Falls Home Assistant die Docker-IP von n8n
wegen fehlgeschlagener Auth-Versuche blockt (401 in
`homeassistant.components.http.ban`), in `configuration.yaml`:

```yaml
http:
  trusted_proxies:
    - 192.168.5.0/24
  use_x_forwarded_for: true
```

Danach Home Assistant neu starten.

### 4. Entity-IDs anpassen

Die verwendeten Home-Assistant-Entities sind im Node "Define Time Windows &
Entities" hartkodiert:

- `sensor.miner_avalon_nano_3s_leistung` / `..._2_leistung` (Leistung Avalon #1/#2)
- `sensor.bitaxe1_power` / `sensor.bitaxe2_power` (Leistung BitAxe #1/#2)
- `switch.grow_inbox_socket_2` / `switch.grow_inbox_socket_1` (Steckdosen Avalon #1/#2)
- `switch.sonoff_schalter` (Steckdose BitAxe #2)
- `select.miner_avalon_nano_3s_arbeitsmodus` / `..._2_arbeitsmodus` (Arbeitsmodus)

Bei anderer Hardware/Entity-Namen im Node-Parameter `jsonOutput` anpassen.

Bitcoin-Adressen (öffentlich, keine Geheimnisse) für Lottery-Checks:
`bc1qfm6wv0ggw00df2lqc8ck27aansztsrv8k3lw22` (powermining.io + ocean.xyz).

### 5. Publishen

Workflow in n8n aktivieren ("Publish"), damit die Webhook-URL dauerhaft
erreichbar ist:

```
http://localhost:5678/webhook/mining-dashboard
```

## Dashboard öffnen

`start-mining-dashboard.bat` doppelklicken: startet Docker Desktop (falls
nötig), startet n8n über `docker compose up -d` (erstellt den Container bei
Bedarf komplett neu, nicht nur "docker start" auf einen vorhandenen), wartet
bis n8n erreichbar ist, öffnet dann die Dashboard-URL im Standardbrowser (der
Aufruf triggert den Workflow live neu).

### Automatischer Start beim Hochfahren

Eine Verknüpfung im Windows-Autostart-Ordner ruft `start-mining-dashboard.bat`
bei jeder Anmeldung automatisch auf (minimiertes Fenster):

```
%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\Solar Mining Dashboard.lnk
```

Das Skript wartet bis zu 5 Minuten auf Docker (kalter Boot inkl. WSL2-Start
braucht manchmal etwas) und bis zu 2 Minuten auf n8n, bevor es aufgibt.
Falls der PC kein Auto-Login hat, läuft es beim nächsten manuellen Login.

Zum Deaktivieren: die `.lnk`-Datei im Autostart-Ordner löschen.

## Troubleshooting

**Container ist nach einem Neustart komplett weg (nicht nur gestoppt).**
Ist uns einmal passiert, vermutlich durch einen Docker-Desktop-Reset/Update.
Da alle Daten im Windows-Ordner `C:\Users\kraemhel\.n8n` liegen (Bind-Mount,
kein benanntes Docker-Volume), sind Workflows/Credentials/Executions davon
nicht betroffen. Fix: `docker compose up -d` im Projektordner – erstellt den
Container neu und mountet den bestehenden Datenordner, alles ist sofort
wieder da. Das Startskript macht das automatisch.

## Bekannte Einschränkungen

- **Ocean.xyz-Werte**: nur "bisher aufgelaufen (unbezahlt)" wird angezeigt,
  da andere Felder (Lifetime, geschätzt/Tag) beim Testen nicht zuverlässig
  waren. Regex-Extraktion aus HTML, keine offizielle API.
- **BitAxe #2 Pool-Split**: läuft zeitweise auf Ocean statt Braiins, der
  genaue zeitliche Anteil ist nicht bekannt. Sein kWh-Verbrauch wird komplett
  der Braiins-Kostenrechnung zugerechnet (konservativ).
- **BitAxe #1 Laufzeit**: keine Steckdosen-Schalter-Entity vorhanden, daher
  Watt-Schwellenwert-Heuristik (>5W = an) statt echter Ein/Aus-Historie.
- **Jahresprognose**: einfache Hochrechnung des 7-Tage-Durchschnitts x 365,
  keine Saisonalität (Sonnenstunden im Winter vs. Sommer) berücksichtigt.

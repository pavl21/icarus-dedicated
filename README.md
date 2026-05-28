# Icarus Dedicated — pavl21 yolks-style image + Pterodactyl egg

Eigenes Pterodactyl-Paket fuer den **Icarus Dedicated Server** (Steam AppID `2089300`):

- **Docker-Image** im yolks-Stil — Wine, SteamCMD und ein voll-seeded `wineprefix` (vcrun2022 + corefonts) sind bereits im Image. Erstinstallation und Restarts brauchen daher kein einzelnes apt/winetricks mehr.
- **Pterodactyl-Egg** (`egg/egg-icarus--dedicated.json`) das auf dieses Image zeigt und alle relevanten Variablen exponiert.
- **GitHub Actions** bauen das Image bei jedem Push automatisch nach `ghcr.io/pavl21/icarus-dedicated`.

> Game-Files (`Icarus/Binaries/Win64/...`) werden NICHT in das Image gebacken — sie kommen weiterhin live von Steam ueber SteamCMD. So bleibt das Image klein und nie veraltet.

---

## Bilder & Tags

| Tag                                            | Wann veröffentlicht                                | Empfohlen für        |
| ---------------------------------------------- | --------------------------------------------------- | -------------------- |
| `ghcr.io/pavl21/icarus-dedicated:latest`       | Jeder Push auf `main`                              | Quick start          |
| `ghcr.io/pavl21/icarus-dedicated:v1`           | Rolling-Alias des aktuellen Major auf `main`       | Egg-Pin              |
| `ghcr.io/pavl21/icarus-dedicated:v1.2.3`       | Wenn Git-Tag `v1.2.3` gepusht wird                 | Production           |
| `ghcr.io/pavl21/icarus-dedicated:sha-<short>`  | Immer                                              | Forensik / Rollback  |

Das Egg pinnt sowohl `:latest` als auch `:v1`, damit Pterodactyl-Server-Admins ein stabiles Major behalten koennen, ohne dass `latest` ueberraschend rotiert.

---

## Was steckt im Image

- **Basis:** `ghcr.io/parkervcp/yolks:wine_latest`
  - Debian-stable
  - WineHQ (`wine`, kein `wine64`)
  - SteamCMD unter `/home/container/steamcmd`
  - Container-User `container` mit UID 988
- **Zusatz von uns:**
  - winetricks
  - Pre-built 64-bit Wine-Prefix unter `/opt/pavl21/wineprefix` mit `vcrun2022` + `corefonts`
  - eigene `entrypoint.sh` mit AUTO_UPDATE + Prefix-Seeding + verbosen Logs

### Prefix-Seeding-Logik

Beim ersten Boot kopiert `entrypoint.sh` `/opt/pavl21/wineprefix` nach `/home/container/.wine` (persistentes Volume). Bei jedem weiteren Boot wird der bestehende Prefix wiederverwendet — die Spielinstallation kann also Registry-Eintraege & Co. dauerhaft halten.

### Auto-Update

Standardmaessig laeuft beim Start:

```
steamcmd \
  +@sSteamCmdForcePlatformType windows \
  +force_install_dir /home/container \
  +login anonymous \
  +app_update 2089300 validate \
  +quit
```

Der Platform-Override muss zuerst kommen, sonst zieht SteamCMD den (nicht existierenden) Linux-Build. Abschalten mit Egg-Variable `AUTO_UPDATE=0`.

---

## Egg importieren

1. In Pterodactyl-Admin: **Nests → Create Nest** "pavl21" (falls noch nicht da).
2. **Eggs → Import Egg** und `egg/egg-icarus--dedicated.json` hochladen, Nest = pavl21.
3. Server anlegen → Egg "Icarus Dedicated" waehlen.
4. Variablen pruefen:

| Variable      | Default              | Beschreibung                          |
| ------------- | -------------------- | ------------------------------------- |
| `SERVER_NAME` | `Icarus by pavl21`   | Anzeigename im Steam-Server-Browser   |
| `SERVER_PORT` | `17777`              | Game-Port (UDP)                       |
| `QUERY_PORT`  | `27015`              | Steam-Query-Port (UDP)                |
| `AUTO_UPDATE` | `1`                  | SteamCMD-Update bei jedem Start       |
| `SRCDS_APPID` | `2089300`            | Icarus Dedicated AppID — nicht aendern |

Beide Ports muessen im Wings-Allocation-Setup als UDP belegt sein.

### Startup-Kommando (im Egg vorbelegt)

```
wine ./Icarus/Binaries/Win64/IcarusServer-Win64-Shipping.exe -Log \
     -SteamServerName="${SERVER_NAME}" \
     -PORT=${SERVER_PORT} \
     -QueryPort=${QUERY_PORT}
```

Done-Detection: `"(Engine Initialization) Total time:"`.

---

## Build & Release

Bauen passiert in GitHub Actions, siehe `.github/workflows/build.yml`. Trigger:

- Push auf `main` → `:latest`, `:v1`, `:sha-...`
- Git-Tag `vX.Y.Z` → zusaetzlich `:vX.Y.Z`
- Pull Request → Buildet nur (kein Push), als Smoke-Test
- `workflow_dispatch` → manuell

Lokales Bauen ist nicht vorgesehen — das Image wird CI-only gepflegt, damit Hashes reproduzierbar bleiben.

---

## Lizenz

MIT, siehe [`LICENSE`](LICENSE).

Icarus ist ein Spiel von RocketWerkz / Dean Hall — diese Repo enthaelt KEINE Game-Files, sondern nur Build-Konfiguration fuer einen Dedicated-Server-Wrapper.

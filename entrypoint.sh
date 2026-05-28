#!/bin/bash
# ---------------------------------------------------------------------------
# pavl21/icarus-dedicated — entrypoint
# ---------------------------------------------------------------------------
# Pterodactyl-compatible: expects the wings daemon to set ${STARTUP} with
# placeholders like "{{SERVER_NAME}}" already substituted from egg variables.
# This script:
#   1. Seeds a pre-built Wine prefix (vcrun2022 + corefonts) into the
#      persistent server volume if the user has not got one yet.
#   2. Runs SteamCMD with the Windows platform override to update Icarus
#      to the latest version (skip with AUTO_UPDATE=0).
#   3. Expands wings-style {{VAR}} placeholders to ${VAR} and execs the
#      result as the container PID 1 of the game.
# ---------------------------------------------------------------------------

set -eo pipefail

cd /home/container || { echo "[pavl21] FATAL: /home/container missing"; exit 1; }

# ---- Knobs (egg variables) -----------------------------------------------
AUTO_UPDATE="${AUTO_UPDATE:-1}"
SRCDS_APPID="${SRCDS_APPID:-2089300}"

# ---- Wine prefix bootstrap ------------------------------------------------
# /home/container/.wine is on the persistent server volume so we only copy
# the seed once. Subsequent boots reuse whatever the user / game wrote.
if [ ! -d "${HOME}/.wine" ]; then
    if [ -d "${PAVL21_PREFIX_SEED:-/opt/pavl21/wineprefix}" ]; then
        echo "[pavl21] Seeding Wine prefix -> ${HOME}/.wine"
        cp -a "${PAVL21_PREFIX_SEED:-/opt/pavl21/wineprefix}" "${HOME}/.wine"
    else
        echo "[pavl21] WARN: no seed prefix found at ${PAVL21_PREFIX_SEED}; wine will lazy-init"
    fi
fi
export WINEPREFIX="${HOME}/.wine"
export WINEARCH="${WINEARCH:-win64}"
export WINEDEBUG="${WINEDEBUG:--all}"
export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-mscoree=;mshtml=}"

# ---- SteamCMD auto-update ------------------------------------------------
# Platform override MUST come BEFORE force_install_dir / login, otherwise
# SteamCMD ignores it and pulls the Linux build (which Icarus does not
# publish a dedicated server for).
if [ "${AUTO_UPDATE}" = "1" ]; then
    echo "[pavl21] SteamCMD update — AppID ${SRCDS_APPID}"
    /home/container/steamcmd/steamcmd.sh \
        +@sSteamCmdForcePlatformType windows \
        +force_install_dir /home/container \
        +login anonymous \
        +app_update "${SRCDS_APPID}" validate \
        +quit
else
    echo "[pavl21] AUTO_UPDATE=0 — skipping SteamCMD update"
fi

# ---- Display effective Wine version for diagnostics ----------------------
echo "[pavl21] $(wine --version 2>/dev/null || echo 'wine: unavailable')"

# ---- Run the actual startup command --------------------------------------
# Wings substitutes {{FOO}} on its side most of the time, but legacy eggs
# sometimes still send raw {{FOO}}. This sed pass handles both, then eval
# expands ${FOO} from the env wings sets per egg variable.
MODIFIED_STARTUP=$(echo -e "${STARTUP}" | sed -e 's/{{/${/g' -e 's/}}/}/g')
echo "[pavl21] Executing: ${MODIFIED_STARTUP}"

# shellcheck disable=SC2086
eval exec ${MODIFIED_STARTUP}

#!/bin/bash
# ---------------------------------------------------------------------------
# pavl21/icarus-dedicated — entrypoint
# ---------------------------------------------------------------------------
# Pterodactyl-compatible: wings passes the egg startup command via ${STARTUP}
# with {{VAR}} placeholders already substituted from the egg variables. This
# script:
#   1. Initializes the Wine prefix on first boot (~/.wine).
#   2. Lazy-seeds the prefix with vcrun2022 + corefonts on first boot,
#      writing a marker file so subsequent restarts skip the seed.
#   3. Runs the SteamCMD Windows-platform update for Icarus (skip with
#      AUTO_UPDATE=0).
#   4. Expands {{VAR}} -> ${VAR} placeholders and execs the game.
# ---------------------------------------------------------------------------

set -eo pipefail

cd /home/container || { echo "[pavl21] FATAL: /home/container missing"; exit 1; }

# Wings does not always export HOME for the egg-defined container user, so
# fall back to /home/container explicitly. Without this, WINEPREFIX would
# resolve to "/.wine" and wineboot would fail with
# `wine: chdir to /.wine : No such file or directory`.
export HOME="${HOME:-/home/container}"

# ---- Knobs (egg variables) -----------------------------------------------
AUTO_UPDATE="${AUTO_UPDATE:-1}"
SRCDS_APPID="${SRCDS_APPID:-2089300}"

export WINEPREFIX="${HOME}/.wine"
export WINEARCH="${WINEARCH:-win64}"
export WINEDEBUG="${WINEDEBUG:--all}"
export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-mscoree=;mshtml=}"
export W_OPT_UNATTENDED="${W_OPT_UNATTENDED:-1}"
export WINETRICKS_GUI="${WINETRICKS_GUI:-none}"

# Wine refuses to bootstrap into a directory it cannot enter; on some wings
# mount layouts the auto-create inside wineboot races with the parent mount
# and fails. Creating the prefix dir up front avoids that race.
mkdir -p "${WINEPREFIX}"

SEED_MARKER="${WINEPREFIX}/.pavl21_seeded"

# ---- One-time prefix seeding ---------------------------------------------
# Runs winetricks under a short-lived Xvfb, then explicitly tears Wine down
# with `wineserver -k` so no orphaned wineserver process keeps the volume
# busy. wineserver -k is non-blocking, unlike -w (which previously deadlocked
# the CI image build).
if [ ! -f "${SEED_MARKER}" ]; then
    echo "[pavl21] First boot — seeding Wine prefix at ${WINEPREFIX}"

    # `wineboot --init` creates the prefix structure. xvfb-run terminates
    # Xvfb when the wrapped command exits, which is fine because we kill
    # wineserver right after.
    xvfb-run -a -s "-screen 0 1024x768x24" wineboot --init || {
        echo "[pavl21] wineboot init failed — aborting seed";
        wineserver -k 2>/dev/null || true;
        exit 1;
    }
    wineserver -k 2>/dev/null || true

    # corefonts: tiny, no installer dialogs, ~30s.
    if ! xvfb-run -a -s "-screen 0 1024x768x24" \
            winetricks -q --force --no-isolate --optout corefonts; then
        echo "[pavl21] WARN: corefonts seed failed, continuing"
    fi
    wineserver -k 2>/dev/null || true

    # vcrun2022: ~1-3 min, may stall on first attempt under some Wine
    # versions; failures are non-fatal because Icarus may still boot.
    if ! xvfb-run -a -s "-screen 0 1024x768x24" \
            winetricks -q --force --no-isolate --optout vcrun2022; then
        echo "[pavl21] WARN: vcrun2022 seed failed, continuing"
    fi
    wineserver -k 2>/dev/null || true

    touch "${SEED_MARKER}"
    echo "[pavl21] Seed complete"
else
    echo "[pavl21] Prefix already seeded (${SEED_MARKER})"
fi

# ---- SteamCMD auto-update ------------------------------------------------
# Platform override MUST come BEFORE force_install_dir / login, otherwise
# SteamCMD silently falls back to the Linux build (which Icarus does not
# ship as a dedicated server).
if [ "${AUTO_UPDATE}" = "1" ]; then
    echo "[pavl21] SteamCMD update — AppID ${SRCDS_APPID}"
    # app_license_request is required for some anonymous AppIDs (Icarus DS
    # included): without it, SteamCMD aborts with "state is 0x202 after
    # update job" even though the metadata fetch succeeds.
    /home/container/steamcmd/steamcmd.sh \
        +@sSteamCmdForcePlatformType windows \
        +@NoPromptForPassword 1 \
        +force_install_dir /home/container \
        +login anonymous \
        +app_license_request "${SRCDS_APPID}" \
        +app_update "${SRCDS_APPID}" validate \
        +quit
else
    echo "[pavl21] AUTO_UPDATE=0 — skipping SteamCMD update"
fi

echo "[pavl21] $(wine --version 2>/dev/null || echo 'wine: unavailable')"

# ---- Run actual startup command ------------------------------------------
MODIFIED_STARTUP=$(echo -e "${STARTUP}" | sed -e 's/{{/${/g' -e 's/}}/}/g')
echo "[pavl21] Executing: ${MODIFIED_STARTUP}"

# shellcheck disable=SC2086
eval exec ${MODIFIED_STARTUP}

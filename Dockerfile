# ---------------------------------------------------------------------------
# pavl21/icarus-dedicated
# ---------------------------------------------------------------------------
# Pterodactyl-compatible "yolks"-style image for the Icarus Dedicated Server
# (Steam AppID 2089300).
#
# Strategy:
#   - Base on parkervcp/yolks wine image (already ships: Debian + WineHQ +
#     SteamCMD + Pterodactyl-conventions uid 988 / /home/container).
#   - Bake a pre-seeded 64-bit Wine prefix with vcrun2022 + corefonts so that
#     Icarus does NOT pull these on every install or restart.
#   - Game files themselves still ship via SteamCMD, so the game version is
#     never frozen into the image. SteamCMD update runs at server boot when
#     AUTO_UPDATE=1 (default).
#
# Out: ghcr.io/pavl21/icarus-dedicated:<tag>
# ---------------------------------------------------------------------------

# wine_staging = WineHQ staging tree maintained by parkervcp/yolks.
# Picked over :wine_latest because staging tends to handle winetricks /
# vcrun installers without spawning blocking dialogs under Xvfb.
FROM ghcr.io/parkervcp/yolks:wine_staging

LABEL org.opencontainers.image.source="https://github.com/pavl21/icarus-dedicated"
LABEL org.opencontainers.image.title="Icarus Dedicated (pavl21)"
LABEL org.opencontainers.image.description="Pterodactyl egg base image for Icarus dedicated servers. Wine + SteamCMD + pre-seeded wineprefix (vcrun2022, corefonts)."
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.vendor="pavl21"

# Wine prefix lives outside /home/container because /home/container is the
# Pterodactyl-managed server volume and would shadow anything we bake in.
# /entrypoint copies this prefix to ~/.wine on first run, so users get a
# clean seeded prefix but can still persist changes.
ENV WINEARCH=win64 \
    WINEDEBUG=-all \
    WINEDLLOVERRIDES="mscoree=;mshtml=" \
    PAVL21_PREFIX_SEED=/opt/pavl21/wineprefix \
    W_OPT_UNATTENDED=1 \
    WINETRICKS_GUI=none \
    DISPLAY=:99

# --- Seed Wine prefix as the unprivileged container user ------------------
# We need Xvfb because some MS redistributables spawn install dialogs even
# with W_OPT_UNATTENDED=1, and Wine refuses to draw without an X server.
# Every winetricks call is wrapped in `timeout` so a hung installer fails
# the CI build instead of dragging it out to the 6h job ceiling.
USER root
RUN apt-get update \
 && apt-get install -y --no-install-recommends xvfb cabextract coreutils \
 && rm -rf /var/lib/apt/lists/* \
 && mkdir -p ${PAVL21_PREFIX_SEED} \
 && chown -R container:container ${PAVL21_PREFIX_SEED} \
 && curl -fsSL https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks \
        -o /usr/local/bin/winetricks \
 && chmod +x /usr/local/bin/winetricks \
 && winetricks --version

USER container

# Step 1: initialize prefix only (cheap, ~30s). If this hangs we know
# the base Wine image itself is broken, not our verbs.
RUN set -eux; \
    export WINEPREFIX=${PAVL21_PREFIX_SEED} WINEARCH=win64; \
    timeout 180 xvfb-run -a -s "-screen 0 1024x768x24" wineboot --init; \
    wineserver -w

# Step 2: corefonts — small, no installer dialogs, ~30s.
RUN set -eux; \
    export WINEPREFIX=${PAVL21_PREFIX_SEED}; \
    timeout 300 xvfb-run -a -s "-screen 0 1024x768x24" \
        winetricks -q --force --no-isolate --optout corefonts; \
    wineserver -w

# Step 3: vcrun2022 — the historically slow / dialog-prone verb. Verbose
# output (-v) is on so CI logs show where it stalls if it stalls.
RUN set -eux; \
    export WINEPREFIX=${PAVL21_PREFIX_SEED}; \
    timeout 900 xvfb-run -a -s "-screen 0 1024x768x24" \
        winetricks -v -q --force --no-isolate --optout vcrun2022; \
    wineserver -w

USER root

# --- Override entrypoint with the pavl21 variant ---------------------------
# The yolks base ships its own /entrypoint.sh; ours adds explicit logging,
# seeds the wineprefix into /home/container/.wine on first boot, and runs
# the AUTO_UPDATE SteamCMD pass with Icarus-specific platform override.
COPY --chown=container:container entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Game / Steam-query ports. Pterodactyl handles publish at the wings layer;
# these are informational so the image is also runnable standalone.
EXPOSE 17777/udp 27015/udp

USER container
WORKDIR /home/container

# SIGINT = clean shutdown for IcarusServer-Win64-Shipping (matches egg stop).
STOPSIGNAL SIGINT
ENTRYPOINT ["/usr/bin/tini", "-g", "--", "/entrypoint.sh"]

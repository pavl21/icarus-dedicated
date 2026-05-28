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

# wine_latest = current stable WineHQ build maintained by parkervcp/yolks.
# Switch to :wine_staging (or pin a SHA) if you need a different Wine branch.
FROM ghcr.io/parkervcp/yolks:wine_latest

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
    PAVL21_PREFIX_SEED=/opt/pavl21/wineprefix

# --- Seed Wine prefix as the unprivileged container user ------------------
# We need xvfb to run winetricks unattended (some installers spawn dialogs
# even with -q). vcrun2022 + corefonts is what Icarus expects at runtime.
USER root
RUN apt-get update \
 && apt-get install -y --no-install-recommends xvfb cabextract \
 && rm -rf /var/lib/apt/lists/* \
 && mkdir -p ${PAVL21_PREFIX_SEED} \
 && chown -R container:container ${PAVL21_PREFIX_SEED} \
 && curl -fsSL https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks \
        -o /usr/local/bin/winetricks \
 && chmod +x /usr/local/bin/winetricks

USER container
RUN WINEPREFIX=${PAVL21_PREFIX_SEED} WINEARCH=win64 \
        xvfb-run -a wineboot --init \
 && WINEPREFIX=${PAVL21_PREFIX_SEED} \
        xvfb-run -a winetricks -q --unattended vcrun2022 corefonts \
 && WINEPREFIX=${PAVL21_PREFIX_SEED} wineserver -w
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

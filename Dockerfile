# ---------------------------------------------------------------------------
# pavl21/icarus-dedicated
# ---------------------------------------------------------------------------
# Pterodactyl yolks-style image for Icarus Dedicated Server (Steam AppID 2089300).
#
# Strategy:
#   - Base on parkervcp/yolks:wine_staging (Wine + SteamCMD + container user
#     uid 988 already in place).
#   - Add winetricks + Xvfb so the image can lazily install vcrun2022 and
#     corefonts into the persistent wineprefix on first run.
#   - Game files come from Steam at install/runtime, so the image is small
#     and never frozen to a game version.
#
# Why lazy seed instead of pre-bake:
#   Pre-baking the wineprefix at build time means running winetricks under
#   xvfb-run inside Docker. wineserver cleanup deadlocks once Xvfb exits,
#   which previously locked the CI build into the 6h job ceiling. Doing the
#   same work at runtime (under tini, with a real PID 1) is reliable and
#   only costs ~2 minutes on the first server start. Subsequent restarts
#   reuse the seeded prefix on the persistent volume.
# ---------------------------------------------------------------------------

FROM ghcr.io/parkervcp/yolks:wine_staging

LABEL org.opencontainers.image.source="https://github.com/pavl21/icarus-dedicated"
LABEL org.opencontainers.image.title="Icarus Dedicated (pavl21)"
LABEL org.opencontainers.image.description="Pterodactyl yolks-style image for Icarus dedicated servers. Wine + SteamCMD + lazy winetricks seed (vcrun2022, corefonts)."
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.vendor="pavl21"

ENV WINEARCH=win64 \
    WINEDEBUG=-all \
    WINEDLLOVERRIDES="mscoree=;mshtml=" \
    W_OPT_UNATTENDED=1 \
    WINETRICKS_GUI=none

USER root
RUN apt-get update \
 && apt-get install -y --no-install-recommends xvfb cabextract \
 && rm -rf /var/lib/apt/lists/* \
 && curl -fsSL https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks \
        -o /usr/local/bin/winetricks \
 && chmod +x /usr/local/bin/winetricks \
 && winetricks --version

COPY --chown=container:container entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 17777/udp 27015/udp

USER container
WORKDIR /home/container

STOPSIGNAL SIGINT
ENTRYPOINT ["/usr/bin/tini", "-g", "--", "/entrypoint.sh"]

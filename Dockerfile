#kcc
FROM ubuntu:noble AS kcc_builder
RUN set -x && \
    BUILD_DEPS="build-essential git cmake libffi-dev libfreetype6-dev libfontconfig1-dev libpng-dev libjpeg-dev libssl-dev libxft-dev make python3 python3-dev python3-venv" && \
    DEBIAN_FRONTEND=noninteractive apt-get update -y && \
    apt-get install -y --no-install-recommends ${BUILD_DEPS}


RUN set -x && \
    python3 -m venv /opt/venv && \
    . /opt/venv/bin/activate && \
    pip install --upgrade pip

RUN set -x && \
    . /opt/venv/bin/activate && \
    pip install --no-cache-dir numpy==2.3.4

RUN set -x && \
    . /opt/venv/bin/activate && \
    pip install --no-cache-dir PyMuPDF==1.26.6

# KCC only imports QtCore/QtGui/QtWidgets/QtNetwork, which all live in
# PySide6-Essentials; the full PySide6 metapackage adds the Addons wheels
# (QtWebEngine, Qt3D, QtCharts, ...) we never load. Same 6.12.0 version.
RUN set -x && \
    . /opt/venv/bin/activate && \
    pip install --no-cache-dir PySide6-Essentials==6.12.0

# Shallow clone: we only need the working tree, not KCC's history, and
# dropping .git saves ~38 MB in the image.
RUN git clone --depth 1 https://github.com/nigeldixon/kcc.git && \
    rm -rf kcc/.git

RUN set -x && \
    . /opt/venv/bin/activate && \
    pip install "pip @ https://files.pythonhosted.org/packages/3f/06/3e4420302363fbb71be3c7f35ce042f54bfca330e3e66b3a2e3c4cca579f/pip-26.2.2-py3-none-any.whl#sha256=fd7f4dfa8190e014013b9f08f3e973f4e4c26ffd179a204895533a7254813a70" && \
    pip install --no-cache-dir -r kcc/requirements-docker.txt

FROM ubuntu:noble

COPY --from=kcc_builder /opt/venv /opt/kcc_venv
COPY --from=kcc_builder kcc /opt/kcc

ARG TARGETARCH
ARG DEBIAN_FRONTEND=noninteractive
ARG DEBCONF_NOWARNINGS=yes

ENV VIRTUAL_ENV=/opt/venv
ENV PATH="$VIRTUAL_ENV/bin:$PATH"
ENV CALIBRE_DBPATH=/config
ENV KCC_WATCH_ENABLED=true

EXPOSE 8083

VOLUME /config
VOLUME /books
VOLUME /c2e_comics
VOLUME /c2e_manga
VOLUME /calibredrop

COPY scripts/ /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh /usr/local/bin/kcc_watch.py

WORKDIR /app/calibre-web

ENTRYPOINT ["/usr/bin/tini", "-g", "--", "/usr/local/bin/docker-entrypoint.sh"]
CMD ["python3", "cps.py"]

RUN \
  apt-get -q update && \
  echo "**** BUILD DEPS ****" && \
  apt-get -q install -y --no-install-recommends \
    build-essential \
    curl \
    libldap2-dev \
    libsasl2-dev \
    python3-dev \
    sed \
    && \
  echo "[[ DONE ]]" && \
  echo "**** RUNTIME DEPS ****" && \
  apt-get -q install -y --no-install-recommends \
    ca-certificates \
    dbus \
    fcitx-rime \
    fonts-wqy-microhei \
    inotify-tools \
    libfontconfig1 \
    libfreetype6 \
    libgl1 \
    libmagic1 \
    libnss3 \
    libopengl0 \
    p7zip-full \
    libqpdf29t64 \
    libxkbcommon-x11-0 \
    libxcb-cursor0 \
    libxcb-icccm4 \
    libxcb-image0 \
    libxcb-keysyms1 \
    libxcb-randr0 \
    libxcb-render-util0 \
    libxcb-xinerama0 \
    poppler-utils \
    python3 \
    python3-venv \
    python3-xdg \
    tini \
    ttf-wqy-zenhei \
    xz-utils \
    && \
  echo "[[ DONE ]]" && \
  echo "**** PREPARE DROP FOLDERS ****" && \
  mkdir -p /c2e_comics /c2e_manga /calibredrop && \
  echo "[[ DONE ]]" && \
  echo "**** INSTALL CALIBRE ****" && \
  mkdir -p /app/calibre && \
  curl -fL --retry 3 -o \
    /tmp/calibre.txz \
    "https://calibre-ebook.com/dist/linux-$(echo "$TARGETARCH" | sed "s/amd64/x86_64/")" && \
  tar xf \
    /tmp/calibre.txz \
    -C /app/calibre && \
  echo "[[ DONE ]]" && \
  echo "**** INSTALL KEPUBIFY ****" && \
  curl -fL --retry 3 -o \
    /usr/bin/kepubify \
    "https://github.com/pgaskin/kepubify/releases/latest/download/kepubify-linux-$(echo "$TARGETARCH" | sed "s/amd64/64bit/")" && \
  chmod +x /usr/bin/kepubify && \
  echo "[[ DONE ]]" && \
  echo "**** INSTALL CALIBRE-WEB ****" && \
  CALIBREWEB_REF="${CALIBREWEB_REF:-develop}" && \
  curl -fL --retry 3 -o \
    /tmp/calibre-web.tar.gz \
    "https://github.com/nigeldixon/calibre-web/archive/refs/heads/${CALIBREWEB_REF}.tar.gz" && \
  mkdir -p \
    /app/calibre-web && \
  tar xf \
    /tmp/calibre-web.tar.gz -C \
    /app/calibre-web --strip-components=1 && \
  cd /app/calibre-web && \
  python3 -m venv $VIRTUAL_ENV && \
  pip install --no-cache-dir \
    pip \
    wheel \
    && \
  pip install --no-cache-dir --find-links https://wheel-index.linuxserver.io/ubuntu/ -r \
    requirements.txt -r \
    optional-requirements.txt && \
  echo "[[ DONE ]]" && \
  echo "**** INSTALL KCC WRAPPERS ****" && \
  printf '#!/bin/sh\nexec /opt/kcc_venv/bin/python3 /opt/kcc/kcc-c2e.py "$@"\n' > /usr/local/bin/kcc-c2e && \
  printf '#!/bin/sh\nexec /opt/kcc_venv/bin/python3 /opt/kcc/kcc-c2p.py "$@"\n' > /usr/local/bin/kcc-c2p && \
  chmod +x /usr/local/bin/kcc-c2e /usr/local/bin/kcc-c2p && \
  echo "[[ DONE ]]" && \
  echo "**** cleanup ****" && \
  apt-get -y purge \
    build-essential \
    curl \
    libldap2-dev \
    libsasl2-dev \
    python3-dev \
    && \
  apt-get -y autoremove && \
  rm -rf \
    /tmp/* \
    /var/lib/apt/lists/* \
    /var/tmp/* \
    /root/.cache

# The KCC entry points carry `#!/usr/bin/env python3`, but python3 on PATH is
# calibre-web's venv (/opt/venv), which has no PySide6, so running them
# directly fails. Point them at the KCC venv instead.
RUN sed -i '1{/^#!/s|.*|#!/opt/kcc_venv/bin/python3|}' \
        /opt/kcc/kcc-c2e.py /opt/kcc/kcc-c2p.py /opt/kcc/kcc.py && \
    for f in /opt/kcc/kcc-c2e.py /opt/kcc/kcc-c2p.py /opt/kcc/kcc.py; do \
        head -1 "$f" | grep -q '^#!/opt/kcc_venv/bin/python3$' || { \
            echo "shebang not fixed: $f"; exit 1; }; \
    done




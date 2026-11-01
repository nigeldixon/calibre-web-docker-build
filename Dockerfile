#kcc
FROM python:3.13-slim-bookworm AS kcc_builder
RUN set -x && \
    BUILD_DEPS="build-essential git cmake libffi-dev libfreetype6-dev libfontconfig1-dev libpng-dev libjpeg-dev libssl-dev libxft-dev make python3-dev" && \
    RUNTIME_DEPS="bash ca-certificates chrpath locales locales-all libfreetype6 libfontconfig1 p7zip-full python3 python3-pip libgl1" && \
    DEBIAN_FRONTEND=noninteractive apt-get update -y && \
    DEBIAN_FRONTENT=noninteractive  apt-get install -y --no-install-recommends ${BUILD_DEPS} git


RUN set -x && \
    python -m venv /opt/venv && \
    . /opt/venv/bin/activate && \
    pip install --upgrade pip

RUN set -x && \
    . /opt/venv/bin/activate && \
    pip install --no-cache-dir numpy==2.3.4

RUN set -x && \
    . /opt/venv/bin/activate && \
    pip install --no-cache-dir PyMuPDF==1.26.6

RUN git clone https://github.com/nigeldixon/kcc.git

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
ENV KCC_VIRTUAL_ENV=/opt/kcc_venv
ENV PATH="$VIRTUAL_ENV/bin:$KCC_VIRTUAL_ENV/bin:$PATH"
ENV CALIBRE_DBPATH=/config
#ENV PYTHONPATH="$VIRTUAL_ENV:$PYTHONPATH"

EXPOSE 8083

VOLUME /config
VOLUME /books

WORKDIR /app/calibre-web

ENTRYPOINT ["python3", "cps.py"]

RUN \
  apt-get -q update && \
  echo "**** BUILD DEPS ****" && \
  apt-get -q install -y --no-install-recommends \
    build-essential \
    curl \
    gawk \
    libldap2-dev \
    libsasl2-dev \
    python3-dev \
    sed \
    jq \
    && \
  echo "[[ DONE ]]" && \
  echo "**** RUNTIME DEPS ****" && \
  apt-get -q install -y --no-install-recommends \
    ca-certificates \
    dbus \
    fcitx-rime \
    fonts-wqy-microhei \
    libmagic1 \
    libnss3 \
    libopengl0 \
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
    ttf-wqy-zenhei \
    wget \
    xz-utils \
    && \
  echo "[[ DONE ]]" && \
  echo "**** INSTALL CALIBRE ****" && \
  if [ -z ${CALIBRE_RELEASE+x} ]; then \
    CALIBRE_RELEASE=$(curl -sX GET "https://api.github.com/repos/kovidgoyal/calibre/releases/latest" \
    | jq -r .tag_name); \
  fi && \
  CALIBRE_VERSION="$(echo ${CALIBRE_RELEASE} | cut -c2-)" && \ 
  mkdir -p /app/calibre && \
  curl -o \
    /tmp/calibre.txz -L \
    "https://download.calibre-ebook.com/${CALIBRE_VERSION}/calibre-${CALIBRE_VERSION}-$(echo "$TARGETARCH" | sed "s/amd/x86_/").txz" && \
  tar xf \
    /tmp/calibre.txz \
    -C /app/calibre && \
  echo "[[ DONE ]]" && \
  echo "**** INSTALL KEPUBIFY ****" && \
  if [ -z ${KEPUBIFY_RELEASE+x} ]; then \
    KEPUBIFY_RELEASE=$(curl -sX GET "https://api.github.com/repos/pgaskin/kepubify/releases/latest" \
    | awk '/tag_name/{print $4;exit}' FS='[""]'); \
  fi && \
  curl -v -o \
    /usr/bin/kepubify -L \
    https://github.com/pgaskin/kepubify/releases/download/${KEPUBIFY_RELEASE}/kepubify-linux-$(echo "$TARGETARCH" | sed "s/amd64/64bit/") && \
  chmod +x /usr/bin/kepubify && \
  echo "[[ DONE ]]" && \
  echo "**** INSTALL CALIBRE-WEB ****" && \
  if [ -z ${CALIBREWEB_RELEASE+x} ]; then \
    CALIBREWEB_RELEASE=$(curl -sX GET "https://api.github.com/repos/janeczku/calibre-web/releases/latest" \
    | awk '/tag_name/{print $4;exit}' FS='[""]'); \
  fi && \
  curl -o \
    /tmp/calibre-web.tar.gz -L \
    https://github.com/janeczku/calibre-web/archive/${CALIBREWEB_RELEASE}.tar.gz && \
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




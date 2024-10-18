FROM ubuntu:noble

ENV VIRTUAL_ENV=/opt/venv
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

RUN \
  apt-get update && \
  echo "**** build dependencies ****" && \
  apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    libldap2-dev \
    libsasl2-dev \
    pipx \
    python3-dev \
     && \
  echo "**** runtime dependencies ****" && \
  apt-get install -y --no-install-recommends \
    imagemagick \
    ghostscript \
    libldap2 \
    libmagic1 \
    libsasl2-2 \
    libxi6 \
    libxslt1.1 \
    python3-full \
    unrar \
    xdg-utils && \
  echo "**** install CALIBRE ****" && \
  echo "**** install CALIBRE-WEB ****" && \
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
  python3 -m venv .venv && \
  source ./.venv/bin/activate && \
  pip install -U --no-cache-dir \
    pip \
    wheel && \
  pip install -U --no-cache-dir --find-links https://wheel-index.linuxserver.io/ubuntu/ -r \
    requirements.txt -r \
    optional-requirements.txt && \
  echo "**** install KEPUBIFY ****" && \
  if [ -z ${KEPUBIFY_RELEASE+x} ]; then \
    KEPUBIFY_RELEASE=$(curl -sX GET "https://api.github.com/repos/pgaskin/kepubify/releases/latest" \
    | awk '/tag_name/{print $4;exit}' FS='[""]'); \
  fi && \
  curl -o \
    /usr/bin/kepubify -L \
    https://github.com/pgaskin/kepubify/releases/download/${KEPUBIFY_RELEASE}/kepubify-linux-${TARGETARCH} && \
  echo "**** cleanup ****" && \
  apt-get -y purge \
    build-essentials \
    libldap2-dev \
    libsasl2-dev \
    python3-dev && \
  apt-get -y autoremove && \
  rm -rf \
    /tmp/* \
    /var/lib/apt/lists/* \
    /var/tmp/* \
    /root/.cache
    
EXPOSE 8083

VOLUME /config
VOLUME /books

WORKDIR /app/calibre-web

ENTRYPOINT ["python", "cps.py"]

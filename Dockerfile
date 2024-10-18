FROM ubuntu:noble

ENV VIRTUAL_ENV=/opt/venv
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

ARG TARGETOS
ARG TARGETARCH
ARG BUILDPLATFORM
ARG TARGETPLATFORM

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
    xdg-utils \
    xz-utils \
    && \
  echo "**** install CALIBRE ****" && \
  CALIBRE_RELEASE=$(curl -sX GET "https://api.github.com/repos/kovidgoyal/calibre/releases/latest" \
	 | awk '/tag_name/{print $4;exit}' FS='[""]' | sed 's/^v//g' ) && \ 
  CALIBRE_VERSION="$(echo ${CALIBRE_RELEASE} | cut -c2-)" && \
  mkdir -p /app/calibre

EXPOSE 8083

VOLUME /config
VOLUME /books

WORKDIR /app/calibre-web

ENTRYPOINT ["python", "cps.py"]

FROM alpine:20240606

WORKDIR /app/calibre-web
ENV PATH="/opt/venv/bin:$PATH"

RUN apk add --no-cache \
        build-base \
        linux-headers \
        openldap-dev \
        python3-dev \
        py3-pip \
 && curl -o \
        /tmp/calibre-web.tar.gz -L \
        https://github.com/${{ github.repository_owner }}/calibre-web/archive/develop.tar.gz \
 && mkdir -p \
        /app/calibre-web \
 && tar xf \
        /tmp/calibre-web.tar.gz -C \
        /app/calibre-web --strip-components=1 \
 && cd /app/calibre-web \
 && mkdir -p \
        /app/calibre-web \
 && tar xf \
        /tmp/calibre-web.tar.gz -C \
        /app/calibre-web --strip-components=1 \
 && cd /app/calibre-web \
 && python -m venv /opt/venv \
 && pip install -r requirements.txt optional-requirements.txt \
 && apk del \
        build-base \
        linux-headers \
        openldap-dev \
        python3-dev \
        py3-pip \
 && apk add --no-cache \
        ghostscript \
        imagemagick \
        libldap \
        libsasl \
        python3

EXPOSE 8083
VOLUME /config

ENTRYPOINT ["python", "cps.py"]

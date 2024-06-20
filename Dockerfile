FROM alpine:20240606

COPY ["cps.py", "requirements.txt", "optional-requirements.txt", "/app/calibre-web/"]
COPY ["cps/", "/app/calibre-web/cps"]

WORKDIR /app/calibre-web
ENV PATH="/opt/venv/bin:$PATH"

RUN apk add --no-cache \
        build-base \
        linux-headers \
        openldap-dev \
        python3-dev \
        py3-pip \
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

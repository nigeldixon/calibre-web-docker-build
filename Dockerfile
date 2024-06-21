FROM --platform=$BUILDPLATFORM alpine:20240606

WORKDIR /app/calibre-web
ENV PATH="/opt/venv/bin:$PATH"

ARG TARGETOS
ARG TARGETARCH

RUN apk add --no-cache \
        build-base \
        curl \
        linux-headers \
        openldap-dev \
        python3-dev \
        py3-pip \
 && curl -o \
        /tmp/calibre-web.tar.gz -L \
        https://github.com/nigeldixon/calibre-web/archive/develop.tar.gz \
 && if [ -z ${KEPUBIFY_RELEASE+x} ]; then \
        KEPUBIFY_RELEASE=$(curl -sX GET "https://api.github.com/repos/pgaskin/kepubify/releases/latest" \
        | awk '/tag_name/{print $4;exit}' FS='[""]'); \
 fi \
 && curl -o \
        /usr/bin/kepublify -L \
        https://github.com/pgaskin/kepubify/releases/download/${KEPUBIFY_RELEASE}/kepubify-linux-${TARGETARCH} \
 && CALIBRE_RELEASE=$(curl -sX GET "https://api.github.com/repos/kovidgoyal/calibre/releases/latest" \
	| awk '/tag_name/{print $4;exit}' FS='[""]' | sed 's/^v//g' ) && \ 
 && curl -o \
	/tmp/calibre.txz -L \
	"https://github.com/kovidgoyal/calibre/releases/download/v${CALIBRE_RELEASE}/calibre-${CALIBRE_RELEASE}-${TARTGETARCH}.txz" \
 && mkdir -p \
        /app/calibre-web \
 && mkdir -p \
        /app/calibre \
 && tar xf \
        /tmp/calibre-web.tar.gz -C \
        /app/calibre-web --strip-components=1 \
 && tar xf \
	/tmp/calibre.txz \
	-C /root-layer/app/calibre \
        
 && mkdir -p \
        /app/calibre-web \
 && tar xf \
        /tmp/calibre-web.tar.gz -C \
        /app/calibre-web --strip-components=1 \
 && cd /app/calibre-web \
 && python -m venv /opt/venv \
 && pip install -r requirements.txt \
 && pip install -r optional-requirements.txt \
 && apk del \
        build-base \
        curl \
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

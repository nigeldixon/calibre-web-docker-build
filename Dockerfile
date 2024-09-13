FROM python:3.12-alpine


ENV VIRTUAL_ENV=/opt/venv
WORKDIR /app/calibre-web
ENV PATH="$VIRTUAL_ENV/bin:$PATH"
ENV PYTHONPATH="/usr/lib/python3.12/site-packages:$PYTHONPATH"

ENV CALIBRE_DBPATH=/config

ARG TARGETOS
ARG TARGETARCH
ARG BUILDPLATFORM
ARG TARGETPLATFORM
ARG GLIBCVERSION="2.40"
ARG GLIBPREFEIX="/usr/glibc-compat"

RUN apk add --no-cache \
        bison \
        build-base \
        curl \
	gcompat \
        gawk \
 	libstdc++ \
  	libgcc \
       	libffi-dev \
	#libxml2-dev \
        linux-headers \
	#musl-dev \
 	qt6-qtbase-devel \
 	qt6-qtwebengine \
  	qt6-qtsvg \
   	qt6-qtimageformats \
        openldap-dev \
 && apk add calibre --repository=https://dl-cdn.alpinelinux.org/alpine/edge/testing \
 #&& export PYTHONPATH=/usr/lib/python3.12/site-packages:$PYTHONPATH \
 #&& pip install apsw html5_parser msgpack pyQt6 \
 && curl -o \
        /tmp/calibre-web.tar.gz -L \
        https://github.com/nigeldixon/calibre-web/archive/develop.tar.gz \
 && if [ -z ${KEPUBIFY_RELEASE+x} ]; then \
        KEPUBIFY_RELEASE=$(curl -sX GET "https://api.github.com/repos/pgaskin/kepubify/releases/latest" \
        | awk '/tag_name/{print $4;exit}' FS='[""]'); \
 fi \
 && curl -o \
        /usr/bin/kepubify -L \
        https://github.com/pgaskin/kepubify/releases/download/${KEPUBIFY_RELEASE}/kepubify-linux-${TARGETARCH} \
 && chmod +x /usr/bin/kepubify \
 && CALIBRE_RELEASE=$(curl -sX GET "https://api.github.com/repos/kovidgoyal/calibre/releases/latest" \
	| awk '/tag_name/{print $4;exit}' FS='[""]' | sed 's/^v//g' ) \ 
 && mkdir -p \
        /app/calibre-web \
 && tar xf \
        /tmp/calibre-web.tar.gz -C \
        /app/calibre-web --strip-components=1 \
 && mkdir -p \
        /app/calibre-web \
 && tar xf \
        /tmp/calibre-web.tar.gz -C \
        /app/calibre-web --strip-components=1 \
 && cd /app/calibre-web \
# && python -m venv $VIRTUAL_ENV \
 && pip install --upgrade pip wheel \
 && pip install pipenv \
 && pip install --no-cache-dir -r requirements.txt -r optional-requirements.txt \
 && apk del \
        build-base \
        curl \
	libxml2-dev \
        linux-headers \
        openldap-dev \
	musl-dev \
 	qt6-qtbase-dev \
 && apk add --no-cache \
        ghostscript \
        imagemagick \
        libldap \
	libmagic \
        libsasl \
        musl

EXPOSE 8083
VOLUME /config
VOLUME /books

ENTRYPOINT ["python", "cps.py"]

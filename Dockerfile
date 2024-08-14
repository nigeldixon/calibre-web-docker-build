FROM python:3.8-alpine


ENV VIRTUAL_ENV=/opt/venv
WORKDIR /app/calibre-web
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

ENV CALIBRE_DBPATH=/config

ARG TARGETOS
ARG TARGETARCH
ARG BUILDPLATFORM
ARG TARGETPLATFORM


RUN apk add --no-cache \
        build-base \
        curl \
	gcompat \
 	libstdc++ \
  	libgcc \
       	libffi-dev \
        linux-headers \
	musl-dev \
        openldap-dev \
        python3-dev \
        py3-pip \
	wget \
&& wget -qO- "https://ftpmirror.gnu.org/libc/glibc-$version.tar.gz" \
			| tar zxf - \
&& mkdir -p /glibc-build && cd /glibc-build \
&& "/glibc-$version/configure" \
			--prefix="$prefix" \
			--libdir="$prefix/lib" \
			--libexecdir="$prefix/lib" \
			--enable-multi-arch \
			--enable-stack-protector=strong \	
 && make --jobs=4 && make install
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
 && CALIBRE_URL="https://download.calibre-ebook.com/${CALIBRE_RELEASE}/calibre-${CALIBRE_RELEASE}-arm64.txz" \
 && echo $CALIBRE_URL \
 && curl -o \
	/tmp/calibre.txz -L \
	"$CALIBRE_URL" \
 && mkdir -p \
        /app/calibre-web \
 && mkdir -p \
        /app/calibre \
 && tar xf \
        /tmp/calibre-web.tar.gz -C \
        /app/calibre-web --strip-components=1 \
 && tar xf \
	/tmp/calibre.txz \
	-C /app/calibre \
 && mkdir -p \
        /app/calibre-web \
 && tar xf \
        /tmp/calibre-web.tar.gz -C \
        /app/calibre-web --strip-components=1 \
 && cd /app/calibre-web \
 && python -m venv $VIRTUAL_ENV \
 && pip install --upgrade pip wheel \
 && pip install pipenv \
 && pip install -U --no-cache-dir -r requirements.txt -r optional-requirements.txt \
 && apk del \
        build-base \
        curl \
        linux-headers \
        openldap-dev \
        python3-dev \
        py3-pip \
	musl-dev \
 && apk add --no-cache \
        ghostscript \
        imagemagick \
        libldap \
        libsasl \
        python3 \
	musl

RUN echo "$CALIBRE_URL"

EXPOSE 8083
VOLUME /config
VOLUME /books

ENTRYPOINT ["python", "cps.py"]

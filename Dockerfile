FROM alpine:latest as build

ENV SQUID_VER 5.7

RUN set -x && \
	apk add --no-cache  \
		gcc \
		g++ \
		libc-dev \
		curl \
		gnupg \
		libressl-dev \
		perl-dev \
		autoconf \
		automake \
		make \
		pkgconfig \
		heimdal-dev \
		libtool \
		libcap-dev \
		linux-headers

RUN set -x && \
	mkdir -p /tmp/build && \
	cd /tmp/build && \
    curl -SsL http://www.squid-cache.org/Versions/v${SQUID_VER%%.*}/squid-${SQUID_VER}.tar.gz -o squid-${SQUID_VER}.tar.gz && \
	curl -SsL http://www.squid-cache.org/Versions/v${SQUID_VER%%.*}/squid-${SQUID_VER}.tar.gz.asc -o squid-${SQUID_VER}.tar.gz.asc

COPY squid-keys.asc /tmp

RUN set -x && \
	cd /tmp/build && \
	export GNUPGHOME="$(mktemp -d)" && \
	gpg --import /tmp/squid-keys.asc && \
	gpg --batch --verify squid-${SQUID_VER}.tar.gz.asc squid-${SQUID_VER}.tar.gz && \
	rm -rf "$GNUPGHOME"

RUN set -x && \
        cd /tmp/build && \
        tar --strip 1 -xzf squid-${SQUID_VER}.tar.gz && \
        \
        CFLAGS="-g0 -O2" \
        CXXFLAGS="-g0 -O2" \
        LDFLAGS="-s" \
        \
        ./configure \
                --build="$(uname -m)" \
                --host="$(uname -m)" \
                --prefix=/usr \
                --datadir=/usr/share/squid \
                --sysconfdir=/etc/squid \
                --libexecdir=/usr/lib/squid \
                --localstatedir=/var \
                --with-logdir=/var/log/squid \
                --disable-strict-error-checking \
                --disable-arch-native \
                --enable-removal-policies="lru,heap" \
                --enable-auth-digest \
                --enable-auth-basic="getpwnam,NCSA,DB" \
                --enable-external-acl-helpers="file_userip,unix_group,wbinfo_group" \
                --enable-auth-ntlm="fake" \
                --enable-auth-negotiate="kerberos,wrapper" \
                --enable-silent-rules \
                --enable-delay-pools \
                --enable-ssl-crtd \
                --enable-security-cert-generators="file" \
                --enable-cache-digests \
                --enable-follow-x-forwarded-for \
                --enable-storeio="aufs,diskd,ufs,rock" \
                --enable-translation \
                --disable-snmp \
                --with-openssl \
                --disable-dependency-tracking \
                --with-large-files \
                --with-default-user=squid \
                --with-pidfile=/var/run/squid/squid.pid



RUN set -x && \
	cd /tmp/build && \
	make && \
	make install && \
	cd tools/squidclient && make && make install-strip

FROM alpine:latest

ENV SQUID_CONFIG_FILE /etc/squid/squid.conf
ENV TZ America/Los_Angeles

RUN set -x && \
	deluser squid 2>/dev/null; delgroup squid 2>/dev/null; \
	addgroup -S squid -g 3128 && adduser -S -u 3128 -G squid -g squid -H -D -s /bin/false -h /var/cache/squid squid

RUN apk add --no-cache \
		libstdc++ \
		heimdal-libs \
		libcap \
		libressl3.5-libcrypto \
		libressl3.5-libssl \
		libltdl

COPY --from=build /etc/squid/ /etc/squid/
COPY --from=build /usr/lib/squid/ /usr/lib/squid/
COPY --from=build /usr/share/squid/ /usr/share/squid/
COPY --from=build /usr/sbin/squid /usr/sbin/squid
COPY --from=build /usr/bin/squidclient /usr/bin/squidclient


RUN install -d -o squid -g squid \
		/var/cache/squid \
		/var/log/squid \
		/var/run/squid && \
	chmod +x /usr/lib/squid/*

RUN install -d -m 755 -o squid -g squid \
		/etc/squid/conf.d \
		/etc/squid/conf.d.tail
RUN touch /etc/squid/conf.d/placeholder.conf

RUN	set -x && \
	apk add --no-cache --virtual .tz alpine-conf tzdata && \
	/sbin/setup-timezone -z $TZ && \
	apk del .tz

VOLUME ["/var/cache/squid"]
EXPOSE 3128/tcp

USER squid

CMD ["sh", "-c", "/usr/sbin/squid -f ${SQUID_CONFIG_FILE} --foreground -z && exec /usr/sbin/squid -f ${SQUID_CONFIG_FILE} --foreground -d 10"]

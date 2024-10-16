ARG ALPINE_RELEASE="3.20.3"

## -- Build Container -- ##

FROM alpine:${ALPINE_RELEASE} AS BUILDER

ARG OPENSSL_VERSION=3.0.15
ARG OPENSSL_SHA256="23c666d0edf20f14249b3d8f0368acaee9ab585b09e1de82107c66e1f3ec9533"
ARG GOST_ENGINE_HEAD=e0a500ab877ba72cb14026a24d462dd923b90ced
ARG CURL_VERSION=8.10.1
ARG CURL_SHA256="d15ebab765d793e2e96db090f0e172d127859d78ca6f6391d7eafecfd894bbc0"

WORKDIR /usr/local/src

RUN set -xe \
    && apk -q --no-cache upgrade && apk -q --update --no-cache add \
        git \
        g++ \
        gcc \
        perl \
        wget \
        make \
        re2c \
        cmake \
        pkgconf \
        autoconf \
        libc-dev \
        coreutils \
        linux-headers

# Build and install openssl
RUN set -xe \
    && wget -q --show-progress --progress=bar:force "https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/openssl-${OPENSSL_VERSION}.tar.gz" -O \
        "openssl-${OPENSSL_VERSION}.tar.gz" \
    && echo "$OPENSSL_SHA256" "openssl-${OPENSSL_VERSION}.tar.gz" | sha256sum -c - \
    && tar -xzf "openssl-${OPENSSL_VERSION}.tar.gz" \
    && cd "openssl-${OPENSSL_VERSION}" \
# RPATH crutch
# in x86_64 target library path is "$PREFIX/lib64" in other cases "$PREFIX/lib"
    && case $(uname -m) in \
        "aarch64") \
            export SSL_LIB=/usr/local/ssl/lib \
            ;; \
        "x86_64") \
            export SSL_LIB=/usr/local/ssl/lib64 \
            ;; \
        esac \
    && ./config no-async shared --prefix=/usr/local/ssl --openssldir=/usr/local/ssl -Wl,-rpath=${SSL_LIB} -Wl,--enable-new-dtags \
    && make && make install_sw && make install_ssldirs \
    && rm -rf "/usr/local/src/openssl-${OPENSSL_VERSION}.tar.gz" \
    && /usr/local/ssl/bin/openssl version -a

# Build and install GOST engine
RUN set -xe \
    && git clone -q https://github.com/gost-engine/engine.git engine \
    && cd engine \
    && git checkout -q $GOST_ENGINE_HEAD \
    && git submodule update --init \
    && mkdir build \
    && cd build \
    && OPENSSL_ENGINES_DIR=$(/usr/local/ssl/bin/openssl version -e | sed  's/.*\"\(.*\)\".*/\1/') \
# RPATH crutch
# in x86_64 target library path is "$PREFIX/lib64" in other cases "$PREFIX/lib"
    && case $(uname -m) in \
        "aarch64") \
            export SSL_LIB=/usr/local/ssl/lib \
            ;; \
        "x86_64") \
            export SSL_LIB=/usr/local/ssl/lib64 \
            ;; \
        esac \
    && cmake \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_C_FLAGS="-I/usr/local/ssl/include -L${SSL_LIB}" \
	    -DOPENSSL_ROOT_DIR=/usr/local/ssl \
        -DOPENSSL_INCLUDE_DIR=/usr/local/ssl/include \
        -DOPENSSL_LIBRARIES=${SSL_LIB} \
        -DOPENSSL_ENGINES_DIR=$OPENSSL_ENGINES_DIR \
        ../ \
    && cmake --build . --config Release \
    && make install 
    
# Build curl
RUN set -xe \
    && apk -q --update --no-cache add \
        zlib-dev \
        nghttp2-dev \
        libidn2-dev \
    && wget -q --show-progress --progress=bar:force "https://github.com/curl/curl/releases/download/curl-$(printf ${CURL_VERSION} |tr -s . _)/curl-${CURL_VERSION}.tar.gz" -O \
        "curl-${CURL_VERSION}.tar.gz" \
    && echo "$CURL_SHA256" "curl-${CURL_VERSION}.tar.gz" | sha256sum -c - \
    && tar -zxf "curl-${CURL_VERSION}.tar.gz" \
    && cd "curl-${CURL_VERSION}" \
# RPATH crutch
# in x86_64 target library path is "$PREFIX/lib64" in other cases "$PREFIX/lib"
    && case $(uname -m) in \
        "aarch64") \
            export SSL_LIB=/usr/local/ssl/lib \
            ;; \
        "x86_64") \
            export SSL_LIB=/usr/local/ssl/lib64 \
            ;; \
        esac \
    && CPPFLAGS="-I/usr/local/ssl/include" LDFLAGS="-L${SSL_LIB} -Wl,-rpath,${SSL_LIB}" LD_LIBRARY_PATH=${SSL_LIB} \
        ./configure --prefix=/usr/local/curl --with-ssl=/usr/local/ssl --with-libssl-prefix=/usr/local/ssl --without-libpsl \
    && make \
    && make install \
    && rm -rf "/usr/local/src/curl-${CURL_VERSION}.tar.gz" "/usr/local/src/curl-${CURL_VERSION}"

# Build cpro_converter tool
COPY cpro_converter.c /usr/local/src/cpro_converter.c

RUN set -xe \
# RPATH crutch
# in x86_64 target library path is "$PREFIX/lib64" in other cases "$PREFIX/lib"
    && case $(uname -m) in \
        "aarch64") \
            export SSL_LIB=/usr/local/ssl/lib \
            ;; \
        "x86_64") \
            export SSL_LIB=/usr/local/ssl/lib64 \
            ;; \
        esac \
    && gcc -o cpro_converter -Iengine  -I/usr/local/ssl/include \
        -L/usr/local/src/engine/build \
        -L/usr/local/src/openssl-${OPENSSL_VERSION} \
        -L${SSL_LIB} \
	engine/gost_ameth.c engine/gost_asn1.c \
	engine/gost_params.c engine/e_gost_err.c \
        engine/gost_ctl.c \
	cpro_converter.c -lcrypto -lssl -pthread -ldl -static -lgost_core \
    && rm -rf "/usr/local/src/engine" "/usr/local/src/openssl-${OPENSSL_VERSION}" /tmp/*

## -- Runtime Container -- ##

FROM alpine:${ALPINE_RELEASE}

WORKDIR /usr/local/src

RUN set -xe \
    && apk -q --no-cache upgrade && apk -q --update --no-cache add \
        bash \
        libidn2 \
        coreutils \
        nghttp2-libs \
        ca-certificates \
        ca-certificates-bundle \
    && rm -rf /var/cache/apk/*

COPY --from=BUILDER /usr/local/ssl/ /usr/local/ssl/
COPY --from=BUILDER /usr/local/curl/ /usr/local/curl/
COPY --from=BUILDER /usr/local/src/cpro_converter ./cpro_converter

RUN set -xe \
    && ln -sf /usr/local/ssl/bin/openssl /usr/bin/openssl \
    && ln -sf /usr/local/curl/bin/curl /usr/bin/curl


# Enable GOST engine
RUN set -xe \

    && OPENSSL_ENGINES_DIR=$(/usr/local/ssl/bin/openssl version -e | sed  's/.*\"\(.*\)\".*/\1/') \

    && sed -i '6i openssl_conf=openssl_def' /usr/local/ssl/openssl.cnf \
    && echo "" >> /usr/local/ssl/openssl.cnf \
    && echo "# OpenSSL default section" >> /usr/local/ssl/openssl.cnf \
    && echo "[openssl_def]" >> /usr/local/ssl/openssl.cnf \
    && echo "engines = engine_section" >> /usr/local/ssl/openssl.cnf \
    && echo "" >> /usr/local/ssl/openssl.cnf \
    && echo "# Engine scetion" >> /usr/local/ssl/openssl.cnf \
    && echo "[engine_section]" >> /usr/local/ssl/openssl.cnf \
    && echo "gost = gost_section" >> /usr/local/ssl/openssl.cnf \
    && echo "" >> /usr/local/ssl/openssl.cnf \
    && echo "# Engine gost section" >> /usr/local/ssl/openssl.cnf \
    && echo "[gost_section]" >> /usr/local/ssl/openssl.cnf \
    && echo "engine_id = gost" >> /usr/local/ssl/openssl.cnf \
    && echo "dynamic_path = ${OPENSSL_ENGINES_DIR}/gost.so" >> /usr/local/ssl/openssl.cnf \
    && echo "default_algorithms = ALL" >> /usr/local/ssl/openssl.cnf \
    && echo "CRYPT_PARAMS = id-Gost28147-89-CryptoPro-A-ParamSet" >> /usr/local/ssl/openssl.cnf

# Add Minsvyaz CA certificates
RUN set -xe \
    && curl -sSL https://github.com/schors/gost-russian-ca/raw/master/certs/ca-certificates.pem -o /usr/local/share/ca-certificates/gost-ca-certificates.pem \
    && update-ca-certificates \
    && rm -f /usr/local/share/ca-certificates/gost-ca-certificates.pem

ENTRYPOINT ["./cpro_converter"]


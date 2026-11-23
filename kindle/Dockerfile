# The pinned koxtoolchain release contains AMD64 host executables. Its ARM
# compiler and runtimes target glibc 2.20.
FROM amd64/ubuntu:24.04 AS base
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential ca-certificates cmake curl file git jq ninja-build patch perl pkg-config \
    qemu-user unzip xz-utils zstd && rm -rf /var/lib/apt/lists/*
ENV HOME=/sdk/home

FROM base AS build
ARG JOBS=2
COPY kindle/prepare.sh kindle/kindlehf.cmake kindle/manifest.json /usr/local/lib/kobuild/kindle/
COPY kindle/patches /usr/local/lib/kobuild/kindle/patches
RUN JOBS="$JOBS" bash /usr/local/lib/kobuild/kindle/prepare.sh

FROM base AS toolchain
COPY --from=build /sdk/x-tools /sdk/x-tools
COPY --from=build /sdk/qt-host /sdk/qt-host
COPY --from=build /sdk/qt /sdk/qt
COPY --from=build /sdk/openssl /sdk/openssl
COPY --from=build /sdk/runtime /sdk/runtime
COPY --from=build /sdk/fbink /sdk/fbink
COPY --from=build /sdk/kindlehf.cmake /sdk/kindlehf.cmake
COPY --from=build /sdk/ready.txt /sdk/ready.txt
COPY --from=build /sdk/src/qtbase-everywhere-src-6.8.3/LICENSES /sdk/src/qtbase-everywhere-src-6.8.3/LICENSES
COPY --from=build /sdk/src/qtsensors-everywhere-src-6.8.3/LICENSES /sdk/src/qtsensors-everywhere-src-6.8.3/LICENSES
COPY --from=build /sdk/src/FBInk-886f25f13368859ad8a899b88d04c26e19cda32e/LICENSE /sdk/src/FBInk-886f25f13368859ad8a899b88d04c26e19cda32e/LICENSE
COPY --from=build /sdk/src/openssl-openssl-3.5.9/LICENSE.txt /sdk/src/openssl-openssl-3.5.9/LICENSE.txt
COPY --from=build /sdk/downloads /usr/src/kobuild/kindle
COPY kindle /usr/src/kobuild/kindle/recipe
COPY kindle/check.sh /usr/local/bin/kobuild-check
COPY LICENSE NOTICE /usr/share/doc/kobuild/
COPY kindle/manifest.json /usr/share/doc/kobuild/kindle-manifest.json
COPY --from=build /sdk/src/qtbase-everywhere-src-6.8.3/LICENSES /usr/share/doc/kobuild/qt-licenses
ENV PATH=/sdk/x-tools/arm-kindlehf-linux-gnueabihf/bin:/sdk/qt-host/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    CROSS_TC=arm-kindlehf-linux-gnueabihf \
    CMAKE_TOOLCHAIN_FILE=/sdk/qt/lib/cmake/Qt6/qt.toolchain.cmake \
    QT_HOST_PATH=/sdk/qt-host \
    KOBALT_KINDLE_QT=/sdk/qt \
    KOBALT_KINDLE_QT_HOST=/sdk/qt-host \
    LDFLAGS="-Wl,-rpath-link,/sdk/openssl/lib -Wl,-rpath-link,/sdk/runtime/lib" \
    PKG_CONFIG_LIBDIR=/sdk/qt/lib/pkgconfig:/sdk/runtime/lib/pkgconfig:/sdk/openssl/lib/pkgconfig \
    KOBUILD_TARGET=kindle LC_ALL=C.UTF-8
RUN bash /usr/src/kobuild/kindle/recipe/bundle-gcc-runtime-sources.sh && \
    bash /usr/local/bin/kobuild-check
WORKDIR /work
CMD ["/bin/bash"]

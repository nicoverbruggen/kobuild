# Qt's official Linux desktop libraries, for building and testing an
# application's Linux desktop client. AMD64 and ARM64 hosts use the same
# recipe; each installs the Qt archives of its own architecture.
FROM docker.io/library/ubuntu:24.04@sha256:534baea6a22c03a63003dbc8dbe78fe34bc0d7e595d9a9dc9834884ff530eb55
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential ca-certificates ccache cmake curl file git jq lld make ninja-build p7zip-full \
        patch perl pkg-config unzip xz-utils zip \
        libdbus-1-3 libegl-dev libfontconfig-dev libgl-dev libglib2.0-0t64 libglx-dev \
        libopengl-dev libxkbcommon-dev \
    && rm -rf /var/lib/apt/lists/*
ENV QT_PATH=/opt/Qt/6.11.3/linux \
    LC_ALL=C.UTF-8
ENV CMAKE_PREFIX_PATH=$QT_PATH \
    PATH=$QT_PATH/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
COPY linux/manifest.json linux/install.sh /usr/local/lib/kobuild/
RUN --mount=type=cache,target=/var/cache/kobuild-linux,sharing=locked \
    bash /usr/local/lib/kobuild/install.sh
COPY LICENSE NOTICE /usr/share/doc/kobuild/
COPY android/ICU-LICENSE.txt /usr/share/doc/kobuild/icu-LICENSE.txt
COPY linux/smoke /usr/local/lib/kobuild/smoke
COPY --chmod=755 linux/check.sh /usr/local/bin/kobuild-check
ENV KOBUILD_TARGET=linux
RUN bash /usr/local/bin/kobuild-check
WORKDIR /work
CMD ["/bin/bash"]

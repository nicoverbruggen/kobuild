# kobuild

Kobo SDK containers with a cross compiler, sysroot and compatible Qt. Qt5 targets firmware 4.x; Qt6 targets firmware 5.x/6.x. Application dependencies and patches stay in the application repository.

```sh
./build.sh qt5
./build.sh qt6
```

Images are tagged `localhost/kobuild:qt5` and `localhost/kobuild:qt6`. Docker is used when installed; set `CONTAINER_ENGINE=podman` to select Podman. Builds use two compiler jobs by default; set `JOBS` to change it. Linux AMD64 and ARM64 hosts both produce ARM32 Kobo binaries.

To configure and compile a CMake project:

```sh
docker run --rm -v "$PWD:/work" -w /work localhost/kobuild:qt6 \
    sh -c 'cmake -S . -B build/qt6 -G Ninja && cmake --build build/qt6 --parallel 2'
```

GitHub Actions builds and checks both host architectures on pushes and pull requests. A tag such as `v1.0.0` also publishes `ghcr.io/<owner>/<repo>:qt5-v1.0.0` and `:qt6-v1.0.0`. Stable releases update the `qt5` and `qt6` aliases. Beta tags publish versioned images only. Publishing uses `GITHUB_TOKEN` with package write access.

The Qt6 image includes its prepared Qt source and build scripts in `/usr/src/kobuild/qt6-source.tar.xz`. This covers Qt, not all system packages. Exact source provenance for all components inherited from NickelTC in the Qt5 image remains unverified.

Scripts use [MIT](LICENSE). See [NOTICE](NOTICE) and [Qt patch notices](qt6/source/NOTICE) for third-party terms and sources.

#!/usr/bin/env python3
"""Compile an Android Qt Widgets client and optionally package its APK."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import zipfile


def run(*args):
    subprocess.run([str(arg) for arg in args], check=True)


def check_elf(binary, readelf):
    header = binary.read_bytes()[:20]
    if header[:6] != b'\x7fELF\x02\x01' or header[18:20] != b'\xb7\x00':
        raise RuntimeError('Expected a little-endian Android ARM64 library: ' + str(binary))
    segments = subprocess.check_output([str(readelf), '--program-headers', '--wide', str(binary)], text=True)
    alignments = [int(line.split()[-1], 16) for line in segments.splitlines() if line.strip().startswith('LOAD ')]
    if not alignments or any(alignment < 16384 for alignment in alignments):
        raise RuntimeError('Native library lacks 16 KiB ELF alignment: ' + str(binary))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apk', action='store_true')
    args = parser.parse_args()
    docs = Path('/usr/share/doc/kobuild')
    manifest = json.loads((docs / 'android-manifest.json').read_text())
    for spec in manifest['qt_archives']:
        if spec['kind'] == 'source':
            path = Path('/usr/src/kobuild/android') / spec['name']
            with path.open('rb') as stream:
                if hashlib.file_digest(stream, 'sha256').hexdigest() != spec['sha256']:
                    raise RuntimeError('Qt source archive checksum mismatch: ' + spec['name'])
    for name in ('LICENSE', 'NOTICE', 'qt-licenses/LGPL-3.0-only.txt', 'icu-LICENSE.txt', 'android-packages.txt'):
        if not (docs / name).is_file() or not (docs / name).stat().st_size:
            raise RuntimeError('Missing distribution file: ' + name)
    ndk = Path(os.environ['ANDROID_NDK_ROOT'])
    tools = ndk / 'toolchains/llvm/prebuilt/linux-x86_64/bin'
    readelf = tools / 'llvm-readelf'
    qt = Path(os.environ['QT_ANDROID_ARM64_PATH'])
    sdk = Path(os.environ['ANDROID_HOME'])
    build_tools = sdk / ('build-tools/' + manifest['build_tools'])
    if not re.search(r'^Pkg.Revision\s*=\s*' + re.escape(manifest['ndk']) + r'\s*$',
                     (ndk / 'source.properties').read_text(), re.MULTILINE):
        raise RuntimeError('Android NDK revision mismatch')
    for library in ('Core', 'Gui', 'Widgets', 'Network', 'Sensors'):
        check_elf(qt / ('lib/libQt6' + library + '_arm64-v8a.so'), readelf)
    with tempfile.TemporaryDirectory(prefix='kobuild-android-check-') as directory:
        work = Path(directory)
        (work / 'main.cpp').write_text('''#include <QApplication>
#include <QNetworkAccessManager>
#include <QSensor>
#include <QWidget>
class CheckWidget : public QWidget {
    Q_OBJECT
public:
    using QWidget::QWidget;
};
int main(int argc, char **argv) {
    QApplication app(argc, argv);
    QNetworkAccessManager network;
    QSensor sensor("accelerometer");
    CheckWidget widget;
    return widget.width();
}
#include "main.moc"
''')
        (work / 'message.txt').write_text('Android resource compiler check\n')
        (work / 'CMakeLists.txt').write_text('''cmake_minimum_required(VERSION 3.22)
project(kobuild_android_check LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_AUTOMOC ON)
find_package(Qt6 @VERSION@ EXACT REQUIRED COMPONENTS Core Gui Widgets Network Sensors)
qt_add_executable(check main.cpp)
target_link_libraries(check PRIVATE Qt6::Widgets Qt6::Network Qt6::Sensors)
qt_add_resources(check messages PREFIX "/kobuild" FILES message.txt)
set_target_properties(check PROPERTIES QT_ANDROID_MIN_SDK_VERSION 28
    QT_ANDROID_TARGET_SDK_VERSION 36 QT_ANDROID_COMPILE_SDK_VERSION 36
    QT_ANDROID_PACKAGE_NAME org.kobuild.check)
'''.replace('@VERSION@', manifest['qt_version']))
        build = work / 'build'
        run(qt / 'bin/qt-cmake', '-S', work, '-B', build, '-G', 'Ninja', '-DCMAKE_BUILD_TYPE=Release',
            '-DQT_HOST_PATH=' + os.environ['QT_HOST_PATH'], '-DANDROID_SDK_ROOT=' + str(sdk),
            '-DANDROID_NDK_ROOT=' + str(ndk), '-DANDROID_PLATFORM=android-28',
            '-DANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON',
            '-DQT_ANDROID_SDK_BUILD_TOOLS_REVISION=' + manifest['build_tools'])
        run('cmake', '--build', build, '--target', 'check', '--parallel', '2')
        binary = build / 'libcheck_arm64-v8a.so'
        check_elf(binary, readelf)
        dependencies = subprocess.check_output([str(readelf), '-d', str(binary)], text=True)
        for library in ('Widgets', 'Network', 'Sensors'):
            if 'libQt6' + library + '_arm64-v8a.so' not in dependencies:
                raise RuntimeError('Missing Android Qt library: ' + library)
        if args.apk:
            run('cmake', '--build', build, '--target', 'apk', '--parallel', '2')
            apk = build / 'android-build/check.apk'
            if not apk.is_file():
                raise RuntimeError('Android deploy tool did not produce an APK')
            with zipfile.ZipFile(apk) as package:
                if 'lib/arm64-v8a/libcheck_arm64-v8a.so' not in package.namelist():
                    raise RuntimeError('APK is missing the Android ARM64 application')
                for name in package.namelist():
                    if name.startswith('lib/') and name.endswith('.so'):
                        library = work / 'packaged-library.so'
                        library.write_bytes(package.read(name))
                        check_elf(library, readelf)
            run(build_tools / 'zipalign', '-c', '-P', '16', '4', apk)
            badging = subprocess.check_output([str(build_tools / 'aapt2'), 'dump', 'badging', str(apk)], text=True)
            for expected in ("package: name='org.kobuild.check'", "minSdkVersion:'28'", "targetSdkVersion:'36'",
                             "native-code: 'arm64-v8a'"):
                if expected not in badging:
                    raise RuntimeError('APK metadata mismatch: ' + expected + '\n' + badging)
            # A disposable, public test password checks signing tools without
            # needing a release key. The key and APK disappear with this check.
            key = work / 'test.p12'
            run('keytool', '-genkeypair', '-noprompt', '-storetype', 'PKCS12', '-keystore', key,
                '-alias', 'kobuild-check', '-storepass', 'android', '-keypass', 'android',
                '-keyalg', 'RSA', '-keysize', '2048', '-validity', '1', '-dname', 'CN=kobuild check')
            signed = work / 'signed.apk'
            run(build_tools / 'apksigner', 'sign', '--ks', key, '--ks-type', 'PKCS12',
                '--ks-key-alias', 'kobuild-check', '--ks-pass', 'pass:android', '--key-pass', 'pass:android',
                '--v4-signing-enabled', 'false', '--out', signed, apk)
            run(build_tools / 'apksigner', 'verify', '--verbose', signed)
            run(build_tools / 'zipalign', '-c', '-P', '16', '4', signed)
    print('Android Qt code generation, ARM64 link, 16 KiB alignment and distribution checks passed'
          + ('; APK packaging and test signing passed' if args.apk else ''))


if __name__ == '__main__':
    main()

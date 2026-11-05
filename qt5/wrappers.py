"""Use the old runtime headers and libraries with the modern ARM compiler."""
from pathlib import Path
import subprocess

loader = Path('/tc/qt5-host/lib64/ld-linux-x86-64.so.2')
loader.unlink()
loader.symlink_to('../lib/x86_64-linux-gnu/ld-2.28.so')
root = Path('/tc/qt5')
bin = root / 'bin'
bin.mkdir(exist_ok=True)
# Ubuntu's cross compiler always searches its own glibc 2.35 headers in
# /usr/arm-linux-gnueabihf/include before the sysroot. Firmware 4.x has glibc
# 2.19, so replace the standard search list: the compiler's own headers, then
# the sysroot. -idirafter keeps both after the caller's -I and -isystem
# directories, where the compiler puts its standard directories.
compiler_headers = subprocess.run(['/usr/bin/arm-linux-gnueabihf-gcc-11', '-print-file-name=include'],
                                  check=True, capture_output=True, text=True).stdout.strip()
system_includes = ' -nostdinc -idirafter ' + compiler_headers + ' -idirafter /tc/qt5/sysroot/usr/include'
for name in ('gcc', 'g++'):
    includes = system_includes if name == 'gcc' else ' -fno-sized-deallocation -include /tc/qt5/cxx-compat.h -isystem /tc/qt5/include/c++/4.9.4 -isystem /tc/qt5/include/c++/4.9.4/arm-nickel-linux-gnueabihf' + system_includes
    output = bin / name
    output.write_text('#!/bin/sh\nexec /usr/bin/arm-linux-gnueabihf-' + name + '-11'
                      + ' --sysroot=/tc/qt5/sysroot -B/tc/qt5/sysroot/usr/lib/ -L/tc/qt5/sysroot/lib -L/tc/qt5/sysroot/usr/lib -no-pie'
                      + ' -march=armv7-a -mfpu=neon -mfloat-abi=hard' + includes + ' "$@"\n')
    output.chmod(0o755)
for name in ('moc', 'rcc', 'uic'):
    tool = root / 'sysroot/usr/bin' / name
    tool.rename(tool.with_suffix('.x86_64'))
    # Select both the loader and its libraries. QEMU's -L alone can fall back
    # to Ubuntu's newer libstdc++ on AMD64 and mix incompatible runtimes.
    tool.write_text('#!/bin/sh\nexec qemu-x86_64 /tc/qt5-host/lib64/ld-linux-x86-64.so.2'
                    + ' --inhibit-cache --library-path /tc/qt5-host/lib/x86_64-linux-gnu:/tc/qt5-host/usr/lib/x86_64-linux-gnu '
                    + str(tool.with_suffix('.x86_64')) + ' "$@"\n')
    tool.chmod(0o755)
for metadata in (root / 'sysroot/usr/lib/pkgconfig').glob('*.pc'):
    metadata.write_text(metadata.read_text().replace('prefix=/usr\n', 'prefix=/tc/qt5/sysroot/usr\n'))
# NickelTC's Qt5Gui has QT_NO_OPENGL and no GL dependency. Its old generated
# CMake metadata still asks for desktop GL; qmake correctly omits it.
extras = root / 'sysroot/usr/lib/cmake/Qt5Gui/Qt5GuiConfigExtras.cmake'
extras.write_text(extras.read_text().replace('_qt5gui_find_extra_libs(OPENGL "GL" "" "")', '')
                  .replace('set(Qt5Gui_OPENGL_IMPLEMENTATION GL)', 'set(Qt5Gui_OPENGL_IMPLEMENTATION "")'))

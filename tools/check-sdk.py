#!/usr/bin/env python3
"""Compile and link an ARM Qt client without running device code."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--target', choices=['qt5', 'qt6'], default=os.environ.get('KOBUILD_TARGET'))
    args = parser.parse_args()
    if args.target not in ('qt5', 'qt6'):
        parser.error('Set --target or KOBUILD_TARGET to qt5 or qt6')
    major = args.target[-1]
    with tempfile.TemporaryDirectory(prefix='kobuild-check-') as directory:
        work = Path(directory)
        (work / 'main.cpp').write_text('''#include <QApplication>
#include <QWidget>
#include <QtGui/qpa/qplatformintegration.h>
class CheckWidget : public QWidget {
    Q_OBJECT
public:
    using QWidget::QWidget;
};
int main(int argc, char **argv) {
    QApplication app(argc, argv);
    CheckWidget widget;
    return widget.width();
}
#include "main.moc"
''')
        (work / 'CMakeLists.txt').write_text('''cmake_minimum_required(VERSION 3.16)
project(kobuild_check LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(CMAKE_AUTOMOC ON)
find_package(Qt@MAJOR@ REQUIRED COMPONENTS Core Gui Widgets)
add_executable(check main.cpp)
target_link_libraries(check PRIVATE Qt@MAJOR@::Widgets)
if(TARGET Qt@MAJOR@::GuiPrivate)
    target_link_libraries(check PRIVATE Qt@MAJOR@::GuiPrivate)
else()
    # Qt 5.2 exports private include paths instead of a GuiPrivate target.
    target_include_directories(check PRIVATE ${Qt@MAJOR@Gui_PRIVATE_INCLUDE_DIRS} ${Qt@MAJOR@Core_PRIVATE_INCLUDE_DIRS})
endif()
'''.replace('@MAJOR@', major))
        subprocess.run(['cmake', '-S', str(work), '-B', str(work / 'build'), '-G', 'Ninja'], check=True)
        subprocess.run(['cmake', '--build', str(work / 'build'), '--parallel', '2'], check=True)
        binary = work / 'build/check'
        header = binary.read_bytes()[:20]
        if header[:6] != b'\x7fELF\x01\x01' or header[18:20] != b'\x28\x00':
            raise RuntimeError('Expected a little-endian ARM32 binary')
        attributes = subprocess.check_output(['arm-linux-gnueabihf-readelf', '-A', str(binary)], text=True)
        if 'Tag_ABI_VFP_args: VFP registers' not in attributes:
            raise RuntimeError('Expected the ARM hard-float ABI')
        dependencies = subprocess.check_output(['arm-linux-gnueabihf-readelf', '-d', str(binary)], text=True)
        if f'libQt{major}Widgets.so.{major}' not in dependencies:
            raise RuntimeError('Expected the selected Qt Widgets library')
    print('Qt code generation, private headers and ARM hard-float link check passed')


if __name__ == '__main__':
    main()

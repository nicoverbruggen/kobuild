cmake_minimum_required(VERSION 3.22)
project(kobuild_android_check LANGUAGES CXX)
find_package(PkgConfig REQUIRED)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_AUTOMOC ON)
find_package(Qt6 6.11.3 EXACT REQUIRED COMPONENTS Core Gui Widgets Network Sensors)
qt_standard_project_setup(REQUIRES 6.11)
qt_add_executable(check main.cpp)
target_link_libraries(check PRIVATE Qt6::Widgets Qt6::Network Qt6::Sensors)
qt_add_resources(check messages PREFIX "/kobuild" FILES message.txt)
set_target_properties(check PROPERTIES QT_ANDROID_MIN_SDK_VERSION 28
    QT_ANDROID_TARGET_SDK_VERSION 36 QT_ANDROID_COMPILE_SDK_VERSION 36
    QT_ANDROID_PACKAGE_NAME org.kobuild.check)

#! /bin/sh
set -e

mkdir -p build_android
mkdir -p build_ios
mkdir -p output/ios
mkdir -p output/android

echo "Building android"
./xqc_build.sh android build_android output/android third_party/boringssl


echo "Building ios"
# ./xqc_build.sh ios build_ios output/ios third_party/boringssl
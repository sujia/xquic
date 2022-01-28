# Copyright (c) 2022, Alibaba Group Holding Limited
#!/bin/sh

# android_archs=(armeabi-v7a arm64-v8a)
ios_archs=(armv7 arm64 x86_64)
android_archs=(arm64-v8a)
# ios_archs=(arm64)
cur_dir=$(cd "$(dirname "$0")";pwd)

cp -f $cur_dir/cmake/CMakeLists.txt  $cur_dir/CMakeLists.txt

platform=$1
build_dir=$2
artifact_dir=$3

# boringssl is used as default
ssl_type="boringssl"
ssl_path=$4
ssl_lib_path="${ssl_path}/"

if [ -z "$ssl_path" ] || [ -z "$ssl_lib_path" ] ; then
    echo "ssl environment not specified"
    exit 0
fi

create_dir_or_exit() {
    if [ x"$2" == x ] ; then
        echo "$1 MUST NOT be empty"
        exit 1
    fi
    if [ -d $2 ] ; then
        echo "directory already exists"
    else
        mkdir $2
        echo "create $1 directory($2) suc"
    fi
}

platform=$(echo $platform | tr A-Z a-z )

if [ x"$platform" == xios ] ; then 
    if [ x"$IOS_CMAKE_TOOLCHAIN" == x ] ; then
        echo "IOS_CMAKE_TOOLCHAIN MUST be defined"
        IOS_CMAKE_TOOLCHAIN=./cmake/ios.toolchain.cmake
        echo "set IOS_CMAKE_TOOLCHAIN to ${IOS_CMAKE_TOOLCHAIN}"
        # exit 0
    fi

    archs=${ios_archs[@]} 
    configures="-DSSL_TYPE=${ssl_type}
                -DSSL_PATH=${ssl_path}
                -DSSL_LIB_PATH=${ssl_lib_path}
                -DDEPLOYMENT_TARGET=10.0
                -DCMAKE_BUILD_TYPE=Minsizerel
                -DXQC_ENABLE_TESTING=OFF
                -DXQC_BUILD_SAMPLE=OFF
                -DGCOV=OFF
                -DCMAKE_TOOLCHAIN_FILE=${IOS_CMAKE_TOOLCHAIN}
                -DENABLE_BITCODE=0
                -DXQC_NO_SHARED=1"

elif [ x"$platform" == xandroid ] ; then
    if [ x"$ANDROID_NDK" == x ] ; then
        echo "ANDROID_NDK MUST be defined"
        exit 0
    fi

    archs=${android_archs[@]}
    configures="-DSSL_TYPE=${ssl_type}
                -DSSL_PATH=${ssl_path}
                -DSSL_LIB_PATH=${ssl_lib_path}
                -DCMAKE_BUILD_TYPE=Minsizerel
                -DXQC_ENABLE_TESTING=OFF
                -DXQC_BUILD_SAMPLE=OFF
                -DGCOV=OFF
                -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK/build/cmake/android.toolchain.cmake
                -DANDROID_STL=c++_shared
                -DANDROID_NATIVE_API_LEVEL=android-19
                -DXQC_DISABLE_RENO=OFF
                -DXQC_ENABLE_BBR2=ON
                -DBUILD_SHARED_LIBS=1
                -DXQC_DISABLE_LOG=ON"
else 
    echo "no support platform"
    exit 0
fi


generate_plat_spec() {
    plat_spec=
    if [ x"$platform" == xios ] ; then
        plat_spec="-DARCHS=$1"
        if [ x"$1" == xx86_64 ] ; then
            plat_spec="$plat_spec -DPLATFORM=SIMULATOR64"
        elif [ x"$1" == xi386 ] ; then
            plat_spec="$plat_spec -DPLATFORM=SIMULATOR"
        fi
    else
        plat_spec="-DANDROID_ABI=$1"
    fi
    echo $plat_spec
}

create_dir_or_exit build $build_dir
# to absoulute path 
build_dir=$cur_dir/$build_dir

create_dir_or_exit artifact $artifact_dir
artifact_dir=$cur_dir/$artifact_dir

cd $build_dir 

for i in ${archs[@]} ;
do
    rm -f  CMakeCache.txt
    rm -rf CMakeFiles
    rm -rf Makefile
    rm -rf cmake_install.cmake
    rm -rf include
    rm -rf outputs
    rm -rf third_party

    echo "compiling xquic on $i arch"
    cmake  $configures  $(generate_plat_spec $i ) -DLIBRARY_OUTPUT_PATH=`pwd`/outputs/ ..
    make -j 8 ssl
    make -j 8 crypto
    make -j 8 xquic
    if [ $? != 0 ] ; then
        exit 0
    fi

    if [ ! -d  ${artifact_dir}/$i ] ; then
        mkdir -p ${artifact_dir}/$i
    fi
    cp -f `pwd`/outputs/*.a     ${artifact_dir}/$i/
    if [ x"$platform" == xandroid ] ; then 
        cp -f `pwd`/outputs/*.so    ${artifact_dir}/$i/
    fi
done

cd ..

make_fat() {
    script="lipo -create"
    for i in ${archs[@]} ;
    do
        script="$script -arch $i $artifact_dir/$i/$1  "
    done
    script="$script -output $cur_dir/ios/xquic/xquic/Libs/$1"
    $($script) 
}


if [ x"$platform" == xios ] ; then
    if [ ! -d $cur_dir/ios/xquic/xquic/Headers ] ; then
        mkdir -p $cur_dir/ios/xquic/xquic/Headers
    fi
    if [ ! -d $cur_dir/ios/xquic/xquic/Libs ] ; then
        mkdir -p $cur_dir/ios/xquic/xquic/Libs
    fi
    make_fat libxquic.a
    make_fat libcrypto.a
    make_fat libssl.a
    cp -f $cur_dir/include/xquic/*   $cur_dir/ios/xquic/xquic/Headers/
    cp -f $build_dir/include/xquic/* $cur_dir/ios/xquic/xquic/Headers/

fi

strip_android() {
    UNAMES=$(uname -s)
    echo $UNAMES
    if [ "$UNAMES" == "Linux" ]; then
        export HOST_TAG=linux-x86_64
    else
        export HOST_TAG=darwin-x86_64
    fi
    echo $HOST_TAG
    export TOOLCHAIN=$ANDROID_NDK/toolchains/llvm/prebuilt/$HOST_TAG
    echo "strip $android_strip"
    export android_strip_32=$TOOLCHAIN/bin/arm-linux-androideabi-strip
    export android_strip_64=$TOOLCHAIN/bin/aarch64-linux-android-strip
    $android_strip_64 -s output/android/arm64-v8a/libxquic.so
    $android_strip_32 -s output/android/armeabi-v7a/libxquic.so
    echo "strip done"
}

if [ x"$platform" == xandroid ] ; then
     strip_android
fi


#!/bin/bash

realpath() {
    [[ $1 = /* ]] && echo "$1" || echo "$PWD/${1#./}"
}

XCODE=$(xcode-select -p)
if [ ! -d "$XCODE" ]; then
	echo "You have to install Xcode and the command line tools first"
	exit 1
fi

REL_SCRIPT_PATH="$(dirname $0)"
SCRIPTPATH=$(realpath "$REL_SCRIPT_PATH")
CURLPATH="$SCRIPTPATH/../curl"

PWD=$(pwd)
cd "$CURLPATH"

if [ ! -x "$CURLPATH/configure" ]; then
	echo "Curl needs external tools to be compiled"
	echo "Make sure you have autoconf, automake and libtool installed"

	./buildconf

	EXITCODE=$?
	if [ $EXITCODE -ne 0 ]; then
		echo "Error running the buildconf program"
		cd "$PWD"
		exit $EXITCODE
	fi
fi

git apply ../patches/patch_curl_fixes1172.diff

# export CC="$XCODE/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
DESTDIR="$SCRIPTPATH/../prebuilt-with-ssl/iOS"

export IPHONEOS_DEPLOYMENT_TARGET="12"
ARCHS=(arm64 arm64 x86_64)
HOSTS=(arm arm64 x86_64)
PLATFORMS=(iPhoneOS iPhoneSimulator iPhoneSimulator)
SDK=(iphoneos iphonesimulator iphonesimulator)

#Build for all the architectures
for (( i=0; i<${#ARCHS[@]}; i++ )); do
	ARCH=${ARCHS[$i]}
	PLATFORM=${PLATFORMS[$i]}
	SYSROOT=$(xcrun --sdk ${SDK[$i]} --show-sdk-path)
	TARGET="$ARCH-apple-ios"
	BITCODE_FLAGS="-fembed-bitcode"

	if [ "$PLATFORM" = "iPhoneSimulator" ]; then
		BITCODE_FLAGS=""
		TARGET="$TARGET-simulator"
		export CPPFLAGS="-isysroot ${SYSROOT} -D__IPHONE_OS_VERSION_MIN_REQUIRED=${IPHONEOS_DEPLOYMENT_TARGET%%.*}0000"
	fi

	export CFLAGS="-target $TARGET -arch $ARCH -pipe -Os -gdwarf-2 -isysroot ${SYSROOT} -miphoneos-version-min=${IPHONEOS_DEPLOYMENT_TARGET} $BITCODE_FLAGS -Werror=partial-availability"
	export LDFLAGS="-arch $ARCH -isysroot ${SYSROOT}"

	cd "$CURLPATH"
	./configure	--host="${HOSTS[$i]}-apple-darwin" \
			--with-darwinssl \
			--enable-static \
			--disable-shared \
			--enable-threaded-resolver \
			--disable-verbose \
			--enable-ipv6
	EXITCODE=$?
	if [ $EXITCODE -ne 0 ]; then
		echo "Error running the cURL configure program"
		cd "$PWD"
		exit $EXITCODE
	fi

	make -j $(sysctl -n hw.logicalcpu_max)
	EXITCODE=$?
	if [ $EXITCODE -ne 0 ]; then
		echo "Error running the make program"
		cd "$PWD"
		exit $EXITCODE
	fi

	LIB_DESTDIR=$DESTDIR/${PLATFORM}_${ARCH}
	mkdir -p "$LIB_DESTDIR"
	cp "$CURLPATH/lib/.libs/libcurl.a" "$LIB_DESTDIR/"

	make clean
done

git checkout $CURLPATH

#Build universal libraries
cd "$DESTDIR"

mkdir -p ios
lipo -create iPhoneOS_*/libcurl.a -output ios/libcurl.a

mkdir -p simulator
lipo -create iPhoneSimulator_*/libcurl.a -output simulator/libcurl.a

mkdir -p dev
lipo -create iPhoneOS_*/libcurl.a iPhoneSimulator_x86_64/libcurl.a -output dev/libcurl.a

# mkdir -p apple-silicon
# lipo -create iPhoneOS_*/libcurl.a iPhoneSimulator_arm64/libcurl.a -output apple-silicon/libcurl.a

#Copying cURL headers
if [ -d "$DESTDIR/include" ]; then
	echo "Cleaning headers"
	rm -rf "$DESTDIR/include"
fi
cp -R "$CURLPATH/include" "$DESTDIR/"
rm "$DESTDIR/include/curl/.gitignore"

cd "$PWD"

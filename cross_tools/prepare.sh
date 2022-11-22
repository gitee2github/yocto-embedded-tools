#!/bin/bash

function delete_dir() {
	while [ $# != 0 ] ; do
		[ -n "$1" ] && rm -rf ./$1 ; shift; done
}

function do_patch() {
	pushd $1
	if [ $1 = "isl" ];then
		tar xf $1-0.14.tar.xz
		tar xf $1-0.16.1.tar.xz
		patch -p1 < *.patch
	elif [ $1 = "zlib" ];then
		tar xf *.tar.*
	else
		PKG=$(echo *.tar.*)
        echo "$1: do_unpack for of $PKG..."
		tar xf *.tar.*
        echo "make patchlist of $1..."
		cat *.spec | grep "Patch" | grep -v "#" |grep "\.patch" | awk -F ":" '{print $2}' > $1-patchlist
	    if [ $1 = "gcc" ];then
            # current patches can't apply, it cause --sysroot bugs
            sed -i '/0041-Backport-Register-sysroot-in-the-driver-switches-tab.patch/d' $1-patchlist
        fi
        ls ${OE_PATCH_DIR}/ | grep "^$1" > $1-patchlist-oe || true
		pushd ${PKG%%.tar.*}
		for i in `cat ../$1-patchlist`
		do
            echo "----------------apply patch $i:"
			patch -p1 < ../$i
		done
		for i in `cat ../$1-patchlist-oe`
		do
            echo "----------------apply patch ${OE_PATCH_DIR}/$i:"
			patch -p1 < ${OE_PATCH_DIR}/$i
		done
		popd
	fi
	popd
    echo "------------do_patch for $1 done!"
}

function download_and_patch() {
	while [ $# != 0 ] ; do
		[ -n "$1" ] && echo "Download $1" && git clone -b $COMMON_BRANCH https://gitee.com/src-openeuler/$1.git --depth 1 && do_patch $1; shift;
	done
}

function do_prepare() {
	[ ! -d "$LIB_PATH" ] && mkdir $LIB_PATH
	pushd $LIB_PATH
	delete_dir $KERNEL $GCC $GLIBC $MUSLC $BINUTILS $GMP $MPC $MPFR $ISL $EXPAT $GETTEXT $NCURSES $ZLIB $LIBICONV $GDB
	git clone -b $KERNEL_BRANCH https://gitee.com/openeuler/kernel.git --depth 1
	git clone -b $MUSLC_BRANCH https://gitee.com/src-openeuler/musl.git --depth 1 && do_patch musl;
	download_and_patch $GCC $GLIBC $BINUTILS $GMP $MPC $MPFR $ISL $EXPAT $NCURSES $ZLIB $GDB
	#LIBICONV and GETTEXT dir is need, but with no code, it will skip when ct-ng build under our openeuler env.
	mkdir -p $LIB_PATH/$LIBICONV/$LIBICONV_DIR
	mkdir -p $LIB_PATH/$GETTEXT/$GETTEXT_DIR
	popd
}

function update_feature() {
	# Change GLIBC_DYNAMIC_LINKER to use lib64/xxx.ld for arm64 and lib64/lp64d/xxx.ld for riscv64
	sed -i "s#^\#define GLIBC_DYNAMIC_LINKER.*#\#undef STANDARD_STARTFILE_PREFIX_2\n\#define STANDARD_STARTFILE_PREFIX_2 \"/usr/lib64/\"\n\#define GLIBC_DYNAMIC_LINKER \"/lib%{mabi=lp64:64}%{mabi=ilp32:ilp32}/ld-linux-aarch64%{mbig-endian:_be}%{mabi=ilp32:_ilp32}.so.1\"#g" $LIB_PATH/$GCC/$GCC_DIR/gcc/config/aarch64/aarch64-linux.h
	sed -i "s#^\#define GLIBC_DYNAMIC_LINKER.*#\#define GLIBC_DYNAMIC_LINKER \"/lib64/lp64d/ld-linux-riscv\" XLEN_SPEC \"-\" ABI_SPEC \".so.1\"#g" $LIB_PATH/$GCC/$GCC_DIR/gcc/config/riscv/linux.h
	sed -i "s#^\#define MUSL_DYNAMIC_LINKER.*#\#define MUSL_DYNAMIC_LINKER \"/lib%{mabi=lp64:64}%{mabi=ilp32:ilp32}/ld-musl-aarch64%{mbig-endian:_be}%{mabi=ilp32:_ilp32}.so.1\"#g" $LIB_PATH/$GCC/$GCC_DIR/gcc/config/aarch64/aarch64-linux.h
	sed -i "s#^\#define MUSL_DYNAMIC_LINKER.*#\#define MUSL_DYNAMIC_LINKER \"/lib64/lp64d/ld-musl-riscv\" XLEN_SPEC MUSL_ABI_SUFFIX \".so.1\"#g" $LIB_PATH/$GCC/$GCC_DIR/gcc/config/riscv/linux.h        

	# Change libstdc++.so option
	sed -i "s#^\\t\$(OPT_LDFLAGS).*#\\t\$(OPT_LDFLAGS) \$(SECTION_LDFLAGS) \$(AM_CXXFLAGS)  \$(LTLDFLAGS) -Wl,-z,relro,-z,now,-z,noexecstack -Wtrampolines -o \$\@#g" $LIB_PATH/$GCC/$GCC_DIR/libstdc++-v3/src/Makefile.in
}

function update_config() {
	cp $SRC_DIR/configs/config_* $WORK_DIR/
	sed -i "s#^CT_LINUX_CUSTOM_LOCATION.*#CT_LINUX_CUSTOM_LOCATION=\"$LIB_PATH/kernel\"#g" $WORK_DIR/config_*
	sed -i "s#^CT_BINUTILS_CUSTOM_LOCATION.*#CT_BINUTILS_CUSTOM_LOCATION=\"$LIB_PATH/$BINUTILS/$BINUTILS_DIR\"#g" $WORK_DIR/config_*
	sed -i "s#^CT_GLIBC_CUSTOM_LOCATION.*#CT_GLIBC_CUSTOM_LOCATION=\"$LIB_PATH/$GLIBC/$GLIBC_DIR\"#g" $WORK_DIR/config_*
	sed -i "s#^CT_MUSL_CUSTOM_LOCATION.*#CT_MUSL_CUSTOM_LOCATION=\"$LIB_PATH/$MUSLC/$MUSLC_DIR\"#g" $WORK_DIR/config_*
	sed -i "s#^CT_GCC_CUSTOM_LOCATION.*#CT_GCC_CUSTOM_LOCATION=\"$LIB_PATH/$GCC/$GCC_DIR\"#g" $WORK_DIR/config_*
	sed -i "s#^CT_GDB_CUSTOM_LOCATION.*#CT_GDB_CUSTOM_LOCATION=\"$LIB_PATH/$GDB/$GDB_DIR\"#g" $WORK_DIR/config_*
	sed -i "s#^CT_GMP_CUSTOM_LOCATION.*#CT_GMP_CUSTOM_LOCATION=\"$LIB_PATH/$GMP/$GMP_DIR\"#g" $WORK_DIR/config_*
	sed -i "s#^CT_ISL_CUSTOM_LOCATION.*#CT_ISL_CUSTOM_LOCATION=\"$LIB_PATH/$ISL/$ISL_DIR\"#g" $WORK_DIR/config_*
	sed -i "s#^CT_MPC_CUSTOM_LOCATION.*#CT_MPC_CUSTOM_LOCATION=\"$LIB_PATH/$MPC/$MPC_DIR\"#g" $WORK_DIR/config_*
	sed -i "s#^CT_MPFR_CUSTOM_LOCATION.*#CT_MPFR_CUSTOM_LOCATION=\"$LIB_PATH/$MPFR/$MPFR_DIR\"#g" $WORK_DIR/config_*
	sed -i "s#^CT_EXPAT_CUSTOM_LOCATION.*#CT_EXPAT_CUSTOM_LOCATION=\"$LIB_PATH/$EXPAT/$EXPAT_DIR\"#g" $WORK_DIR/config_*
	sed -i "s#^CT_LIBICONV_CUSTOM_LOCATION.*#CT_LIBICONV_CUSTOM_LOCATION=\"$LIB_PATH/$LIBICONV/$LIBICONV_DIR\"#g" $WORK_DIR/config_*
	sed -i "s#^CT_GETTEXT_CUSTOM_LOCATION.*#CT_GETTEXT_CUSTOM_LOCATION=\"$LIB_PATH/$GETTEXT/$GETTEXT_DIR\"#g" $WORK_DIR/config_*
	sed -i "s#^CT_NCURSES_CUSTOM_LOCATION.*#CT_NCURSES_CUSTOM_LOCATION=\"$LIB_PATH/$NCURSES/$NCURSES_DIR\"#g" $WORK_DIR/config_*
	sed -i "s#^CT_ZLIB_CUSTOM_LOCATION.*#CT_ZLIB_CUSTOM_LOCATION=\"$LIB_PATH/$ZLIB/$ZLIB_DIR\"#g" $WORK_DIR/config_*
}

usage()
{
	echo -e "Tip: sh "$THIS_SCRIPT" <work_dir>\n"
}

check_use()
{
	if [ -n "$BASH_SOURCE" ]; then
		THIS_SCRIPT="$BASH_SOURCE"
	elif [ -n "$ZSH_NAME" ]; then
		THIS_SCRIPT="$0"
	else
		THIS_SCRIPT="$(pwd)/prepare.sh"
		if [ ! -e "$THIS_SCRIPT" ]; then
			echo "Error: $THIS_SCRIPT doesn't exist!"
			return 1
		fi
	fi

	if [ "$0" != "$THIS_SCRIPT" ]; then
		echo "Error: This script cannot be sourced. Please run as 'sh $THIS_SCRIPT'" >&2
		return 1
	fi
}

main()
{
	usage
	check_use || return 1
	set -e
	WORK_DIR="$1"
	SRC_DIR="$(cd $(dirname $0)/;pwd)"
	SRC_DIR="$(realpath ${SRC_DIR})"
	if [[ -z "${WORK_DIR}" ]];then
		WORK_DIR=$SRC_DIR
		echo "use default work dir: $WORK_DIR"
	fi
	WORK_DIR="$(realpath ${WORK_DIR})"
	source $SRC_DIR/configs/config.xml
    OE_PATCH_DIR="$SRC_DIR/patches"
	readonly LIB_PATH="$WORK_DIR/open_source"

	do_prepare
	update_feature
	update_config

	cd $WORK_DIR
	echo "Prepare done! Now you can run: (not in root please)"
	echo "'cp config_arm32 .config && ct-ng build' for build arm"
	echo "'cp config_aarch64 .config && ct-ng build' for build arm64"
	echo "'cp config_x86_64 .config && ct-ng build' for build x86_64"
	echo "'cp config_riscv64 .config && ct-ng build' for build riscv64"
	echo "'cp config_aarch64-musl .config && ct-ng build' for build muslc_aarch64"
}

main "$@"

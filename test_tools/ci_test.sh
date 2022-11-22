#!/bin/bash

set -e

# 测试镜像类型: tiny 或 std
IMAGE_TYPE=
# 测试镜像编译框架：aarch64 或 arm
BUILD_ARCH=
# 测试镜像编译分支: master openEuler-22.03-LTS openEuler-22.09
BUILD_BRANCH=
# 构建镜像所在的路径
IMAGE_OUT_DIR=
# 测试框架下载、执行的路径
TEST_WORK_DIR=

# 测试运行的测试套名
run_suitecase=
# 可以忽略的测试失败用例
ignoreFail=
#qemu启动时等待的时间
qemu_option_wait_time=
# 多测试套结果保存文件夹
results_path=

# 测试结果
exitCode=0

function printLine() {
    lineLen=$1
    for i in $(seq 1 $lineLen); do
        echo -n "-"
    done
    echo " "
}

function printSpace() {
    lineLen=$1
    for i in $(seq 1 $lineLen); do
        echo -n " "
    done
}

function printItem() {
    suiteName=$1
    printCase=$2
    result=$3

    suiteLen=$( echo $suiteName | wc -L )
    suiteSpaceLen=`expr $suiteMaxLen - $suiteLen`
    resultLen=$( echo $result | wc -L )
    resultSpaceLen=`expr 8 - $resultLen`

    caseLen=$( echo $printCase | wc -L )
    caseSpaceLen=`expr $caseMaxLen - $caseLen`
    echo -n "| $suiteName"
    printSpace $suiteSpaceLen
    echo -n " | $printCase"
    printSpace $caseSpaceLen
    echo -n " | $result"
    printSpace $resultSpaceLen
    echo "|"
}

function result_output() {
    # 打印所有用例执行结果
    suiteMaxLen=$( ls ${results_path} | wc -L )
    caseMaxLen=8
    for one_suite in ${run_suitecase[@]}; do
        tmpSucceedLen=0
        tmpFailedLen=0
        tmpMax=0
        if [ -e ${results_path}/${one_suite}/succeed ]; then
            tmpSucceedLen=$( ls ${results_path}/${one_suite}/succeed | wc -L )
        fi
        if [ -e ${results_path}/${one_suite}/failed ]; then
            tmpFailedLen=$( ls ${results_path}/${one_suite}/failed | wc -L )
        fi
        if [ $tmpSucceedLen -gt $tmpFailedLen ]; then
            tmpMax=$tmpSucceedLen
        else
            tmpMax=$tmpFailedLen
        fi
        if [ $tmpMax -gt $caseMaxLen ]; then
            caseMaxLen=$tmpMax
        fi
    done
    suiteMaxLen=`expr $suiteMaxLen + 1`
    caseMaxLen=`expr $caseMaxLen + 1`
    totalLen=`expr $suiteMaxLen + $caseMaxLen + 17`

    printLine $totalLen
    printItem "testsuite" "testcase" "result"
    printLine $totalLen
    for one_suite in ${run_suitecase[@]}; do
        succeedCases=""
        failCases=""
        if [ -e ${results_path}/${one_suite}/succeed ]; then
            succeedCases=$(ls ${results_path}/${one_suite}/succeed)
        fi
        if [ -e ${results_path}/${one_suite}/failed ]; then
            failCases=$(ls ${results_path}/${one_suite}/failed)
        fi
        if [ -n "$succeedCases" ]; then
            for one_case in $succeedCases; do
                printItem $one_suite $one_case "succeed"
            done
        fi
        if [ -n "$failCases" ]; then
            for one_case in $failCases; do
                if [[ "${ignoreFail[*]}"  =~ "${one_case}" ]]; then
                    printItem $one_suite $one_case "ignore"
                else
                    printItem $one_suite $one_case "failed"
                fi
            done
        fi
    done
    printLine $totalLen
}

function test_result_ana() {
    successNum=0
    for one_suite in ${run_suitecase[@]}; do
        checkFail=""
        if [ -e ${results_path}/${one_suite}/failed ]; then
            checkFail=$(ls ${results_path}/${one_suite}/failed/)
        fi

        if [ -e ${results_path}/${one_suite}/succeed ]; then
            tmpSuccessNum=$(ls ${results_path}/${one_suite}/succeed/ | wc -l)
            successNum=`expr $successNum + $tmpSuccessNum`
        fi

        for oneFail in ${checkFail[@]}; do
            if [[ "${ignoreFail[*]}"  =~ "${oneFail}" ]]; then
                echo "INFO: ignore $oneFail test fail"
                else
                echo "ERROR: run $oneFail test fail"
                exitCode=1
            fi
        done
    done

    if [ $successNum -eq 0 ]; then
        exitCode=1
    fi

    result_output
}

function run_test() {
    # 执行测试
    pushd "${run_test_dir}/mugen"
        # 安装测试执行依赖
        sh -x dep_install.sh -e

        if [[ $IMAGE_TYPE == "std" ]]; then
            # 为qemu配置一个可用的IP地址，防止有其他qemu已经占用IP
            last_ip_num=$(($RANDOM%250+2))
            can_ip_use=0
            for i in {1...10}; do
                ret=0
                ping "192.168.10.${last_ip_num}" -c 1 || can_ip_use=1
                if [ $can_ip_use -eq 1 ]; then
                    break;
                fi
            done
            if [ $can_ip_use -eq 0 ]; then
                echo "ERROR: can't get a ip set to qemu."
                exit 1
            fi
            last_pwd_num=$(($RANDOM%1000))
            # 启动qemu
            wait_login_str="openEuler Embedded(openEuler Embedded Reference Distro)"
            if [[ ${BUILD_BRANCH} == "openEuler-22.03-LTS" ]]; then
                wait_login_str="login:"
            fi

            sh -x qemu_ctl.sh start --qemu_type "${BUILD_ARCH}" \
                                    --passwd "openEuler@${last_pwd_num}" \
                                    --host_ip "192.168.10.1" \
                                    --qemu_ip "192.168.10.${last_ip_num}" \
                                    --put_all \
                                    --kernal_img_path "${run_test_dir}/image/${BUILD_ARCH}/zImage" \
                                    --initrd_path "${run_test_dir}/image/${BUILD_ARCH}/initrd" \
                                    --login_wait_str "${wait_login_str}" \
                                    --option_wait_time ${qemu_option_wait_time}
            rem_run_str="-s"
            need_env_str=""
        elif [[ $IMAGE_TYPE == "tiny" ]]; then
            mkdir -p conf
            echo '{
            "NODE": [
                {
                    "ID": 1,
                    "LOCALTION": "local",
                    "MACHINE": "physical",
                    "FRAME": "aarch64",
                    "NIC": "lo0",
                    "MAC": "",
                    "IPV4": "127.0.0.1",
                    "USER": "root",
                    "PASSWORD": "",
                    "SSH_PORT": 22,
                    "BMC_IP": "",
                    "BMC_USER": "",
                    "BMC_PASSWORD": ""
                }
            ]
        }'>> conf/env.json
            export FIND_TINY_DIR=${outputdir}
            rem_run_str=""
            need_env_str="-E"
        fi

        for one_suite in ${run_suitecase[@]}; do
            # 执行测试套编译准备
            bash mugen.sh -b ${one_suite}
            # set -e 后如果用例失败则会推出 这里改成所有都返回0 后面再统计
            echo "
            pushd "${run_test_dir}/mugen"
                bash mugen.sh -f ${one_suite} ${rem_run_str}
            popd
            exit 0
            ">> ${run_test_dir}/tmp_test_run_${one_suite}.sh
            sh -x ${run_test_dir}/tmp_test_run_${one_suite}.sh
            # 拷贝测试套执行结果
            if [ -e ${run_test_dir}/mugen/results/${one_suite} ]; then
                cp -Rrf ${run_test_dir}/mugen/results/${one_suite} ${results_path}/
            else
                continue
            fi
            rm -rf ${run_test_dir}/tmp_test_run_${one_suite}.sh
        done

        if [[ $IMAGE_TYPE == "std" ]]; then
            # 关闭qemu
            sh qemu_ctl.sh stop
        elif [[ $IMAGE_TYPE == "tiny" ]]; then
            rm -rf conf/env.json
        fi
    popd
}

function set_param() {
    IMAGE_TYPE=$1
    BUILD_ARCH=$2
    BUILD_BRANCH=$3
    IMAGE_OUT_DIR=$4
    TEST_WORK_DIR=$5
    run_suitecase=$6
    ignoreFail=$7
    qemu_option_wait_time=$8

    if [ -z $IMAGE_TYPE ]; then
        IMAGE_TYPE="std"
    fi
    if [ -z $BUILD_ARCH ]; then
        BUILD_ARCH="aarch64"
    fi
    if [ -z $BUILD_BRANCH ]; then
        BUILD_BRANCH="openEuler-22.09"
        if [[ ${BUILD_BRANCH} == "yocto_refactor" || ${BUILD_BRANCH} == "gitee_pages" ]]; then
            BUILD_BRANCH="master"
        fi
    fi
    if [ -z $IMAGE_OUT_DIR ]; then
        IMAGE_OUT_DIR="/usr1/output"
    fi
    if [ -z $TEST_WORK_DIR ]; then
        TEST_WORK_DIR="/usr1/ci_test"
        mkdir -p $TEST_WORK_DIR
    fi

    if [ -z $run_suitecase ]; then
        # 设置需要执行的测试套, 目前一致, 后面一定会不同
        if [[ $IMAGE_TYPE == "std" ]]; then
            run_suitecase=("embedded_security_config_test" "embedded_os_basic_test")
        elif [[ $IMAGE_TYPE == "tiny" ]]; then
            run_suitecase=("embedded_tiny_image_test")
        fi
    fi

    if [ -z $qemu_option_wait_time ]; then
        qemu_option_wait_time=180
    fi
}

function main() {
    br_nf_iptab_num=1
    if [ -e /proc/sys/net/bridge/bridge-nf-call-iptables ]; then
        br_nf_iptab_num=$(sudo cat /proc/sys/net/bridge/bridge-nf-call-iptables)
        echo 0 | sudo tee /proc/sys/net/bridge/bridge-nf-call-iptables
    fi

    set_param "$@"

    run_test_dir="${TEST_WORK_DIR}/test_run_dir_${BUILD_ARCH}_${IMAGE_TYPE}"
    SDK_INSTALL_PATH=${run_test_dir}/sdk/${BUILD_ARCH}

    # 清理现场 防止上次构建有残留
    if [[ -e  ${run_test_dir}/mugen/qemu_ctl.sh && -e  ${run_test_dir}/mugen/conf/qemu_info.json ]]; then
        sh ${run_test_dir}/mugen/qemu_ctl.sh stop
    fi
    # 删除工作目录
    rm -rf ${run_test_dir}/mugen
    rm -rf ${run_test_dir}/image
    rm -rf ${SDK_INSTALL_PATH}
    # 创建工作目录
    mkdir -p ${run_test_dir}/sdk
    mkdir -p ${run_test_dir}/image/${BUILD_ARCH}
    mkdir -p ${SDK_INSTALL_PATH}

    # 查找镜像并按照事件排序(防止给定路径有多个镜像)
    zImage_path=$(find ${IMAGE_OUT_DIR} -name "zImage" | xargs ls -ta | head -n 1)
    initrd_path=$(find ${IMAGE_OUT_DIR} -name "openeuler-image-*qemu-*.rootfs.cpio.gz" | xargs ls -ta)
    # initrd_path在22.09会有.live的也查找到
    for one_initrd in ${initrd_path[@]}; do
        if [[ "${one_initrd}" =~ "live" ]]; then
            continue
        else
            initrd_path=${one_initrd}
            break
        fi
    done
    cp -r ${zImage_path} ${run_test_dir}/image/${BUILD_ARCH}/zImage
    cp -r ${initrd_path} ${run_test_dir}/image/${BUILD_ARCH}/initrd
    # 查找并配置SDK
    if [[ $IMAGE_TYPE == "std" ]]; then
        toolchain_path=$(find ${IMAGE_OUT_DIR} -name "openeuler-glibc-*-toolchain-*.sh")
        cp -r ${toolchain_path} ${run_test_dir}/sdk/toolchain.sh

        # 配置sdk
        sh ${run_test_dir}/sdk/toolchain.sh <<EOF
${SDK_INSTALL_PATH}
Y
EOF

        environment_script=$(find ${SDK_INSTALL_PATH} -name "environment-setup-*-openeuler-*")
        for one_env_script in ${environment_script[@]}; do
            source ${one_env_script}
        done

        # openEuler-22.03-LTS分支需要手动执行编译, master分支已经可以在source时自动执行
        if [[ $BUILD_BRANCH == "openEuler-22.03-LTS" ]]; then
            kernel_src_path=$(find   ${SDK_INSTALL_PATH}/sysroots -name "kernel" | grep "usr/src/kernel")
            cd ${kernel_src_path}
            make modules_prepare
        fi
    fi

    # 下载测试框架
    git clone https://gitee.com/openeuler/mugen.git ${run_test_dir}/mugen

    cd ${run_test_dir}
    # 创建多测试套结果保存文件夹
    results_path="${run_test_dir}/results"
    rm -rf ${results_path}
    mkdir -p ${results_path}

    run_test
    test_result_ana

    echo ${br_nf_iptab_num} | sudo tee /proc/sys/net/bridge/bridge-nf-call-iptables

    exit $exitCode
}

main "$@"
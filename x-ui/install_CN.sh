#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

# check root
[[ $EUID -ne 0 ]] && echo -e "${RED}错误：${PLAIN} 必须使用root用户运行此脚本！\n" && exit 1

# check os
if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif cat /etc/issue | grep -Eqi "debian"; then
    release="debian"
elif cat /etc/issue | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /etc/issue | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
elif cat /proc/version | grep -Eqi "debian"; then
    release="debian"
elif cat /proc/version | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /proc/version | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
else
    echo -e "${RED}未检测到系统版本，请联系脚本作者！${PLAIN}\n" && exit 1
fi

arch=$(arch)

if [[ $arch == "i386" || $arch == "i686" ]]; then
    arch="386"
elif [[ $arch == "x86_64" || $arch == "x64" || $arch == "amd64" ]]; then
    arch="amd64"
elif [[ $arch == "aarch64" || $arch == "arm64" ]]; then
    arch="arm64"
elif [[ $arch == "s390x" ]]; then
    arch="s390x"
else
    arch="amd64"
    echo -e "${RED}检测架构失败，使用默认架构: ${arch}${PLAIN}"
fi

echo "架构: ${arch}"

if [ $(getconf WORD_BIT) != '32' ] && [ $(getconf LONG_BIT) != '64' ]; then
    echo "本软件不支持 32 位系统(x86)，请使用 64 位系统(x86_64)，如果检测有误，请联系作者"
    exit -1
fi

os_version=""

# os version
if [[ -f /etc/os-release ]]; then
    os_version=$(awk -F'[= ."]' '/VERSION_ID/{print $3}' /etc/os-release)
fi
if [[ -z "$os_version" && -f /etc/lsb-release ]]; then
    os_version=$(awk -F'[= ."]+' '/DISTRIB_RELEASE/{print $2}' /etc/lsb-release)
fi

if [[ x"${release}" == x"centos" ]]; then
    if [[ ${os_version} -le 6 ]]; then
        echo -e "${RED}请使用 CentOS 7 或更高版本的系统！${PLAIN}\n" && exit 1
    fi
elif [[ x"${release}" == x"ubuntu" ]]; then
    if [[ ${os_version} -lt 16 ]]; then
        echo -e "${RED}请使用 Ubuntu 16 或更高版本的系统！${PLAIN}\n" && exit 1
    fi
elif [[ x"${release}" == x"debian" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        echo -e "${RED}请使用 Debian 8 或更高版本的系统！${PLAIN}\n" && exit 1
    fi
fi

install_base() {
    if [[ x"${release}" == x"centos" ]]; then
        yum install wget curl tar -y
    else
        apt-get update
        apt install wget curl tar -y
    fi
}

#This function will be called when user installed x-ui out of sercurity
config_after_install() {
    echo -e "${YELLOW}出于安全考虑，安装/更新完成后需要强制修改端口与账户密码${PLAIN}"
    read -p "确认是否继续? [y/n]: " config_confirm
    if [[ x"${config_confirm}" == x"y" || x"${config_confirm}" == x"Y" ]]; then
        read -p "请设置您的账户名（如未填写则随机8位字符）: " config_account
        [[ -z $config_account ]] && config_account=$(date +%s%N | md5sum | cut -c 1-8)
        echo -e "${YELLOW}您的账户名将设定为:${config_account}${PLAIN}"
        read -p "请设置您的账户密码（如未填写则随机8位字符）: " config_password
        [[ -z $config_password ]] && config_password=$(date +%s%N | md5sum | cut -c 1-8)
        echo -e "${YELLOW}您的账户密码将设定为:${config_password}${PLAIN}"
        read -p "请设置面板访问端口（如未填写则随机端口号）: " config_port
        [[ -z $config_port ]] && config_port=$(shuf -i 2000-65535 -n 1)
        until [[ -z $(ss -ntlp | awk '{print $4}' | sed 's/.*://g' | grep -w "$port") ]]; do
            if [[ -n $(ss -ntlp | awk '{print $4}' | sed 's/.*://g' | grep -w "$port") ]]; then
                echo -e "${RED} $config_port ${PLAIN} 端口已经其他程序占用，请更换面板端口号"
                read -p "请设置面板访问端口（如未填写则随机端口号）: " config_port
                [[ -z $config_port ]] && config_port=$(shuf -i 2000-65535 -n 1)
            fi
        done
        echo -e "${YELLOW}您的面板访问端口将设定为:${config_port}${PLAIN}"
        echo -e "${YELLOW}确认设定,设定中${PLAIN}"
        /usr/local/x-ui/x-ui setting -username ${config_account} -password ${config_password}
        echo -e "${YELLOW}账户密码设定完成${PLAIN}"
        /usr/local/x-ui/x-ui setting -port ${config_port}
        echo -e "${YELLOW}面板端口设定完成${PLAIN}"
    else
        config_port=$(/usr/local/x-ui/x-ui setting -show | sed -n 4p | awk -F ": " '{print $2}')
        echo -e "${RED}已取消, 所有设置项均为默认设置, 请及时修改${PLAIN}"
    fi
}

install_x-ui() {
    systemctl stop x-ui
    cd /usr/local/

    if [ $# == 0 ]; then
        last_version=$(curl -Ls "https://api.github.com/repos/sing-web/x-ui/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ ! -n "$last_version" ]]; then
            echo -e "${RED}检测 x-ui 版本失败，可能是超出 Github API 限制，请稍后再试，或手动指定 x-ui 版本安装${PLAIN}"
            exit 1
        fi
        echo -e "检测到 x-ui 最新版本：${last_version}，开始安装"
        wget -N --no-check-certificate -O /usr/local/x-ui-linux-${arch}.tar.gz https://github.com/sing-web/x-ui/releases/download/${last_version}/x-ui-linux-${arch}.tar.gz
        if [[ $? -ne 0 ]]; then
            echo -e "${RED}下载 x-ui 失败，请确保你的服务器能够下载 Github 的文件${PLAIN}"
            exit 1
        fi
    else
        last_version=$1
        url="https://github.com/sing-web/x-ui/releases/download/${last_version}/x-ui-linux-${arch}.tar.gz"
        echo -e "开始安装 x-ui $1"
        wget -N --no-check-certificate -O /usr/local/x-ui-linux-${arch}.tar.gz ${url}
        if [[ $? -ne 0 ]]; then
            echo -e "${RED}下载 x-ui $1 失败，请确保此版本存在${PLAIN}"
            exit 1
        fi
    fi

    if [[ -e /usr/local/x-ui/ ]]; then
        rm /usr/local/x-ui/ -rf
    fi

    tar zxvf x-ui-linux-${arch}.tar.gz
    rm x-ui-linux-${arch}.tar.gz -f
    cd x-ui
    chmod +x x-ui bin/xray-linux-${arch}
    cp -f x-ui.service /etc/systemd/system/
    wget --no-check-certificate -O /usr/bin/x-ui https://raw.githubusercontent.com/sing-web/x-ui/main/x-ui_CN.sh
    chmod +x /usr/local/x-ui/x-ui.sh
    chmod +x /usr/bin/x-ui
    config_after_install
    #echo -e "如果是全新安装，默认网页端口为 ${GREEN}54321${PLAIN}，用户名和密码默认都是 ${GREEN}admin${PLAIN}"
    #echo -e "请自行确保此端口没有被其他程序占用，${YELLOW}并且确保 54321 端口已放行${PLAIN}"
    #    echo -e "若想将 54321 修改为其它端口，输入 x-ui 命令进行修改，同样也要确保你修改的端口也是放行的"
    #echo -e ""
    #echo -e "如果是更新面板，则按你之前的方式访问面板"
    #echo -e ""
    systemctl daemon-reload
    systemctl enable x-ui
    systemctl start x-ui
    
    systemctl stop warp-go >/dev/null 2>&1
    wg-quick down wgcf >/dev/null 2>&1
    ipv4=$(curl -s4m8 ip.p3terx.com -k | sed -n 1p)
    ipv6=$(curl -s6m8 ip.p3terx.com -k | sed -n 1p)
    systemctl start warp-go >/dev/null 2>&1
    wg-quick up wgcf >/dev/null 2>&1
    echo -e "${GREEN}x-ui ${last_version}${PLAIN} 安装完成，面板已启动"
    echo -e ""
    echo -e "x-ui 管理脚本使用方法: "
    echo -e "----------------------------------------------"
    echo -e "x-ui              - 显示管理菜单 (功能更多)"
    echo -e "x-ui start        - 启动 x-ui 面板"
    echo -e "x-ui stop         - 停止 x-ui 面板"
    echo -e "x-ui restart      - 重启 x-ui 面板"
    echo -e "x-ui status       - 查看 x-ui 状态"
    echo -e "x-ui enable       - 设置 x-ui 开机自启"
    echo -e "x-ui disable      - 取消 x-ui 开机自启"
    echo -e "x-ui log          - 查看 x-ui 日志"
    echo -e "x-ui update       - 更新 x-ui 面板"
    echo -e "x-ui install      - 安装 x-ui 面板"
    echo -e "x-ui uninstall    - 卸载 x-ui 面板"
    echo -e "----------------------------------------------"
    echo ""
    if [[ -n $ipv4 ]]; then
        echo -e "${YELLOW}面板IPv4访问地址为：${PLAIN} ${GREEN}http://$ipv4:$config_port ${PLAIN}"
    fi
    if [[ -n $ipv6 ]]; then
        echo -e "${YELLOW}面板IPv6访问地址为：${PLAIN} ${GREEN}http://[$ipv6]:$config_port ${PLAIN}"
    fi
    echo -e "请自行确保此端口没有被其他程序占用，${YELLOW}并且确保${PLAIN} ${RED} $config_port ${PLAIN} ${YELLOW}端口已放行${PLAIN}"
}

echo -e "${GREEN}开始安装${PLAIN}"
install_base
install_x-ui $1
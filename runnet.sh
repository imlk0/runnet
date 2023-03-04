#!/bin/bash

outer_addr=''
outer_addr_mask=''
inner_addr=''
inner_addr_mask=''
net_ns_name="rn$$"
veth_outer_name="${net_ns_name}_vo"
veth_inner_name="${net_ns_name}_vi"

need_internet=0
cmd_user=
publish_list=()
forward_list=()

in_subnet() {
    local subnet mask subnet_split ip_split subnet_mask subnet_start subnet_end ip rval
    local readonly BITMASK=0xFFFFFFFF

    IFS=/ read subnet mask <<<"${1}"
    IFS=. read -a subnet_split <<<"${subnet}"
    IFS=. read -a ip_split <<<"${2}"

    subnet_mask=$(($BITMASK << $((32 - $mask)) & $BITMASK))
    subnet_start=$((${subnet_split[0]} << 24 | ${subnet_split[1]} << 16 | ${subnet_split[2]} << 8 | ${subnet_split[3]} & ${subnet_mask}))
    subnet_end=$(($subnet_start | ~$subnet_mask & ${BITMASK}))
    ip=$((${ip_split[0]} << 24 | ${ip_split[1]} << 16 | ${ip_split[2]} << 8 | ${ip_split[3]} & ${BITMASK}))

    (($ip >= $subnet_start)) && (($ip <= $subnet_end)) && rval=0 || rval=1
    return ${rval}
}

setup_addr() {
    local ip ok
    for ip_num in {0..255}; do
        ip="192.168.${ip_num}.1"
        ok=1
        for subnet in $(ip addr | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9][0-9]?\b"); do
            in_subnet ${subnet} ${ip} && {
                ok=0
                break
            }
        done
        if [[ ${ok} -eq 1 ]]; then
            outer_addr="192.168.${ip_num}.1"
            outer_addr_mask=24
            inner_addr="192.168.${ip_num}.2"
            inner_addr_mask=24
            return
        fi
    done
    error "Unable to find unused subnet in range 192.168.0.0 - 192.168.255.0, please customize it"
    exit 1
}

# start up env
start_up() {
    # add net namespace
    ip netns add ${net_ns_name}

    # add veth
    ip link add ${veth_outer_name} type veth peer name ${veth_inner_name}
    # setup veth_outer
    ip link set ${veth_outer_name} up
    ip addr add ${outer_addr}/${outer_addr_mask} dev ${veth_outer_name}

    # setup veth_inner
    ip link set ${veth_inner_name} netns ${net_ns_name}
    ip netns exec ${net_ns_name} ip link set ${veth_inner_name} up
    ip netns exec ${net_ns_name} ip addr add ${inner_addr}/${inner_addr_mask} dev ${veth_inner_name}
    # enable loopback
    ip netns exec ${net_ns_name} ip link set lo up

    if [[ ${need_internet} -eq 1 ]]; then
        # add default route
        ip netns exec ${net_ns_name} ip route add default via ${outer_addr}
        # enable NAT
        bash -c "echo 1 > /proc/sys/net/ipv4/ip_forward"
        iptables -t nat -A POSTROUTING -s ${inner_addr}/${inner_addr_mask} ! -o ${veth_outer_name} -j MASQUERADE
        iptables -t filter -A FORWARD -i any -o ${veth_outer_name} -j ACCEPT
        iptables -t filter -A FORWARD -i ${veth_outer_name} -o ${veth_outer_name} -j ACCEPT
        iptables -t filter -A FORWARD -i ${veth_outer_name} ! -o ${veth_outer_name} -j ACCEPT
    fi
}

# shut down env
shut_down() {
    if [[ ${need_internet} -eq 1 ]]; then
        # disable NAT
        iptables -t nat -D POSTROUTING -s ${inner_addr}/${inner_addr_mask} ! -o ${veth_outer_name} -j MASQUERADE
        iptables -t filter -D FORWARD -i any -o ${veth_outer_name} -j ACCEPT
        iptables -t filter -D FORWARD -i ${veth_outer_name} -o ${veth_outer_name} -j ACCEPT
        iptables -t filter -D FORWARD -i ${veth_outer_name} ! -o ${veth_outer_name} -j ACCEPT
    fi
    # delete veth
    ip link delete ${veth_outer_name}
    # delete net namespace
    ip netns delete ${net_ns_name}
}

setup_port_mapping() {
    for publish in ${publish_list[@]}; do
        type=
        if [[ ${type} == */* ]]; then
            type=${publish##*/}
        fi
        type=${type:-"tcp"}
        port_map=${publish%/*}
        port_src=${port_map%:*}
        port_dest=${inner_addr}:${port_map##*:}
        info "publish: host[0.0.0.0:${port_src}]\t--(${type})->\tcontainer[${port_dest}]"
        socat -lf/dev/null ${type}-listen:${port_src},fork ${type}:${port_dest} &
    done

    for forward in ${forward_list[@]}; do
        type=
        if [[ ${type} == */* ]]; then
            type=${forward##*/}
        fi
        type=${type:-"tcp"}
        port_map=${forward%/*}
        port_src=${port_map%:*}
        port_dest=${port_map##*:}
        if [[ ${port_src} != *:* ]]; then
            port_src=127.0.0.1:${port_src}
        fi
        info "forward: host[${port_src}]\t<-(${type})--\tcontainer[0.0.0.0:${port_dest}]"
        unix_file="/tmp/runnet$$_${type}_${port_src}_${port_dest}"
        socat -lf/dev/null unix-listen:\"${unix_file}\",fork ${type}:${port_src} &
        ip netns exec ${net_ns_name} socat -lf/dev/null ${type}-listen:${port_dest},fork unix-connect:\"${unix_file}\" &
    done
}

do_install() {
    script_path=$(realpath $0)
    echo "install -m 755 ${script_path} /usr/local/bin/runnet"
    install -m 755 ${script_path} /usr/local/bin/runnet
}

kill_this() {
    shut_down
    pkill -P $$
}

error() {
    echo -e "[error] $1"
}

info() {
    echo -e "[info] $1"
}

warning() {
    echo -e "[warning] $1"
}

usage() {
    echo "Run cmd in a isolation network namespace."
    echo ""
    echo "usage:"
    echo "    runnet [options] <cmd>"
    echo "options:"
    echo "    --install                           Copy this script to /usr/local/bin/runnet"
    echo ""
    echo "    --internet                          Enable Internet access"
    echo "    --user=<username>                   The user that the program runs as."
    echo "    --forward=[host:]<port>:<port>      Forward a external port([host:]<port>) to the inside the container."
    echo "    --publish=<port>:<port>             Publish the port inside the container to the host."
    echo "    --outer-addr=<addr>/<mask>          Specific the address & mask of host side interface."
    echo "    --inner-addr=<addr>/<mask>          Specific the address & mask of container side interface."
    echo "    --netns=<netns_name>                Specific the name of created network namespace. A random name will be used if not set."
}

if [[ $# -eq 0 ]]; then
    usage
    exit 1
fi

if [[ ${EUID} -ne 0 ]]; then
    error "This script must be run as root"
    exit 1
fi

while true; do
    case $1 in
    --internet) # need internet access
        need_internet=1
        shift
        ;;
    --user=*)
        cmd_user=${1:7}
        shift
        ;;
    --publish=*:*)
        publish_list+=(${1:10})
        shift
        ;;
    --forward=*:*)
        forward_list+=(${1:10})
        shift
        ;;
    --outer-addr=*/*)
        _addr=${1:13}
        outer_addr="${_addr/\/*/}"
        outer_addr_mask="${_addr/*\//}"
        shift
        ;;
    --inner-addr=*/*)
        _addr=${1:13}
        inner_addr="${_addr/\/*/}"
        inner_addr_mask="${_addr/*\//}"
        shift
        ;;
    --netns=*)
        net_ns_name=${1:8}
        veth_outer_name="${net_ns_name:0:12}_vo"
        veth_inner_name="${net_ns_name:0:12}_vi"
        shift
        ;;
    --install)
        do_install
        exit 0
        ;;
    -)
        shift
        break
        ;;
    -*)
        usage
        exit 1
        ;;
    *)
        break
        ;;
    esac
done

if { [[ ${inner_addr} == "" ]] || [[ ${outer_addr} == "" ]]; } && [[ "${inner_addr}${outer_addr}" != "" ]]; then
    error "--inner-addr and --outer-addr should be set or not set at the same time"
    exit 1
fi

if [[ "${inner_addr}${outer_addr}" == "" ]]; then
    setup_addr
fi

trap kill_this EXIT

start_up
setup_port_mapping

cmd="$*"

if [[ ${cmd_user} == "" ]]; then
    cmd_user=${SUDO_USER}
fi
if [[ ${cmd_user} != "" ]]; then
    cmd="sudo -u ${cmd_user} --shell ${cmd}"
else
    warning "\${SUDO_USER} is empty and cmd will run as root"
fi

ip netns exec ${net_ns_name} sysctl net.ipv4.ping_group_range="$(sudo sysctl net.ipv4.ping_group_range -b)" -q

ip netns exec ${net_ns_name} ${cmd}


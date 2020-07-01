
OUTER_ADDR=''
INNER_ADDR=''
NET_NS_NAME="runnet$$"
VETH_OUTER_NAME="runnet_vo$$"
VETH_INNER_NAME="runnet_vi$$"
OUT_INTERFACE=''

# sudo ip netns exec ${NET_NS_NAME} sudo -u imlk bash

# --publish=7474:7474
# -u root
# --internet
# --out-if=


in_subnet() {
    local subnet mask subnet_split ip_split subnet_mask subnet_start subnet_end ip rval
    local readonly BITMASK=0xFFFFFFFF

    IFS=/ read subnet mask <<< "${1}"
    IFS=. read -a subnet_split <<< "${subnet}"
    IFS=. read -a ip_split <<< "${2}"

    subnet_mask=$(($BITMASK<<$((32-$mask)) & $BITMASK))
    subnet_start=$((${subnet_split[0]} << 24 | ${subnet_split[1]} << 16 | ${subnet_split[2]} << 8 | ${subnet_split[3]} & ${subnet_mask}))
    subnet_end=$(($subnet_start | ~$subnet_mask & ${BITMASK}))
    ip=$((${ip_split[0]} << 24 | ${ip_split[1]} << 16 | ${ip_split[2]} << 8 | ${ip_split[3]} & ${BITMASK}))

    (( $ip >= $subnet_start )) && (( $ip <= $subnet_end )) && rval=0 || rval=1
    return ${rval}
}


setup_addr(){
    local ip ok
    for ip_num in {0..255}; do
        ip="192.168.${ip_num}.1"
        ok=1
        for subnet in `ip addr | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\/[0-9][0-9]?\b"`; do
            in_subnet ${subnet} ${ip} && { ok=0; break; }
        done
        if [[ ${ok} -eq 1 ]]; then
            OUTER_ADDR="192.168.${ip_num}.1"
            INNER_ADDR="192.168.${ip_num}.2"
            return
        fi
    done
    error "Unable to find unused subnet in range 192.168.0.0 - 192.168.255.0, please customize it" || exit 1
}


setup_interface(){
    local dev
    dev=`ip -4 route list 0/0 | cut -d ' ' -f 5`
    if [[ ${dev} == "" ]]; then
        error "Can not identify the default gateway interface. You must specify it by --out-if" || exit 1
    fi
    OUT_INTERFACE=$dev
}

# start up env
start_up(){
    # add net namespace
    ip netns add ${NET_NS_NAME}

    # add veth
    ip link add ${VETH_OUTER_NAME} type veth peer name ${VETH_INNER_NAME}
    # setup veth_outer
    ip link set ${VETH_OUTER_NAME} up
    ip addr add ${OUTER_ADDR}/24 dev ${VETH_OUTER_NAME}

    # setup veth_inner
    ip link set ${VETH_INNER_NAME} netns ${NET_NS_NAME}
    ip netns exec ${NET_NS_NAME} ip link set ${VETH_INNER_NAME} up
    ip netns exec ${NET_NS_NAME} ip addr add ${INNER_ADDR}/24 dev ${VETH_INNER_NAME}
    # enable loopback
    ip netns exec ${NET_NS_NAME} ip link set lo up

    # add default route
    ip netns exec ${NET_NS_NAME} ip route add default via ${OUTER_ADDR}
    # enable NAT
    bash -c "echo 1 > /proc/sys/net/ipv4/ip_forward"
    iptables -t nat -A POSTROUTING -s ${INNER_ADDR}/24 -o ${OUT_INTERFACE} -j MASQUERADE
    iptables -t filter -A FORWARD -i ${OUT_INTERFACE} -o ${VETH_OUTER_NAME} -j ACCEPT
    iptables -t filter -A FORWARD -o ${OUT_INTERFACE} -i ${VETH_OUTER_NAME} -j ACCEPT
}


# shut down env
shut_down(){
    # disable NAT
    iptables -t nat -D POSTROUTING -s ${INNER_ADDR}/24 -o ${OUT_INTERFACE} -j MASQUERADE
    iptables -t filter -D FORWARD -i ${OUT_INTERFACE} -o ${VETH_OUTER_NAME} -j ACCEPT
    iptables -t filter -D FORWARD -o ${OUT_INTERFACE} -i ${VETH_OUTER_NAME} -j ACCEPT

    # delete veth
    ip link delete ${VETH_OUTER_NAME}
    # delete net namespace
    ip netns delete ${NET_NS_NAME}
}


error(){
    echo "[error] $1"
}

warning(){
    echo "[warning] $1"
}

usage(){
    echo "This is usage part"
}


if [[ ${EUID} -ne 0 ]]; then
    error "This script must be run as root"; exit 1
fi

if [[ $# -eq 0 ]]; then
    usage; exit 1
fi

setup_addr
setup_interface

start_up
cmd="$*"
if [[ ${SUDO_USER} != "" ]]; then
    cmd="sudo -u ${SUDO_USER} ${cmd}"
else
    warning "\${SUDO_USER} is empty and cmd will run as root"
fi
ip netns exec ${NET_NS_NAME} ${cmd}

shut_down



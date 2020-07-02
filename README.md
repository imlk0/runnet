# 🔀netrun

This is a lightweight container script that allows programs to run in an separate environment with a virtual network interface. It implements network interface isolation and bidirectional port mapping based on the network namespace.

Using this tool, you can avoid the conflict of listening ports. And you can also map the listening port of the program to any port

# Install

Dependencies:

- Linux >= 2.6.24 (support of network namespace)
- `bash`
- `iptables`
- `socat`

Install step:

1. Clone this project.
2. You can use the script `./runnet.sh` directly. 

    Or you can use the following command to copy the script into `/usr/local/bin/runnet`. Then you can use `runnet` command from anywhere.
    ```
    bash ./runnet.sh --install
    ```

# Usage
```
usage:
    runnet [options] <cmd>
options:
    --install                           Copy this script to /usr/local/bin/runnet

    --internet                          Enable Internet access, By default, there is no Internet access in the container.
    --out-if=<interface>                Specify the default network interface, only required if --internet is specified.
    --user=<username>                   The user that the program runs as. By default, we will read username from ${SUDO_USER}. If ${SUDO_USER} is empty, we will run program as root.
    --forward=[host:]<port1>:<port2>    Forward a external port([host:]<port1>) to <port2> inside the container.
    --publish=<port1>:<port2>           Publish the <port2> inside the container to the host <port1>.
```

# Example

- Start a program in the new namespace directly in the following way:

  ```
  sudo runnet ifconfig
  ```

  output:

  ```
  lo: flags=73<UP,LOOPBACK,RUNNING>  mtu 65536
          inet 127.0.0.1  netmask 255.0.0.0
          inet6 ::1  prefixlen 128  scopeid 0x10<host>
          loop  txqueuelen 1000  (Local Loopback)
          RX packets 0  bytes 0 (0.0 B)
          RX errors 0  dropped 0  overruns 0  frame 0
          TX packets 0  bytes 0 (0.0 B)
          TX errors 0  dropped 0 overruns 0  carrier 0  collisions 0
  
  runnet93735_vi: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1500
          inet 192.168.1.2  netmask 255.255.255.0  broadcast 0.0.0.0
          inet6 fe80::3c0e:8bff:fe31:65c5  prefixlen 64  scopeid 0x20<link>
          ether 3e:0e:8b:31:65:c5  txqueuelen 1000  (Ethernet)
          RX packets 1  bytes 90 (90.0 B)
          RX errors 0  dropped 0  overruns 0  frame 0
          TX packets 1  bytes 90 (90.0 B)
          TX errors 0  dropped 0 overruns 0  carrier 0  collisions 0
  ```
  
- Start a SpringBoot backend program listening on port `8080`. Enable Internet access. Then publish port `8080` from container to the host port `80`, and forward the mysql service port(`3306`) from the host to the container(`3306`).
    ```shell
    sudo runnet --internet --publish=80:8080 --forward=3306:3306 ./gradlew bootRun
    ```
    Then, you can access the backend from `http://localhost:80/`, and the program is actually listening on port `8080`.
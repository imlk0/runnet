# netrun

This is a lightweight container script that implements network interface isolation based on network namespace. The program will run in an environment with a separate virtual network interface. port mapping in both directions is implemented.

# Install


# Usage
```
usage:
    runnet [options] <cmd>
options:
    --internet                          Enable Internet access
    --out-if=<interface>                Specify the default network interface, only required if --internet is specified.
    --user=<username>                   The user that the program runs as.
    --forward=[host:]<port>:<port>      Forward a external port([host:]<port>) to the inside the container.
    --publish=<port>:<port>             Publish the port inside the container to the host.
```


# Example
```shell
sudo bash ./runnet.sh  --internet --publish=8080:9999 --publish=80:9998 --forward=3306:3306 --forward=80:1080 bash
```
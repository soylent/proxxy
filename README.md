# proxxxy

HTTPS & SOCKS5 Proxy

## Installation

    gem install proxxxy

## Usage

By default, proxxxy starts an HTTPS proxy server on port 3128.

    proxxxy

Send a request through the proxy server. Note the `-p` (proxy tunnel) flag.

    curl -px https://127.0.0.1:3128 https://www.google.com

You can start several proxy servers.

    proxxxy https://0.0.0.0:3128 socks5://127.0.0.1:1080

For more details please run:

    proxxxy --help

## Logging

Example output:

    2020-12-23T20:39:59.300-07:00 127.0.0.1 43878 www.google.com 80 socks5 success 78
    2020-12-23T20:42:07.560-07:00 127.0.0.1 43900 www.google.com 443 https success 844

Log messages are printed to stdout in DSV format. Values are separated by space,
and each row contains:

1. Timestamp in ISO 8601
1. Client address
1. Client port
1. Server address
1. Server port
1. Proxy type: https or socks5
1. Status: success or failure
1. Comment: number of proxied bytes if success or error message if failure

The `--quiet` option disables logging.

## FAQ

* Errno::EADDRNOTAVAIL (Cannot assign requested address - bind(2) for "::1" port 3000)

  Make sure that IPv6 is enabled. To check if it's disabled, run:

      sudo sysctl -a | grep disable_ipv6

## Development

Pull requests are welcome!

To run tests, install `cutest` and execute:

    cutest test/proxxxy.rb

To run benchmark:

    ./benchmark

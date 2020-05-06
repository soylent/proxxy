# proxxxy

HTTPS Proxy

## Installation

```sh
gem install proxxxy
```

## Usage

Start proxy server:

```sh
proxxxy
```

Send a request through the proxy server. Note the `-p` (proxy tunnel) flag.

```sh
curl -px http://127.0.0.1:3128 https://www.google.com
```

For more details please run:

```sh
proxxxy --help
```

## Logging

Log messages are printed to stdout in DSV format. Values are separated by space,
and each row contains:

1. Timestamp in ISO 8601
2. Client address
3. Server address
4. Status: success or failure
5. Comment: number of proxied bytes if success or error message if failure

The `--quiet` option disables logging.

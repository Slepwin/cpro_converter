# CryptoPRO storage converter to PEM

This tool is used to extract private key from CryptoPRO storage format using GOST R 34.10-2012 format

Storage is a folder with files:
```
header.key
masks.key
masks2.key
name.key
primary.key
primary2.key
```

## Requirements and dependencies

CPU arhictecture:
* x86_64 (amd64)
* arm64 (aarch64)  

OS:
* Linux
* MacOS

Software:
* [Docker version 24.0.7](https://www.docker.com)

Based on:
1. [alpine 3.20.3](https://alpinelinux.org)
2. [openssl 3.0.15](https://github.com/openssl/openssl)
3. [gost engine 3.0.3](https://github.com/gost-engine/engine)
4. [curl 8.10.1](https://github.com/curl/curl)

## Building Image

To build image run:

```
docker build -t cpro_converter ./
```

## How to use


Change path `~/storage.001` to your storage path
and run:
```
docker run --rm -ti -v ~/storage.001:/usr/local/src/storage.001 cpro_converter storage.001
```

Your key will be output to stdout


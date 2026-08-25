# 01 — OS and Toolchain (100% identical configuration)

> Source: collected from the real iPhone iSH device via `apk list --installed` /
> `pip3 list` / `npm ls -g` / `env` (2026-08-24).

---

## 1.1 Base system

```
Alpine Linux v3.21.0 (VERSION_ID=3.21.0)
musl libc 1.2.5 (no glibc)
BusyBox v1.37.0 (busybox-1.37.0-r8)
Arch: aarch64 (x86_64 also works on a computer — switch the binary accordingly)
```

## 1.2 apk package list (146 packages, complete)

The following is the one-shot install command (all package names; `apk add` pulls dependencies
automatically):

```sh
apk add --no-cache \
  alpine-baselayout alpine-baselayout-data alpine-keys alpine-release apk-tools \
  bash binutils brotli-libs busybox busybox-binsh c-ares ca-certificates \
  ca-certificates-bundle cairo curl fd file fontconfig freetype gcc gdbm git \
  git-init-template gmp htop icu-data-en icu-libs isl26 jansson jq lcms2 \
  libatomic libbsd libbz2 libcrypto3 libcurl libdw libedit libelf libevent \
  libexpat libffi libgcc libgfortran libgomp libidn2 libimagequant libjpeg-turbo \
  libmagic libmd libncursesw libpanelw libpng libpsl libsharpyuv libssl3 \
  libstdc++ libunistring libwebp libwebpdemux libwebpmux libx11 libxau libxcb \
  libxdmcp libxext libxrender mpc1 mpdecimal mpfr4 musl musl-dev musl-fts \
  musl-utils ncurses-terminfo-base nghttp2-libs nodejs npm nspr nss oniguruma \
  openblas openjpeg openssh-client-common openssh-client-default openssh-keygen \
  pcre2 pixman poppler poppler-utils py3-contourpy py3-cycler py3-dateutil \
  py3-fonttools py3-kiwisolver py3-markdown py3-matplotlib py3-numpy \
  py3-packaging py3-parsing py3-pillow py3-pip py3-pypdf py3-setuptools py3-six \
  python3 qhull readline ripgrep scanelf simdjson simdutf sqlite sqlite-libs \
  ssl_client strace tiff tmux vim vim-common wget xxd xz-libs zlib zstd-libs
```

> Note: `gcc` + `musl-dev` were installed on 2026-08-23 for writing the C reproducer (debug use).
> `strace` is installed but unusable on iSH (PTRACE unsupported); it works normally on a computer.
> `file` is also debug-related.

### Minimal set (core tools only, without image/math libraries)

```sh
apk add --no-cache bash git jq curl wget file ripgrep fd sqlite htop tmux vim \
  python3 py3-pip nodejs npm openssh-client gcc musl-dev strace
```

## 1.3 pip packages (complete list)

```
agent-slides==0.1.0a0      (leftover from the disabled PPT package, optional)
annotated-types==0.8.0
anyio==4.14.2
attrs==26.1.0
beautifulsoup4==4.15.0
brotli==1.2.0
bs4==0.0.2
certifi==2026.7.22
cffi==2.1.1
charset-normalizer==3.5.1
click==8.4.2
contourpy==1.3.0
cryptography==50.0.0
cycler==0.12.1
ddgs==9.15.0               (DDG search, disabled, optional)
duckduckgo_search==8.1.1   (same, disabled)
fake-useragent==2.2.0
fonttools==4.55.0
h11==0.16.0
h2==4.4.1
hpack==4.2.0
httpcore==1.0.9
httpcore2==2.12.0
httpx==0.28.1
httpx2==2.12.0
hyperframe==6.1.0
idna==3.19
jsonschema==4.26.0
```
(The above is the first 30 lines of `pip3 list`; export the full list on iSH with
`pip3 freeze > requirements.txt`)

Core pip packages:
```sh
pip3 install python-pptx beautifulsoup4 httpx fake-useragent
```

## 1.4 npm global

```
@modelcontextprotocol/server-brave-search@0.6.2   (Brave MCP, removed/disabled, optional)
```

## 1.5 Environment variables (complete, non-sensitive)

```sh
export BROWSER=/usr/local/bin/minis-open     # Minis-specific, skip on a computer
export CHARSET=UTF-8
export ENV=/etc/profile
export GODEBUG=asyncpreemptoff=1             # iSH Go runtime setting, skip on a computer
export GOMAXPROCS=2
export HOME=/root
export LANG=C.UTF-8
export NO_COLOR=1
export OPENSSL_armcap=0                      # iSH-specific (disable ARM crypto instruction detection)
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/opt/bin
export PIP_PROGRESS_BAR=off
export PYTHONDONTWRITEBYTECODE=1
export PYTHONMALLOC=malloc                   # iSH-specific
export TERM=xterm-256color
export TZ=LCL-8
export UV_THREADPOOL_SIZE=1
```

> These env vars are set in the shell profile: `/etc/profile` or `~/.profile`.
> The ones marked "iSH-specific" do not need to be copied on a computer
> (GODEBUG/OPENSSL_armcap/PYTHONMALLOC were set on iSH to work around emulation-layer issues).

## 1.6 Toolchain verification commands

```sh
apk --version && bash --version | head -1 && python3 --version && node -v && npm -v
which git jq curl wget rg fd sqlite3 htop tmux vim gcc strace
```

If everything outputs something, the toolchain is complete.

---

## 1.7 Key differences between iSH and real Linux (environment layer)

| Item | iSH | Real Linux on a computer |
|---|---|---|
| ring TLS | handshake fails | works |
| OpenSSL | works (so the bridge uses OpenSSL) | works |
| strace | does not work (PTRACE_SETOPTIONS EINVAL) | works |
| fork/spawn | intermittent issues + waitid(P_PIDFD) EINVAL | works |
| /proc | incomplete (stale dead processes) | works |
| disk writes | ~0.85MB/s | normal SSD speed |

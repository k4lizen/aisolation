FROM ubuntu:26.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        7zip \
        automake \
        bc \
        btop \
        build-essential \
        ca-certificates \
        clang \
        cmake \
        curl \
        elfutils \
        fzf \
        gdb \
        gdb-multiarch \
        git \
        git-lfs \
        gnupg \
        gzip \
        jq \
        kitty-terminfo \
        less \
        nano \
        openssh-client \
        patch \
        pipx \
        pkgconf \
        python3 \
        python3-dev \
        python3-pip \
        python3-venv \
        python-is-python3 \
        patchelf \
        bear \
        nix \
        cpio \
        gcc-14 \
        ripgrep \
        rustup \
        software-properties-common \
        sudo \
        unzip \
        vim \
        wget \
        zip \
        qemu-user \
        qemu-user-binfmt \
        qemu-system \
        adb \
        llvm-20 \
        libssl-dev \
        openjdk-17-jdk-headless \
        busybox-static \
        flex \
        bison \
        libelf-dev \
        kmod \
        xxd \
        zig \
# Common kernel exploit deps
        libkeyutils-dev \
        libnl-cli-3-dev \
        libnl-route-3-dev \
        libip4tc-dev

# add extra apt sources
# docker
# https://docs.docker.com/engine/install/ubuntu/
RUN install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc && \
    chmod a+r /etc/apt/keyrings/docker.asc && \
    tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
# yazi
RUN curl -fsSL https://yazi-rs.github.io/builds/yazi-keyring.gpg \
        | sudo tee /usr/share/keyrings/yazi-keyring.gpg >/dev/null && \
    echo 'deb [signed-by=/usr/share/keyrings/yazi-keyring.gpg] https://yazi-rs.github.io/builds/ stable main' \
        | sudo tee /etc/apt/sources.list.d/yazi.list >/dev/null
# latest gcc
RUN add-apt-repository -y ppa:ubuntu-toolchain-r/test

# fetch from the new apt sources
RUN apt-get update

# install the newly available programs 
RUN apt-get install -y --no-install-recommends \
    docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin \
    yazi \
    gcc-15 \
    gcc-16

# helix from github latest
RUN set -eux; \
    helix_deb_url="$(curl -fsSL \
        https://api.github.com/repos/helix-editor/helix/releases/latest \
        | jq -er '[.assets[] | select(.name | endswith("_amd64.deb")) | .browser_download_url] \
        | if length == 1 then .[0] else error("expected exactly one amd64 Debian asset") end')"; \
    curl -fsSL \
        "${helix_deb_url}" \
        -o /tmp/helix.deb && \
    apt-get install -y --no-install-recommends /tmp/helix.deb && \
    rm /tmp/helix.deb

# nodejs for the clankers
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y --no-install-recommends nodejs

# claude code and codex
RUN npm install -g @anthropic-ai/claude-code @openai/codex

# install rust and uv
# with hack around installing system-wide
ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH=/usr/local/cargo/bin:$PATH
RUN mkdir -p "$RUSTUP_HOME" "$CARGO_HOME" && \
    rustup default stable && \
    chmod -R a+w "$RUSTUP_HOME" "$CARGO_HOME" && \
    curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin INSTALLER_NO_MODIFY_PATH=1 sh

# delete ubuntu user, and make new user matching the hosts uid and gid
ARG USERNAME=dev
ARG USER_UID=1000
ARG USER_GID=1000
RUN set -eux; \
    if id ubuntu >/dev/null 2>&1 && [ "$(id -u ubuntu)" = "${USER_UID}" ]; then \
        userdel -r ubuntu 2>/dev/null || userdel ubuntu; \
    fi; \
    if ! getent group "${USER_GID}" >/dev/null; then groupadd -g "${USER_GID}" "${USERNAME}"; fi; \
    useradd -m -u "${USER_UID}" -g "${USER_GID}" -s /bin/bash "${USERNAME}"; \
    echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/"${USERNAME}"; \
    chmod 0440 /etc/sudoers.d/"${USERNAME}";

# make claude bypass perms by default
RUN mv /usr/bin/claude /usr/bin/claude2
# (for some reason it doesn't respect the xhigh in the config file)
RUN printf '#!/usr/bin/env bash\nexec /usr/bin/claude2 --dangerously-skip-permissions --effort xhigh $@' > /usr/bin/claude
RUN chmod 755 /usr/bin/claude
ENV IS_SANDBOX=1

# make codex bypass perms by default
RUN mv /usr/bin/codex /usr/bin/codex2
RUN printf '#!/usr/bin/env bash\nexec /usr/bin/codex2 --dangerously-bypass-approvals-and-sandbox $@' > /usr/bin/codex
RUN chmod 755 /usr/bin/codex

# yazi helper
COPY ./yazi-bash-helper.sh .
RUN cat yazi-bash-helper.sh >> /home/${USERNAME}/.bashrc
RUN rm yazi-bash-helper.sh

USER ${USERNAME}

# make sure the dirs exist for the bind-mount
RUN mkdir -p /home/${USERNAME}/.claude /home/${USERNAME}/.codex
# don't pester on startup
RUN printf '{"hasCompletedOnboarding": true, "projects": {"/workspace": {"hasTrustDialogAccepted": true}}}\n' > /home/${USERNAME}/.claude.json
# don't try to update
ENV DISABLE_AUTOUPDATER=1

# git settings
COPY ./gitconfig /home/${USERNAME}/.gitconfig

# bash prompt pretty
RUN printf 'export PS1="\\[\\e[1;33m\\](solation)\\[\\e[0m\\] \\w \\$ "\n' >> /home/"${USERNAME}"/.bashrc;

# make sure we actually own all the files
# and the /nix folder too
RUN sudo chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/ && \
    sudo chown -R ${USERNAME}:${USERNAME} /nix

# install android toolchain
ENV ANDROID_SDK_ROOT=/opt/android-sdk
ENV ANDROID_HOME=/opt/android-sdk
ENV ANDROID_NDK_HOME=/opt/android-sdk/ndk/27.3.13750724
ENV PATH="${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin:${ANDROID_SDK_ROOT}/platform-tools:${ANDROID_NDK_HOME}:${PATH}"
RUN sudo mkdir -p "${ANDROID_SDK_ROOT}" && \
    sudo chown -R "${USERNAME}:${USERNAME}" "${ANDROID_SDK_ROOT}" && \
    curl -fsSL \
        https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip \
        -o /tmp/cmdline-tools.zip && \
    mkdir -p "${ANDROID_SDK_ROOT}/cmdline-tools" && \
    unzip -q /tmp/cmdline-tools.zip \
        -d "${ANDROID_SDK_ROOT}/cmdline-tools" && \
    mv "${ANDROID_SDK_ROOT}/cmdline-tools/cmdline-tools" \
        "${ANDROID_SDK_ROOT}/cmdline-tools/latest" && \
    rm /tmp/cmdline-tools.zip && \
    yes | sdkmanager --licenses >/dev/null && \
    sdkmanager \
        "platform-tools" \
        "platforms;android-35" \
        "build-tools;35.0.0" \
        "ndk;27.3.13750724"

# install pwndbg
RUN curl --proto '=https' --tlsv1.2 -LsSf 'https://install.pwndbg.re' | sh -s -- -t pwndbg-gdb

# install gef
RUN wget -q https://raw.githubusercontent.com/bata24/gef/dev/install-uv.sh -O- | sudo sh

# python tooling
RUN uv tool install vmlinux-to-elf && uv tool install ruff

# for now we do them here because i cba to wait for the whole dockerfile rebuild
RUN sudo apt-get update && sudo apt-get install -y --no-install-recommends shfmt gh

# will mount host folder here
WORKDIR /workspace

CMD ["bash"]

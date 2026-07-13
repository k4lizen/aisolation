FROM ubuntu:24.04

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
        git \
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
        qemu-system

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
# yazi & zig
RUN curl -sS https://debian.griffo.io/EA0F721D231FDD3A0A17B9AC7808B4DD62C41256.asc | gpg --dearmor --yes -o /etc/apt/trusted.gpg.d/debian.griffo.io.gpg && \
    echo "deb https://debian.griffo.io/apt $(lsb_release -sc 2>/dev/null) main" | sudo tee /etc/apt/sources.list.d/debian.griffo.io.list
# helix
RUN add-apt-repository -y ppa:maveonair/helix-editor
# latest gcc
RUN add-apt-repository -y ppa:ubuntu-toolchain-r/test

# fetch from the new apt sources
RUN apt-get update

# install the newly available programs 
RUN apt-get install -y --no-install-recommends \
    docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin \
    helix \
    yazi \
    zig \
    gcc-15 \
    gcc-16

# nodejs for claude-code
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y --no-install-recommends nodejs

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

# make codex bypass perms by default
RUN mv /usr/bin/codex /usr/bin/codex2
RUN printf '#!/usr/bin/env bash\nexec /usr/bin/codex2 --dangerously-bypass-approvals-and-sandbox $@' > /usr/bin/codex
RUN chmod 755 /usr/bin/codex

# yazi helper
COPY ./yazi-bash-helper.sh .
RUN cat yazi-bash-helper.sh >> /home/${USERNAME}/.bashrc
RUN rm yazi-bash-helper.sh

USER ${USERNAME}

# claude settings
COPY ./claude-settings.json /home/${USERNAME}/.claude/settings.json
# don't pester on startup
RUN printf '{"hasCompletedOnboarding": true, "projects": {"/workspace": {"hasTrustDialogAccepted": true}}}\n' > /home/${USERNAME}/.claude.json
# don't try to update
ENV DISABLE_AUTOUPDATER=1

# codex settings
COPY ./codex-config.toml /home/${USERNAME}/.codex/config.toml

# git settings
COPY ./gitconfig /home/${USERNAME}/.gitconfig

# bash prompt pretty
RUN printf 'export PS1="\\[\\e[1;33m\\](aisolation)\\[\\e[0m\\] \\w \\$ "\n' >> /home/"${USERNAME}"/.bashrc;

# make sure we actually own all the files
# and the /nix folder too
RUN sudo chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/ && \
    sudo chown -R ${USERNAME}:${USERNAME} /nix

# will mount host folder here
WORKDIR /workspace

CMD ["bash"]

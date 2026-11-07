# Build stage
FROM golang:1.27.3-trixie AS builder

WORKDIR /build

COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN go build -trimpath -o claude-tools-mcp ./cmd/claude-tools-mcp

# Runtime stage with comprehensive tooling
FROM debian:trixie-slim

# Install base system packages and compilers.
# hadolint ignore=DL3008
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Base system
    bash \
    dash \
    ca-certificates \
    tzdata \
    openssl \
    sudo \
    # Compilers and build tools
    gcc \
    g++ \
    gfortran \
    clang \
    clang-tools \
    llvm \
    make \
    cmake \
    ninja-build \
    autoconf \
    automake \
    libtool \
    m4 \
    bison \
    flex \
    binutils \
    patchelf \
    # Development libraries
    linux-libc-dev \
    libffi-dev \
    libssl-dev \
    libsqlite3-dev \
    libyaml-dev \
    zlib1g-dev \
    libbz2-dev \
    liblzma-dev \
    libreadline-dev \
    libncurses-dev \
    # VCS
    git \
    git-lfs \
    mercurial \
    # Compression tools
    tar \
    gzip \
    bzip2 \
    xz-utils \
    zip \
    unzip \
    p7zip-full \
    lz4 \
    zstd \
    pigz \
    # Network tools
    curl \
    wget \
    openssh-client \
    rsync \
    netcat-openbsd \
    dnsutils \
    iproute2 \
    iputils-ping \
    # Utilities
    jq \
    tree \
    file \
    findutils \
    coreutils \
    grep \
    ripgrep \
    sed \
    gawk \
    parallel \
    shellcheck \
    # Database clients
    sqlite3 \
    postgresql-client \
    default-mysql-client \
    # Other tools
    vim \
    nano \
    less \
    diffutils \
    patch \
    gnupg && \
    rm -rf /var/lib/apt/lists/* /tmp/* /usr/share/man/* /usr/share/doc/*

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Install yq (not in Debian main repos)
RUN ARCH=$(uname -m) && \
    YQ_ARCH=$([ "$ARCH" = "aarch64" ] && echo "arm64" || echo "amd64") && \
    curl -fsSL "https://github.com/mikefarah/yq/releases/download/v4.54.2/yq_linux_${YQ_ARCH}" \
    -o /usr/local/bin/yq && \
    chmod +x /usr/local/bin/yq && \
    rm -rf /tmp/*

# Install Node.js and package managers
ENV NODE_VERSION=26.13.0
RUN ARCH=$(uname -m) && \
    NODE_ARCH=$([ "$ARCH" = "aarch64" ] && echo "arm64" || echo "x64") && \
    curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${NODE_ARCH}.tar.xz" | \
    tar -xJ -C /usr/local --strip-components=1 && \
    npm install -g npm@12.2.2 && \
    npm install -g --allow-scripts=yarn,nx,lmdb,@parcel/watcher,@swc/core,msgpackr-extract \
    yarn@1.22.22 \
    pnpm@12.18.0 \
    newman@6.2.3 \
    lerna@10.1.1 \
    parcel@2.16.4 && \
    npm cache clean --force && \
    rm -rf /tmp/* /root/.npm

# Install Python and tools.
# hadolint ignore=DL3008
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-dev \
    python3-venv && \
    python3 -m venv /opt/python && \
    /opt/python/bin/pip install --no-cache-dir \
    pip==26.3 \
    setuptools==84.2.1 \
    wheel==0.48.0 \
    pipx==1.18.16 \
    ansible==14.6.0 \
    yamllint==1.38.0 \
    sphinx==9.2.0 && \
    rm -rf /var/lib/apt/lists/* /tmp/* /root/.cache
ENV PATH=/opt/python/bin:$PATH

# Install Rust and tools.
ENV RUSTUP_HOME=/usr/local/rustup CARGO_HOME=/usr/local/cargo
ENV PATH=/usr/local/cargo/bin:$PATH
RUN curl -fsSL https://sh.rustup.rs -o /tmp/rustup-init.sh && \
    sh /tmp/rustup-init.sh -y --no-modify-path --profile minimal --default-toolchain 1.99.1 && \
    chmod -R a+w /usr/local/rustup /usr/local/cargo && \
    rm -rf /tmp/*

# Install Go
ENV GO_VERSION=1.27.3
RUN ARCH=$(uname -m) && \
    GO_ARCH=$([ "$ARCH" = "aarch64" ] && echo "arm64" || echo "amd64") && \
    curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${GO_ARCH}.tar.gz" | \
    tar -xz -C /usr/local && \
    mkdir -p /usr/local/go-versions && \
    rm -rf /tmp/*
ENV PATH=/usr/local/go/bin:$PATH

# Install container tools (Docker client, buildx)
ENV DOCKER_VERSION=29.9.3
RUN ARCH=$(uname -m) && \
    if [ "$ARCH" = "aarch64" ]; then ARCH="aarch64"; elif [ "$ARCH" = "x86_64" ]; then ARCH="x86_64"; fi && \
    curl -fsSL "https://download.docker.com/linux/static/stable/${ARCH}/docker-${DOCKER_VERSION}.tgz" | \
    tar xzvf - --strip 1 -C /usr/local/bin docker/docker && \
    mkdir -p /usr/local/lib/docker/cli-plugins && \
    BUILDX_ARCH=$([ "$ARCH" = "aarch64" ] && echo "arm64" || echo "amd64") && \
    curl -fsSL "https://github.com/docker/buildx/releases/download/v0.38.2/buildx-v0.38.2.linux-${BUILDX_ARCH}" \
    -o /usr/local/lib/docker/cli-plugins/docker-buildx && \
    chmod +x /usr/local/lib/docker/cli-plugins/docker-buildx && \
    COMPOSE_ARCH=$([ "$ARCH" = "aarch64" ] && echo "aarch64" || echo "x86_64") && \
    curl -fsSL "https://github.com/docker/compose/releases/download/v5.7.0/docker-compose-linux-${COMPOSE_ARCH}" \
    -o /usr/local/lib/docker/cli-plugins/docker-compose && \
    chmod +x /usr/local/lib/docker/cli-plugins/docker-compose && \
    rm -rf /tmp/*

# Install Buildah and Podman.
# hadolint ignore=DL3008
RUN apt-get update && apt-get install -y --no-install-recommends \
    podman \
    buildah \
    skopeo && \
    rm -rf /var/lib/apt/lists/* /tmp/*

# Install Kubernetes tools
RUN ARCH=$(uname -m) && \
    K8S_ARCH=$([ "$ARCH" = "aarch64" ] && echo "arm64" || echo "amd64") && \
    curl -fsSL "https://dl.k8s.io/release/v1.37.2/bin/linux/${K8S_ARCH}/kubectl" \
    -o /usr/local/bin/kubectl && \
    chmod +x /usr/local/bin/kubectl && \
    # Helm
    curl -fsSL "https://get.helm.sh/helm-v4.3.1-linux-${K8S_ARCH}.tar.gz" | \
    tar xzvf - --strip 1 -C /usr/local/bin "linux-${K8S_ARCH}/helm" && \
    # Kustomize
    curl -fsSL "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv5.8.3/kustomize_v5.8.3_linux_${K8S_ARCH}.tar.gz" | \
    tar xzvf - -C /usr/local/bin && \
    # Kind
    curl -fsSL "https://kind.sigs.k8s.io/dl/v0.33.0/kind-linux-${K8S_ARCH}" -o /usr/local/bin/kind && \
    chmod +x /usr/local/bin/kind && \
    # Minikube
    curl -fsSL "https://storage.googleapis.com/minikube/releases/v1.39.0/minikube-linux-${K8S_ARCH}" \
    -o /usr/local/bin/minikube && \
    chmod +x /usr/local/bin/minikube && \
    rm -rf /tmp/*

# Install AWS CLI.
# hadolint ignore=DL3008
RUN apt-get update && apt-get install -y --no-install-recommends awscli && \
    # Install AWS SAM CLI
    pip3 install --no-cache-dir aws-sam-cli==1.171.0 && \
    rm -rf /var/lib/apt/lists/* /tmp/* /root/.cache

# Install Azure CLI
RUN pip3 install --no-cache-dir azure-cli==2.92.0 && \
    rm -rf /tmp/* /root/.cache /root/.azure

# Install Google Cloud CLI and gcsfuse
RUN ARCH=$(uname -m) && \
    GCLOUD_ARCH=$([ "$ARCH" = "aarch64" ] && echo "arm" || echo "x86_64") && \
    curl -fsSL "https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-592.0.0-linux-${GCLOUD_ARCH}.tar.gz" | \
    tar -xz -C /usr/local && \
    /usr/local/google-cloud-sdk/install.sh --quiet --path-update=false --command-completion=false --usage-reporting=false && \
    ln -s /usr/local/google-cloud-sdk/bin/gcloud /usr/local/bin/gcloud && \
    ln -s /usr/local/google-cloud-sdk/bin/gsutil /usr/local/bin/gsutil && \
    ln -s /usr/local/google-cloud-sdk/bin/bq /usr/local/bin/bq && \
    rm -rf /tmp/* /root/.cache

# Install gcsfuse for GCS FUSE mounting and s3fs for S3 FUSE mounting (works with Kata Containers VM isolation).
# hadolint ignore=DL3008
RUN apt-get update && apt-get install -y --no-install-recommends fuse3 s3fs && \
    go install github.com/googlecloudplatform/gcsfuse/v3@v3.13.0 && \
    mv /root/go/bin/gcsfuse /usr/local/bin/gcsfuse && \
    chmod +x /usr/local/bin/gcsfuse && \
    rm -rf /root/go /tmp/* /var/lib/apt/lists/*

# Install GitHub CLI.
# hadolint ignore=DL3008
RUN apt-get update && apt-get install -y --no-install-recommends gh && \
    rm -rf /var/lib/apt/lists/* /tmp/*

# Install HashiCorp tools
RUN ARCH=$(uname -m) && \
    HC_ARCH=$([ "$ARCH" = "aarch64" ] && echo "arm64" || echo "amd64") && \
    curl -fsSL "https://releases.hashicorp.com/terraform/1.17.1/terraform_1.17.1_linux_${HC_ARCH}.zip" -o /tmp/terraform.zip && \
    unzip -oq /tmp/terraform.zip terraform -d /usr/local/bin && \
    rm /tmp/terraform.zip && \
    curl -fsSL "https://releases.hashicorp.com/packer/1.16.2/packer_1.16.2_linux_${HC_ARCH}.zip" -o /tmp/packer.zip && \
    unzip -oq /tmp/packer.zip packer -d /usr/local/bin && \
    rm /tmp/packer.zip && \
    curl -fsSL "https://releases.hashicorp.com/vault/2.2.1/vault_2.2.1_linux_${HC_ARCH}.zip" -o /tmp/vault.zip && \
    unzip -oq /tmp/vault.zip vault -d /usr/local/bin && \
    rm /tmp/vault.zip && \
    rm -rf /tmp/*

# Install Pulumi
RUN curl -fsSL https://get.pulumi.com | sh -s -- --version 3.274.1 && \
    mv ~/.pulumi/bin/pulumi /usr/local/bin/ && \
    rm -rf ~/.pulumi /tmp/*

# Install Bazel and Bazelisk
RUN ARCH=$(uname -m) && \
    BZL_ARCH=$([ "$ARCH" = "aarch64" ] && echo "arm64" || echo "amd64") && \
    curl -fsSL "https://github.com/bazelbuild/bazelisk/releases/download/v1.30.0/bazelisk-linux-${BZL_ARCH}" \
    -o /usr/local/bin/bazelisk && \
    chmod +x /usr/local/bin/bazelisk && \
    ln -s /usr/local/bin/bazelisk /usr/local/bin/bazel && \
    rm -rf /tmp/*

# Install Bicep
RUN ARCH=$(uname -m) && \
    BCP_ARCH=$([ "$ARCH" = "aarch64" ] && echo "arm64" || echo "x64") && \
    curl -fsSL "https://github.com/Azure/bicep/releases/download/v0.49.2/bicep-linux-${BCP_ARCH}" \
    -o /usr/local/bin/bicep && \
    chmod +x /usr/local/bin/bicep && \
    rm -rf /tmp/*

# Install AzCopy
RUN ARCH=$(uname -m) && \
    AZCOPY_ARCH=$([ "$ARCH" = "aarch64" ] && echo "arm64" || echo "amd64") && \
    curl -fsSL "https://github.com/Azure/azure-storage-azcopy/releases/download/v10.34.1/azcopy_linux_${AZCOPY_ARCH}_10.34.1.tar.gz" | \
    tar xzvf - --strip 1 -C /usr/local/bin --wildcards '*/azcopy' && \
    ln -s /usr/local/bin/azcopy /usr/local/bin/azcopy10 && \
    rm -rf /tmp/*

# Install additional tools.
# hadolint ignore=DL3008
RUN apt-get update && apt-get install -y --no-install-recommends \
    mediainfo \
    aria2 \
    libicu76 \
    sshpass \
    lftp && \
    rm -rf /var/lib/apt/lists/* /tmp/*

# Set up environment variables
ENV PATH=/usr/local/bin:/usr/local/google-cloud-sdk/bin:$PATH

# Set up non-root user
RUN useradd -m -u 1000 claude && \
    # Add claude user to sudoers
    echo "claude ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/claude && \
    chmod 0440 /etc/sudoers.d/claude && \
    # Create workspace
    mkdir -p /workspace && \
    chown -R claude:claude /workspace

WORKDIR /workspace

USER 0
COPY --from=builder /build/claude-tools-mcp /usr/local/bin/claude-tools-mcp

EXPOSE 8080

USER 1000
CMD ["/bin/sh", "-c", "/usr/local/bin/claude-tools-mcp --addr 0.0.0.0:${PORT:-8080}"]

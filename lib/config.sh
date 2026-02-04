#!/usr/bin/env bash
# Configuration management including INI files and profile definitions.

# -------- INI file helpers ----------------------------------------------------
_read_ini() {               # $1=file $2=section $3=key
  awk -F' *= *' -v s="[$2]" -v k="$3" '
    $0==s {in=1; next}
    /^\[/ {in=0}
    in && $1==k {print $2; exit}
  ' "$1" 2>/dev/null
}


# -------- Profile functions (Bash 3.2 compatible) -----------------------------
get_profile_packages() {
    case "$1" in
        core) echo "gcc g++ make git pkg-config libssl-dev libffi-dev zlib1g-dev tmux" ;;
        build-tools) echo "cmake ninja-build autoconf automake libtool" ;;
        shell) echo "rsync openssh-client man-db gnupg2 aggregate file" ;;
        networking) echo "iptables ipset iproute2 dnsutils" ;;
        c) echo "gdb valgrind clang clangd clang-format clang-tidy cppcheck doxygen libboost-all-dev libcmocka-dev libcmocka0 lcov libncurses5-dev libncursesw5-dev" ;;
        openwrt) echo "rsync libncurses5-dev zlib1g-dev gawk gettext xsltproc libelf-dev ccache subversion swig time qemu-system-arm qemu-system-aarch64 qemu-system-mips qemu-system-x86 qemu-utils" ;;
        rust) echo "" ;;  # Rust installed via rustup
        python) echo "" ;;  # Managed via uv
        go) echo "" ;;  # Installed from tarball
        flutter) echo "" ;;  # Installed from source
        javascript) echo "" ;;  # Installed via nvm
        java) echo "" ;;  # Java installed via SDKMan, build tools in profile function
        ruby) echo "ruby-full ruby-dev libreadline-dev libyaml-dev libsqlite3-dev sqlite3 libxml2-dev libxslt1-dev libcurl4-openssl-dev software-properties-common" ;;
        php) echo "php php-cli php-fpm php-mysql php-pgsql php-sqlite3 php-curl php-gd php-mbstring php-xml php-zip composer" ;;
        database) echo "postgresql-client mysql-client sqlite3 redis-tools mongodb-clients" ;;
        devops) echo "docker.io docker-compose kubectl helm terraform ansible awscli" ;;
        web) echo "nginx apache2-utils httpie" ;;
        embedded) echo "gcc-arm-none-eabi gdb-multiarch openocd picocom minicom screen" ;;
        datascience) echo "r-base" ;;
        security) echo "nmap tcpdump wireshark-common netcat-openbsd john hashcat hydra" ;;
        ml) echo "" ;;  # Just cmake needed, comes from build-tools now
        bash) echo "shellcheck shfmt bats" ;;  # Bash dev tools, LSP via bun
        *) echo "" ;;
    esac
}

get_profile_description() {
    case "$1" in
        core) echo "Core Development Utilities (compilers, VCS, shell tools)" ;;
        build-tools) echo "Build Tools (CMake, autotools, Ninja)" ;;
        shell) echo "Optional Shell Tools (fzf, SSH, man, rsync, file)" ;;
        networking) echo "Network Tools (IP stack, DNS, route tools)" ;;
        c) echo "C/C++ Development (debuggers, analyzers, Boost, ncurses, cmocka)" ;;
        openwrt) echo "OpenWRT Development (cross toolchain, QEMU, distro tools)" ;;
        rust) echo "Rust Development (installed via rustup)" ;;
        python) echo "Python Development (managed via uv)" ;;
        go) echo "Go Development (installed from upstream archive)" ;;
        flutter) echo "Flutter Development (installed from fvm)" ;;
        javascript) echo "JavaScript/TypeScript (Node installed via nvm)" ;;
        java) echo "Java Development (latest LTS, Maven, Gradle, Ant via SDKMan)" ;;
        ruby) echo "Ruby Development (gems, native deps, XML/YAML)" ;;
        php) echo "PHP Development (PHP + extensions + Composer)" ;;
        database) echo "Database Tools (clients for major databases)" ;;
        devops) echo "DevOps Tools (Docker, Kubernetes, Terraform, etc.)" ;;
        web) echo "Web Dev Tools (nginx, HTTP test clients)" ;;
        embedded) echo "Embedded Dev (ARM toolchain, serial debuggers)" ;;
        datascience) echo "Data Science (Python, Jupyter, R)" ;;
        security) echo "Security Tools (scanners, crackers, packet tools)" ;;
        ml) echo "Machine Learning (build layer only; Python via uv)" ;;
        bash) echo "Bash/Shell Development (shellcheck, shfmt, bats, LSP via bun)" ;;
        *) echo "" ;;
    esac
}

get_all_profile_names() {
    echo "core build-tools shell networking bash c openwrt rust python go flutter javascript java ruby php database devops web embedded datascience security ml"
}

profile_exists() {
    local profile="$1"
    for p in $(get_all_profile_names); do
        [[ "$p" == "$profile" ]] && return 0
    done
    return 1
}

expand_profile() {
    case "$1" in
        c) echo "core build-tools c" ;;
        openwrt) echo "core build-tools openwrt" ;;
        ml) echo "core build-tools ml" ;;
        rust|go|flutter|python|php|ruby|java|database|devops|web|embedded|datascience|security|javascript|bash)
            echo "core $1"
            ;;
        shell|networking|build-tools|core)
            echo "$1"
            ;;
        *)
            echo "$1"
            ;;
    esac
}

# -------- Profile file management ---------------------------------------------
get_profile_file_path() {
    # Use the parent directory name, not the slot name
    local parent_name=$(generate_parent_folder_name "$PROJECT_DIR")
    local parent_dir="$HOME/.claudebox/projects/$parent_name"
    mkdir -p "$parent_dir"
    echo "$parent_dir/profiles.ini"
}

read_config_value() {
    local config_file="$1"
    local section="$2"
    local key="$3"

    [[ -f "$config_file" ]] || return 1

    awk -F ' *= *' -v section="[$section]" -v key="$key" '
        $0 == section { in_section=1; next }
        /^\[/ { in_section=0 }
        in_section && $1 == key { print $2; exit }
    ' "$config_file"
}

read_profile_section() {
    local profile_file="$1"
    local section="$2"
    local result=()

    if [[ -f "$profile_file" ]] && grep -q "^\[$section\]" "$profile_file"; then
        while IFS= read -r line; do
            [[ -z "$line" || "$line" =~ ^\[.*\]$ ]] && break
            result+=("$line")
        done < <(sed -n "/^\[$section\]/,/^\[/p" "$profile_file" | tail -n +2 | grep -v '^\[')
    fi

    # Bash 3.2 safe array expansion
    if [[ ${#result[@]} -gt 0 ]]; then
        printf '%s\n' "${result[@]}"
    fi
}

update_profile_section() {
    local profile_file="$1"
    local section="$2"
    shift 2
    local new_items=("$@")

    # Bash 3.2 compatible: use while loop instead of readarray
    local existing_items=()
    local line
    while IFS= read -r line; do
        existing_items+=("$line")
    done < <(read_profile_section "$profile_file" "$section")

    local all_items=()
    # Bash 3.2 safe array expansion
    if [[ ${#existing_items[@]} -gt 0 ]]; then
        for item in "${existing_items[@]}"; do
            [[ -n "$item" ]] && all_items+=("$item")
        done
    fi

    # Bash 3.2 safe array expansion
    if [[ ${#new_items[@]} -gt 0 ]]; then
        for item in "${new_items[@]}"; do
            local found=false
            if [[ ${#all_items[@]} -gt 0 ]]; then
                for existing in "${all_items[@]}"; do
                    [[ "$existing" == "$item" ]] && found=true && break
                done
            fi
            [[ "$found" == "false" ]] && all_items+=("$item")
        done
    fi

    {
        if [[ -f "$profile_file" ]]; then
            awk -v sect="$section" '
                BEGIN { in_section=0; skip_section=0 }
                /^\[/ {
                    if ($0 == "[" sect "]") { skip_section=1; in_section=1 }
                    else { skip_section=0; in_section=0 }
                }
                !skip_section { print }
                /^\[/ && !skip_section && in_section { in_section=0 }
            ' "$profile_file"
        fi

        echo "[$section]"
        # Bash 3.2 safe array expansion
        if [[ ${#all_items[@]} -gt 0 ]]; then
            for item in "${all_items[@]}"; do
                echo "$item"
            done
        fi
        echo ""
    } > "${profile_file}.tmp" && mv "${profile_file}.tmp" "$profile_file"
}

get_current_profiles() {
    local profiles_file="${PROJECT_PARENT_DIR:-$HOME/.claudebox/projects/$(generate_parent_folder_name "$PWD")}/profiles.ini"
    local current_profiles=()

    if [[ -f "$profiles_file" ]]; then
        while IFS= read -r line; do
            [[ -n "$line" ]] && current_profiles+=("$line")
        done < <(read_profile_section "$profiles_file" "profiles")
    fi

    # Bash 3.2 safe array expansion
    if [[ ${#current_profiles[@]} -gt 0 ]]; then
        printf '%s\n' "${current_profiles[@]}"
    fi
}

# -------- Profile installation functions for Docker builds -------------------
get_profile_core() {
    local packages=$(get_profile_packages "core")
    if [[ -n "$packages" ]]; then
        echo "RUN apt-get update && apt-get install -y $packages && apt-get clean"
    fi
}

get_profile_build_tools() {
    local packages=$(get_profile_packages "build-tools")
    if [[ -n "$packages" ]]; then
        echo "RUN apt-get update && apt-get install -y $packages && apt-get clean"
    fi
}

get_profile_shell() {
    local packages=$(get_profile_packages "shell")
    if [[ -n "$packages" ]]; then
        echo "RUN apt-get update && apt-get install -y $packages && apt-get clean"
    fi
}

get_profile_networking() {
    local packages=$(get_profile_packages "networking")
    if [[ -n "$packages" ]]; then
        echo "RUN apt-get update && apt-get install -y $packages && apt-get clean"
    fi
}

get_profile_c() {
    local packages=$(get_profile_packages "c")
    if [[ -n "$packages" ]]; then
        echo "RUN apt-get update && apt-get install -y $packages && apt-get clean"
    fi
}

get_profile_openwrt() {
    local packages=$(get_profile_packages "openwrt")
    if [[ -n "$packages" ]]; then
        echo "RUN apt-get update && apt-get install -y $packages && apt-get clean"
    fi
}

get_profile_rust() {
    cat << 'EOF'
# Supply chain security: Use vendored rustup script with checksum verification
COPY --chown=claude vendor/scripts/profiles/rustup.sh /tmp/rustup.sh
COPY --chown=claude vendor/scripts/checksums-profiles.sha256 /tmp/checksums-profiles.sha256
RUN cd /tmp && sha256sum -c checksums-profiles.sha256 --ignore-missing 2>/dev/null | grep -q "rustup.sh: OK" || (echo "Checksum verification failed for rustup.sh" && exit 1)
RUN sh /tmp/rustup.sh -y
ENV PATH="/home/claude/.cargo/bin:$PATH"
# Install rust-analyzer LSP server
RUN rustup component add rust-analyzer
RUN rm -f /tmp/rustup.sh /tmp/checksums-profiles.sha256
EOF
}

get_profile_python() {
    cat << 'EOF'
# Python profile - uv already installed in base image
# Python venv and dev tools are managed via entrypoint flag system
# Install ty LSP server for code intelligence (from Astral, same team as uv/ruff)
USER claude
RUN uv tool install ty
USER root
EOF
}

get_profile_go() {
    # NOTE: Go profile downloads Go SDK from golang.org (official source)
    # Network access required. Go binaries are too large (~100MB) to vendor.
    # Security fix: Added SHA256 checksum verification for both architectures
    cat << 'EOF'
# Go SDK installation (requires network access to golang.org)
# Security: Verifies SHA256 checksum before extraction
RUN ARCH=$(dpkg --print-architecture) && \
    GO_VERSION="1.21.0" && \
    GO_SHA256_AMD64="d0398903a16ba2232b389fb31032ddf57cac34efda306a0eebac34f0965a0742" && \
    GO_SHA256_ARM64="f3d4548edf9b22f26bbd49720350bbfe59d75b7090a1a2bff1afad8214febaf3" && \
    if [ "$ARCH" = "arm64" ]; then \
        GO_ARCH="arm64"; \
        GO_SHA256="$GO_SHA256_ARM64"; \
    else \
        GO_ARCH="amd64"; \
        GO_SHA256="$GO_SHA256_AMD64"; \
    fi && \
    wget -O go.tar.gz "https://golang.org/dl/go${GO_VERSION}.linux-${GO_ARCH}.tar.gz" && \
    echo "${GO_SHA256}  go.tar.gz" | sha256sum -c - && \
    tar -C /usr/local -xzf go.tar.gz && \
    rm go.tar.gz
ENV PATH="/usr/local/go/bin:$PATH"
# Install gopls LSP server for code intelligence
ENV GOPATH="/home/claude/go"
ENV PATH="/home/claude/go/bin:$PATH"
USER claude
RUN go install golang.org/x/tools/gopls@latest
USER root
EOF
}

get_profile_flutter() {
    local flutter_version="${FLUTTER_SDK_VERSION:-stable}"
    cat << EOF
USER claude
# Supply chain security: Use vendored fvm script with checksum verification
COPY --chown=claude vendor/scripts/profiles/fvm-install.sh /tmp/fvm-install.sh
COPY --chown=claude vendor/scripts/checksums-profiles.sha256 /tmp/checksums-profiles.sha256
RUN cd /tmp && sha256sum -c checksums-profiles.sha256 --ignore-missing 2>/dev/null | grep -q "fvm-install.sh: OK" || (echo "Checksum verification failed for fvm-install.sh" && exit 1)
RUN bash /tmp/fvm-install.sh
RUN rm -f /tmp/fvm-install.sh /tmp/checksums-profiles.sha256
ENV PATH="/usr/local/bin:\$PATH"
RUN fvm install $flutter_version
RUN fvm global $flutter_version
ENV PATH="/home/claude/fvm/default/bin:\$PATH"
RUN flutter doctor
USER root
EOF
}

get_profile_javascript() {
    cat << 'EOF'
USER claude
# Supply chain security: Use vendored nvm script with checksum verification
COPY --chown=claude vendor/scripts/profiles/nvm-install.sh /tmp/nvm-install.sh
COPY --chown=claude vendor/scripts/checksums-profiles.sha256 /tmp/checksums-profiles.sha256
RUN cd /tmp && sha256sum -c checksums-profiles.sha256 --ignore-missing 2>/dev/null | grep -q "nvm-install.sh: OK" || (echo "Checksum verification failed for nvm-install.sh" && exit 1)
ENV NVM_DIR="/home/claude/.nvm"
RUN bash /tmp/nvm-install.sh
RUN rm -f /tmp/nvm-install.sh /tmp/checksums-profiles.sha256
RUN . $NVM_DIR/nvm.sh && nvm install --lts
# Install typescript-language-server LSP for code intelligence
RUN bash -c "source $NVM_DIR/nvm.sh && npm install -g typescript eslint prettier yarn pnpm typescript-language-server"
USER root
# Create symlinks for LSP binaries in /usr/local/bin so they're in PATH
RUN bash -c "source $NVM_DIR/nvm.sh && \
    ln -sf \$(which node) /usr/local/bin/node && \
    ln -sf \$(which npm) /usr/local/bin/npm && \
    ln -sf \$(which npx) /usr/local/bin/npx && \
    ln -sf \$(which typescript-language-server) /usr/local/bin/typescript-language-server && \
    ln -sf \$(which tsserver) /usr/local/bin/tsserver || true"
EOF
}

get_profile_java() {
    cat << 'EOF'
USER claude
# Supply chain security: Use vendored sdkman script with checksum verification
COPY --chown=claude vendor/scripts/profiles/sdkman-install.sh /tmp/sdkman-install.sh
COPY --chown=claude vendor/scripts/checksums-profiles.sha256 /tmp/checksums-profiles.sha256
RUN cd /tmp && sha256sum -c checksums-profiles.sha256 --ignore-missing 2>/dev/null | grep -q "sdkman-install.sh: OK" || (echo "Checksum verification failed for sdkman-install.sh" && exit 1)
RUN bash /tmp/sdkman-install.sh
RUN rm -f /tmp/sdkman-install.sh /tmp/checksums-profiles.sha256
RUN bash -c "source $HOME/.sdkman/bin/sdkman-init.sh && sdk install java && sdk install maven && sdk install gradle && sdk install ant"
USER root
# Create symlinks for all Java tools in system PATH
RUN for tool in java javac jar jshell; do \
        ln -sf /home/claude/.sdkman/candidates/java/current/bin/$tool /usr/local/bin/$tool; \
    done && \
    ln -sf /home/claude/.sdkman/candidates/maven/current/bin/mvn /usr/local/bin/mvn && \
    ln -sf /home/claude/.sdkman/candidates/gradle/current/bin/gradle /usr/local/bin/gradle && \
    ln -sf /home/claude/.sdkman/candidates/ant/current/bin/ant /usr/local/bin/ant
# Set JAVA_HOME environment variable
ENV JAVA_HOME="/home/claude/.sdkman/candidates/java/current"
ENV PATH="/home/claude/.sdkman/candidates/java/current/bin:$PATH"
EOF
}

get_profile_ruby() {
    local packages=$(get_profile_packages "ruby")
    if [[ -n "$packages" ]]; then
        echo "RUN apt-get update && apt-get install -y $packages && apt-get clean"
    fi
}

get_profile_php() {
    local packages=$(get_profile_packages "php")
    if [[ -n "$packages" ]]; then
        echo "RUN apt-get update && apt-get install -y $packages && apt-get clean"
    fi
}

get_profile_database() {
    local packages=$(get_profile_packages "database")
    if [[ -n "$packages" ]]; then
        echo "RUN apt-get update && apt-get install -y $packages && apt-get clean"
    fi
}

get_profile_devops() {
    local packages=$(get_profile_packages "devops")
    if [[ -n "$packages" ]]; then
        echo "RUN apt-get update && apt-get install -y $packages && apt-get clean"
    fi
}

get_profile_web() {
    local packages=$(get_profile_packages "web")
    if [[ -n "$packages" ]]; then
        echo "RUN apt-get update && apt-get install -y $packages && apt-get clean"
    fi
}

get_profile_embedded() {
    local packages=$(get_profile_packages "embedded")
    if [[ -n "$packages" ]]; then
        cat << 'EOF'
RUN apt-get update && apt-get install -y gcc-arm-none-eabi gdb-multiarch openocd picocom minicom screen && apt-get clean
USER claude
RUN ~/.local/bin/uv tool install platformio
USER root
EOF
    fi
}

get_profile_datascience() {
    local packages=$(get_profile_packages "datascience")
    if [[ -n "$packages" ]]; then
        echo "RUN apt-get update && apt-get install -y $packages && apt-get clean"
    fi
}

get_profile_security() {
    local packages=$(get_profile_packages "security")
    if [[ -n "$packages" ]]; then
        echo "RUN apt-get update && apt-get install -y $packages && apt-get clean"
    fi
}

get_profile_ml() {
    # ML profile just needs build tools which are dependencies
    echo "# ML profile uses build-tools for compilation"
}

get_profile_bash() {
    cat << 'EOF'
# Bash/Shell development profile
RUN apt-get update && apt-get install -y shellcheck shfmt bats && apt-get clean
# Install bun for better performance (used to run bash-language-server)
USER claude
# Supply chain security: Use vendored bun install script with checksum verification
COPY --chown=claude vendor/scripts/profiles/bun-install.sh /tmp/bun-install.sh
COPY --chown=claude vendor/scripts/checksums-profiles.sha256 /tmp/checksums-profiles.sha256
RUN cd /tmp && sha256sum -c checksums-profiles.sha256 --ignore-missing 2>/dev/null | grep -q "bun-install.sh: OK" || (echo "Checksum verification failed for bun-install.sh" && exit 1)
RUN bash /tmp/bun-install.sh
RUN rm -f /tmp/bun-install.sh /tmp/checksums-profiles.sha256
ENV BUN_INSTALL="/home/claude/.bun"
ENV PATH="/home/claude/.bun/bin:$PATH"
# Install bash-language-server via bun
RUN bun install -g bash-language-server
USER root
# Create symlink for bash-language-server in /usr/local/bin so it's in PATH
RUN ln -sf /home/claude/.bun/bin/bash-language-server /usr/local/bin/bash-language-server
EOF
}

export -f _read_ini get_profile_packages get_profile_description get_all_profile_names profile_exists expand_profile
export -f get_profile_file_path read_config_value read_profile_section update_profile_section get_current_profiles
export -f get_profile_core get_profile_build_tools get_profile_shell get_profile_networking get_profile_c get_profile_openwrt
export -f get_profile_rust get_profile_python get_profile_go get_profile_flutter get_profile_javascript get_profile_java get_profile_ruby
export -f get_profile_php get_profile_database get_profile_devops get_profile_web get_profile_embedded get_profile_datascience
export -f get_profile_security get_profile_ml get_profile_bash
prefix := '/usr/local'

deb:
    #!/usr/bin/env bash
    export VERSION="$(cat VERSION)"
    nfpm pkg --packager deb

install: deb
    #!/usr/bin/env bash
    VERSION="$(cat VERSION)"
    package="obsidian-shell-lib_${VERSION}_amd64.deb"
    # Exit if the package is not found
    if [ ! -f "$package" ]; then
        echo "Package not found: $package"
        exit 1
    fi
    sudo apt -y install --allow-downgrades "./$package"

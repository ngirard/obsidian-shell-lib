prefix := '/usr/local'

deb:
    nfpm pkg --packager deb

install: deb
    #!/usr/bin/env bash
    version="$(grep --only-matching --perl-regexp 'version: \K.*' nfpm.yaml)"
    package="obsidian-shell-lib_${version}_amd64.deb"
    # Exit if the package is not found
    if [ ! -f "$package" ]; then
        echo "Package not found: $package"
        exit 1
    fi
    sudo apt install "./$package"

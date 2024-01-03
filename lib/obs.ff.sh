#!/bin/bash

# POSIX-compliant shell function to manipulate "folder-files" (a folder with a file of the same name inside it).

# Prevent from being sourced more than once
[ -n "${_OBS_FF_SH:-}" ] && return || _OBS_FF_SH=1

if [ -z "${_osl_dir}" ]; then
    # Define the library directory if not defined
    _osl_dir="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
fi

# Dependencies
# None for now

# Make a folder-file in the given parent (default: current directory) with the given name.
ff.mk(){
    name="$1"
    parent="${2:-.}"
    d="$parent/$name"
    # d should not exist yet
    if [ -e "$d" ]; then
        printf 'Error: %s already exists\n' "$d"
        exit 1
    fi
    mkdir -p "$d" || exit 1
    f="$d/$name.md"
    touch "$f"
}

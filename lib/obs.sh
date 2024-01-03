#!/bin/bash
# FIXME: Transition to POSIX

# Entry point for the "obs" library

# Define the library directory
lib_dir="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

# Source the library
. "$lib_dir/obs.core.sh"
. "$lib_dir/obs.ff.sh"
. "$lib_dir/obs.vaults.sh"
. "$lib_dir/obs.ws.sh"
. "$lib_dir/obs.ws.fix-paths.sh"
. "$lib_dir/obs.workspace-ff.sh"
. "$lib_dir/obs.tabs-file.sh"

# Unset the variables used by this library
_OBS_unset_vars(){ unset _OBS_CORE_SH _OBS_FF_SH _OBS_TABS_FILE_SH _OBS_VAULTS_SH _OBS_WORKSPACE_FF_SH _OBS_WS_SH _OBS_WS_FIX_PATHS_SH; }


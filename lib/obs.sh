#!/bin/bash
# FIXME: Transition to POSIX

# Entry point for the "obs" library

if [ -z "${_osl_dir}" ]; then
    # Define the library directory if not defined
    _osl_dir="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
fi

# Source the library
. "$_osl_dir/obs.core.sh"
. "$_osl_dir/obs.ff.sh"
. "$_osl_dir/obs.vaults.sh"
. "$_osl_dir/obs.ws.sh"
. "$_osl_dir/obs.ws.fix-paths.sh"
. "$_osl_dir/obs.workspace-ff.sh"
. "$_osl_dir/obs.tabs-file.sh"

# Unset the variables used by this library
_OBS_unset_vars(){ unset _OBS_CORE_SH _OBS_FF_SH _OBS_TABS_FILE_SH _OBS_VAULTS_SH _OBS_WORKSPACE_FF_SH _OBS_WS_SH _OBS_WS_FIX_PATHS_SH; }


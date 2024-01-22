#!/bin/bash
# Script used to reset the password of user DR_maint in ASE and SRS
# Version:
# Date:
# Author: Catalin Mihai Popa
# Mail: catalin.popa@sap.com
####################################################
####################################################

DT=$(date "+%d%m%Y")
SID=$(printenv SYBASE | awk -F"/" '{print $3}')
maint_username="${SID}_maint"
log_file="/sybase/${SID}/saparch_1/OutputDR_maintPasswordReset_${DT}.log"

# Function that checks if the script is executed by the user syb<sid>
check_user(){
    desired_user="syb${SID,,}"
    current_user=$(whoami)

    if [ "$current_user" != "$desired_user" ]; then
        echo "--> Error: The script must be executed by the user $desired_user" > "${log_file}"
        exit 1
    fi
    echo "--> The script is being executed by the user $current_user" > "${log_file}"
}

# Function used to obtain different passwords from the script caller
get_password(){
    username=$1
    password=$(systemd-ask-password "Enter the Password for ${username}:")
    echo "$password"
}

# Function that resets the password of maint user in ASE and on the DSI connections in SRS
reset_maint_password(){
    maint_password=$(get_password "${maint_username}")
}

# Main program starts here
check_user
reset_maint_password
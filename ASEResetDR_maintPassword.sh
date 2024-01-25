#!/bin/bash
# Script used to reset the password of user DR_maint in ASE and SRS
# Version:
# Date:
# Author: Catalin Mihai Popa
# Mail: catalin.popa@sap.com
####################################################
####################################################

# Function that checks if the script is executed by the user syb<sid>
check_user(){
desired_user="syb${SID,,}"
current_user=$(whoami)

if [ "$current_user" != "$desired_user" ]; then
    echo "--> Error: The script must be executed by the user $desired_user" > "${log_file}"
    exit 1
fi
echo "--> The script is being executed by the user $current_user" >> "${log_file}"
}

# Function that gets | sets important parameters for the script
set_parameters(){
DT=$(date "+%d%m%Y")
SID=$(printenv SYBASE | awk -F"/" '{print $3}')
maint_username="${SID}_maint"
log_file="/sybase/${SID}/saparch_1/OutputDR_maintPasswordReset_${DT}.log"
repserver_name=$(ps -ef | grep repserver | grep -v grep | awk -F"-S" '{print substr($2, 1, 13)}')
srs_site_name="$(echo "${repserver_name: -5}" | tr '[:upper:]' '[:lower:]')"
maint_password=$(get_password "${maint_username}")
}

# Function that builds the isql connection strings
build_isql_connection_string(){

# sa srs isql connection string
sa_srs_aseuserstorekey="sa_srs_${srs_site_name}"
ase_sa_srs_key_command="aseuserstore list ${sa_srs_aseuserstorekey}"

if eval "${ase_sa_srs_key_command}" > /dev/null 2>&1; then
    isql_sa_srs_sql_connection_test_command="isql -k ${sa_srs_aseuserstorekey} -w20000 -J <<EOF
    CONNECT
    GO
    SELECT dsname FROM rs_databases
    GO
    exit
    EOF
    "
    if eval "${isql_sa_srs_sql_connection_test_command}" > /dev/null 2>&1; then
        echo "Connection with aseuserstore key ${sa_srs_aseuserstorekey} is working"
        sa_srs_isql_case="aseuserstore"
    fi
else
    echo "The aseuserstore key ${sa_srs_aseuserstorekey} is not present. Trying isql connection with user sa directly."
    sa_srs_password=$(get_password "sa")
    isql_sa_srs_sql_connection_test_command="isql -X -Usa -P'${sa_srs_password}' -w20000 -J <<EOF
    CONNECT
    GO
    SELECT dsname FROM rs_databases
    GO
    exit
    EOF
    "
    if eval "${isql_sa_srs_sql_connection_test_command}" > /dev/null 2>&1; then
        echo "isql connection with user sa is working"
        sa_srs_isql_case="isql"
    fi
fi

case $sa_srs_isql_case in
    "aseuserstore" )
        echo "aseuserstore"
        ;;
    "isql" )
        echo "isql"
        ;;
esac
}

# Function used to obtain different passwords from the script caller
get_password(){
username=$1
password=$(systemd-ask-password "Enter the Password for ${username}:")
echo "$password"
}

# Function that test the login of user <SID>_maint
test_maint_login(){
isql -X -S"${SID}" -U"${maint_username}" -J -w20000 <<EOF
${maint_password}
EOF
}

# Function that resets the password of maint user in ASE and on the DSI connections in SRS
reset_maint_password(){
check_user
set_parameters
# First test the login of <SID>_maint user with the standard password
if  ! test_maint_login; then
    # Reset the password of user maint and unlock it
    isql -X -S"${SID}" -U"sapsso" -J -w20000 <<EOF
    ${sapsso_password}
    use master
    go
    print "Resetting the password for maint user"
    go
    exec..sp_password "${sapsso_password}", "${maint_password}" , "${maint_username}"
    go
    declare @cnt int
    select @cnt=count(*) from master..syslogins where name = "${maint_username}" and status  = 2
    if @cnt > 0
    begin
    print "${maint_username} user is locked. Will proceed to unlock the user"
    exec..sp_locklogin "${maint_username}",'unlock'
    end
    go
EOF
fi

# Change the password on the DSI connections in the SRS with the new <SID>_maint password
for dsi in "${dsi_to_alter[@]}"; do
    isql -X -Usa -S"${repserver_name}" -J -w2000 <<EOF
    ${sa_srs_password}
    suspend connection to ${dsi}
    go
    alter user ${maint_username} set password "${maint_password}"
    go
    alter connection to ${dsi} set password ${maint_password}
    go
    resume connection to ${dsi}
    go
EOF
done
}

############ Main program starts here ############
############################################

# Check if at least one parameter is provided to the script
if [ "$#" -lt 1 ]; then
    echo "--> The script must be called with at least 1 argument: $0 param1 [param2 ...]" > "${log_file}"
    exit 1
fi

# Store the command-line arguments in an array
dsi_to_alter=("$@")

reset_maint_password
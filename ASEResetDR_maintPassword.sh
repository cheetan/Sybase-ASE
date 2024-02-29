#!/bin/bash
# Script used to reset the password of user DR_maint in ASE and SRS
# Version:
# Date:
# Author: Catalin Mihai Popa
# Mail: catalin.popa@sap.com
####################################################
####################################################

# Function that defines a custom echo output
custom_echo(){
    echo -e "\n####################################################\n####################################################\n" >> "${log_file}"
    echo -ne "[$(date +'%Y-%m-%d %H:%M:%S')]\t" >> "${log_file}"
}

# Function that checks if the script is executed by the user syb<sid>
check_user(){
current_user=$(whoami)

if [[ "$current_user" != syb* ]]; then
    echo -e "--> Error: The script must be executed by the user syb<SID>\n"
    exit 1
fi
}

# Function used to obtain different passwords from the script caller
get_password(){
username=$1
password=$(systemd-ask-password "Enter the Password for ${username}:")
echo "${password}"
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

# Function that builds the isql connection string to use throughout the script
build_isql_connection_string(){

# build the sa srs isql connection string
sa_srs_aseuserstorekey="sa_srs_${srs_site_name}"
sa_srs_key_list_command="aseuserstore list ${sa_srs_aseuserstorekey}"

if eval "${sa_srs_key_list_command}" > /dev/null 2>&1; then
    custom_echo
    echo -e "Testing the sql connection with aseuserstore key ${sa_srs_aseuserstorekey}" >> "${log_file}"

    aseuserstore_sa_srs_connection_test="isql -X -k${sa_srs_aseuserstorekey} -w20000 -J -b <<EOF
    CONNECT
    GO
    SELECT dsname FROM rs_databases
    GO
    exit
    EOF
    "
    if eval "${aseuserstore_sa_srs_connection_test}" > /dev/null 2>&1; then
        custom_echo
        echo -e "Connection with aseuserstore key ${sa_srs_aseuserstorekey} is working" >> "${log_file}"
        sa_srs_sql_connection_string="isql -X -k${sa_srs_aseuserstorekey} -w20000 -J -b <<-EOF"
    fi
else
    custom_echo
    echo -e "The aseuserstore key ${sa_srs_aseuserstorekey} is not present. Trying isql connection with user sa directly"
    sa_srs_password=$(get_password "sa")
    isql_sa_srs_connection_test="isql -X -Usa -S${repserver_name} -y/sybase/${SID}/DM/ -P${sa_srs_password} -w20000 -J -b <<EOF
    CONNECT
    GO
    SELECT dsname FROM rs_databases
    GO
    exit
    EOF
    "
    if eval "${isql_sa_srs_connection_test}" > /dev/null 2>&1; then
        custom_echo
        echo -e "Direct isql connection with user sa in SRS is working" >> "${log_file}"
        sa_srs_sql_connection_string="isql -X -Usa -S${repserver_name} -y/sybase/${SID}/DM/ -P${sa_srs_password} -w20000 -J -b <<-EOF"
    else
        custom_echo
        echo -e"Direct isql connection with user sa in SRS is not working" >> "${log_file}"
        exit 1
    fi
fi

# build the sapsso ase isql connection string
sapsso_ase_aseuserstorekey="sapsso"
sapsso_ase_key_list_command="aseuserstore list ${sapsso_ase_aseuserstorekey}"

if eval "${sapsso_ase_key_list_command}" > /dev/null 2>&1; then
    custom_echo
    echo -e "Testing the sql connection with aseuserstore key ${sapsso_ase_aseuserstorekey}" >> "${log_file}"

    aseuserstore_sapsso_ase_connection_test="isql -X -k${sapsso_ase_aseuserstorekey} -w20000 -J -b <<EOF
    SELECT host_name()
    GO
    exit
    EOF
    "
    if eval "${aseuserstore_sapsso_ase_connection_test}" > /dev/null 2>&1; then
        custom_echo
        echo -e "Connection with aseuserstore key ${sapsso_ase_aseuserstorekey} is working" >> "${log_file}"
        sapsso_ase_sql_connection_string="isql -X -k${sapsso_ase_aseuserstorekey} -w20000 -J -b <<EOF"
    fi
else
    custom_echo
    echo -e "The aseuserstore key ${sapsso_ase_aseuserstorekey} is not present. Trying isql connection with user sa directly"
    sapsso_password=$(get_password "sapsso")
    isql_sapsso_ase_connection_test="isql -X -Usapsso -S${SID} -P${sapsso_password} -w20000 -J -b  <<EOF
    SELECT host_name()
    GO
    exit
    EOF
    "
    if eval "${isql_sapsso_ase_connection_test}" > /dev/null 2>&1; then
        custom_echo
        echo -e "Direct isql connection with user sapsso in ASE is working" >> "${log_file}"
        sapsso_ase_sql_connection_string="isql -X -Usapsso -S${SID} -P${sapsso_password} -w20000 -J -b <<EOF"
    else
        custom_echo
        echo -e "Direct isql connection with user sapsso in ASE is not working" >> "${log_file}"
        exit 1
    fi
fi
}

# Function that tests the login of user <SID>_maint in ASE and SRS
test_maint_login(){
local server_name="$1"
case $server_name in
    "${SID}" )
        maint_isql_ASE_connection_test="isql -X -S${server_name} -U${maint_username} -P${maint_username} -w20000 -J -b <<EOF
SELECT host_name()
GO
EXIT
EOF
"
        if eval "${maint_isql_ASE_connection_test}" > /dev/null 2>&1; then
            custom_echo
            echo -e "Connection with user ${maint_username} in ASE is working. No need to change it's password in ASE" >> "${log_file}"
            return 0
        else
            custom_echo
            echo -e "Connection with user ${maint_username} in ASE is not working. Will proceed to change it's password and unlock it in ASE" >> "${log_file}"
            return 1
        fi
        ;;
    "${repserver_name}" )
        maint_isql_SRS_connection_test="isql -X -S${server_name} -U${maint_username} -y/sybase/${SID}/DM/ -P${maint_username} -w20000 -J -b <<EOF
CONNECT
GO
SELECT dsname FROM rs_databases
GO
exit
EOF
"
        if eval "${maint_isql_SRS_connection_test}" > /dev/null 2>&1; then
            custom_echo
            echo -e "Connection with user ${maint_username} in SRS is working. No need to change it's password in SRS" >> "${log_file}"
            return 0
        else
            custom_echo
            echo -e "Connection with user ${maint_username} in SRS is not working. Will proceed to change it's password in SRS" >> "${log_file}"
            return 1
        fi
        ;;
esac
}

# Function that resets the password of maint user in ASE and on the DSI connections in SRS
reset_maint_password(){
check_user
set_parameters
build_isql_connection_string

# Test the isql log-in of <SID>_maint user with the standard password and reset it if needed in ASE
isql_PasswordChange_Unlock_UserMaint_ASE="${sapsso_ase_sql_connection_string}
set nocount on
go
use master
go
print 'Resetting the password for user ${maint_username} in ASE'
go
-- exec..sp_password ${sapsso_password}, ${maint_password} , ${maint_username}
-- go
declare @cnt int
select @cnt=count(*) from master..syslogins where name = '${maint_username}' and status  = 2
if @cnt > 0
begin
print '${maint_username} user is locked. Will proceed to unlock the user'
exec..sp_locklogin ${maint_username},'unlock'
end
go
exit
EOF
"
if  ! test_maint_login "${SID}"; then
    # Reset the password of user maint in ASE and unlock the user
    if eval "${isql_PasswordChange_Unlock_UserMaint_ASE}" > /dev/null 2>&1; then
        sql_output=$(eval "$isql_PasswordChange_Unlock_UserMaint_ASE")
        custom_echo
        echo -e "${sql_output}\n" >> "${log_file}"
        echo -e "Successfully changed the password and unlocked the user ${maint_username} in ASE" >> "${log_file}"
    else
        custom_echo
        echo -e "Couldn't change the password nor unlock the user ${maint_username}" >> "${log_file}"
        exit 1
    fi
else
    custom_echo
    echo -e "The isql log-in of user ${maint_username} is working. No need to change it's password in ASE" >> "${log_file}"
fi

# Test the isql log-in of <SID>_maint user with the standard password and reset it if needed in SRS
isql_PasswordChange_UserMaint_SRS="${sa_srs_sql_connection_string}
-- alter user ${maint_username} set password ${maint_password}
-- go
exit
EOF
"
if  ! test_maint_login "${repserver_name}"; then
    # Reset the password of user <SID>_maint in SRS
    if eval "${isql_PasswordChange_UserMaint_SRS}" > /dev/null 2>&1; then
        sql_output=$(eval "$isql_PasswordChange_UserMaint_SRS")
        custom_echo
        echo -e "Resetting the password for user ${maint_username} in SRS ${sql_output}\n" >> "${log_file}"
        echo -e "Successfully changed the password of user ${maint_username} in SRS" >> "${log_file}"
    else
        custom_echo
        echo -e "Couldn't change the password of user ${maint_username} in SRS" >> "${log_file}"
        exit 1
    fi
else
    custom_echo
    echo -e "The isql log-in of user ${maint_username} is working. No need to change it's password in SRS" >> "${log_file}"
fi

# Obtain the DSI names that needs to have their password altered with the new password of <SID>_maint user
isql_AlterDSIPassword_SRS="${sa_srs_sql_connection_string} | awk '{print \$NF}'
admin who_is_down
go | grep -Ev 'EXEC|R2|R1|RSSD'
exit
EOF
"
if eval "$isql_AlterDSIPassword_SRS" > /dev/null 2>&1; then
    dsi_to_alter=("$(eval "$isql_AlterDSIPassword_SRS")")
    custom_echo
    echo -e "The DSIs to be altered are:\n${dsi_to_alter[*]}\n" >> "${log_file}"
else
    custom_echo
    echo -e "Couldn't obtain the names of the DSIs to be altered with the new password of <SID>_maint user"
    exit 1
fi

# Change the password on the DSI connections in the SRS with the new <SID>_maint password
for dsi in "${dsi_to_alter[@]}"; do
    isqlAlterDSIResetPassword="${sa_srs_sql_connection_string}
suspend connection to ${dsi}
go
alter connection to ${dsi} set password ${maint_password}
go
resume connection to ${dsi}
go
EOF"
    if eval "$isqlAlterDSIResetPassword" > /dev/null 2>&1; then
        sql_output=$(eval "$isqlAlterDSIResetPassword")
        custom_echo
        echo -e "${sql_output}\n" >> "${log_file}"
        echo -e "Successfully reset the password for the DSI ${dsi} in SRS" >> "${log_file}"
    else
        custom_echo
        echo -e "Couldn't reset the password for the DSI ${dsi} in SRS" >> "${log_file}"
        exit 1
    fi
done
}

############ Main program starts here ############
############################################

reset_maint_password
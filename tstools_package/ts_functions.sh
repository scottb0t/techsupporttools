#!/bin/bash

#####################################
# Functions common to all libraries #
#####################################

# tolower !
global.tolower(){
echo $1 | tr [:upper:] [:lower:]
}

# return 0 (==true) if fed help
global.check_desc(){
local var=$(global.tolower $1)
if [[ $var == 'help' ]]; then
    return 0
else
    return 1
fi
}

#List functions library contains
global.list_functions(){
for function in $(grep '()' $0| grep -v 'global' | grep -v 'grep'); do
    function_name=$(echo $function | awk -F '(' '{print $1}')
    $function_name help
done
}

# Don't forget to replace template with actual prefix

#Describe what this library does
template.describe(){ 
#description
if global.check_desc $1; then cat <<EOF
$FUNCNAME 
Prints Description of library.
EOF
    return
fi
#function...
cat <<EOF

This file is intended as a bash library. 
Calling it directly merely  prints this description.

EOF
}

#List functions library contains
template.list_functions(){ 
#description
if global.check_desc $1; then cat <<EOF
$FUNCNAME 
Prints list of library specific functions.
EOF
    return
fi
#function...
    global.list_functions
EOF
}

template.example_function(){
#description
if global.check_desc $1; then cat <<EOF
$FUNCNAME 
Insert description here
EOF
    return
fi
#function...
}



#### End of global functions and templates ####

# user functions

test_for_root(){
	if [[ $EUID -ne 0 ]]; then
		return 1
	else
		return 0
	fi
}

check_file_write(){
        local file=$1
	touch $file &>/dev/null
	return $?
}

check_file_read(){
        local file=$1
        if [[ ! -e $file ]]; then
                return 5
        elif [[ ! -r $file ]]; then
                return 4
        else
                return 0
        fi
}


check_dir_read(){
        local dir=$1
        if [[ ! -e $dir ]]; then
                return 5
        elif [[ ! -r $dir ]]; then
                return 4
        elif [[ ! -d $dir ]]; then
		return 6
	else
                return 0
        fi
}


choose_username(){
	local path=$1
	while read line  ; do
		local user=$(echo $line | awk -F : '{print $1}')
		local user_uid=$(id -u $user)
		if [[ $user_uid -gt 999 ]] ; then
                        # unless user is a nobody :)
                        if [[ ! $user == "nobody" ]]; then
        			 user_list="$user_list $user"

			fi
		fi

	done < $path/etc/passwd
	PS3="Select a user "
        select user_name in $user_list; do
                break
        done
echo $user_name
}

test_for_uid(){
	local my_user=$1
	local my_uid=$(id -u $my_user)
	echo $my_uid
}
test_for_user(){
	local path=$2
	if [[ $path ]]; then
        	local chroot_path="chroot $path"
	fi

	$chroot_path id $my_user &>/dev/null
	return $?
}

# password functions
reset_password(){
        local username=$1
        local passhash="$2"
        local path=$3
        if [[ $path ]]; then
                local chroot_path="chroot $path"
        fi
        $chroot_path usermod --password "$passhash" $username
	return $?
}

expire_password(){
	local username=$1
	local path=$2
	if [[ $path ]]; then
        	chroot_path="chroot $path"
	fi
	$chroot_path passwd -e $username
        return $?
}

backup_passwords(){
	local path=$1
	local isotime=$(date +%Y%m%d%H%M)
	for file in passwd group shadow gshadow; do
		if ! cp $path/etc/$file $path/etc/$file.fregeek_ts_backup.$isotime;then
			local failarray=( ${failarray[@]-} $(echo "$file") )
		fi
	done
	# check length of failarray if >0 then something failed
         if [[ ${#fail_array[@]} -ne 0 ]]; then
                echo -n "could not backup"
                for name in ${failarray[@]}; do
                        echo -n "/etc/$name"
                done
                return 3
	else
	echo "password files backed up with extension .freegeek_ts_backup.$isotime"
        exit 0
	fi
}

backup_passwords_for_reset(){
	local path=$1
        for file in passwd group shadow gshadow; do
                if ! cp $path/etc/$file $path/etc/$file.freegeek_ts_bak;then
                        local failarray=( ${failarray[@]-} $(echo "$file") )
                fi
        done
        # check length of failarray if >0 then something failed
         if [[ ${#fail_array[@]} -ne 0 ]]; then
                echo -n "could not backup"
                for name in ${failarray[@]}; do
                        echo -n "/etc/$name"
                done
                return 3
	else
		echo "backed up password files to [file].ts_bak"
		return 0
        fi
}

revert_passwords(){
        local path=$1
	local extension=$2
	if [[ ! $extension ]] ; then
		extension='freegeek_ts_bak'
	fi 
        for file in passwd group shadow gshadow ; do
                if ! cp $path/etc/$file.${extension} $path/etc/$file ;then
                        local failarray=( ${failarray[@]-} $(echo "$file") )
                fi
        done
        # check length of failarray if >0 then something failed
         if [[ ${#fail_array[@]} -ne 0 ]]; then
                echo -n "could not revert"
                for name in ${failarray[@]}; do
                        echo -n "/etc/$name"
                done
                return 3
        else
                echo "Restored original password files"
                return 0
        fi
}


# gconf related
reset_gconf(){
	# checks to see if we are changing our own or somebody elses settings
	# --direct option can only be used if gconfd is not running as that 
	# users session
	local my_user=$1
	local setting=$2
	local path=$3
	if [[ $path ]]; then
        	local chroot_path="chroot $path"
	fi
        local my_uid=$($chroot_path id -u $my_user)
	# test to see if self change and if gconfd-2 is running
	if [[ $my_uid -eq $EUID ]] && [[  $(pidof gconfd-2) ]]; then
        	gconftool-2 --recursive-unset $setting
		returnval=$?
	elif [[ $(ps aux |  grep $(pidof gconfd-2) | awk '{print $1}') = $my_user ]]; then
		echo "WARNING:gconfd-2 is running as $my_user"
		echo "You can not change gconfd settings for that user"
		echo "run ts_reset_panel as that user without the -u option"
		returnval=3
	else
        	$chroot_path gconftool-2 --direct --config-source=xml::/home/$my_user/.gconf --recursive-unset $setting
		returnval=$?
	fi
	return $returnval
}


# write to error log and/or standard out 
write_msg(){
local msg="$@"  
for line in "$msg"; do 
	echo "$line"
	if [[ $logfile ]]; then
		if ! echo "$line" >>$logfile; then 
		# should not hit here as already checked
		echo "Could not write to Log File: $logfile"
                exit 3
		fi
	fi
done
return 0
}


# remove list of files
cleanup(){
	rm -r $@
	return $?
}


# test for valid ticket number
#N.B. actually tests for 5 digits, will stop working at some distant point in the future
check_ticket_number(){
	local ticketnumber=$1
	local regex="^[0-9]{5}$"
	if [[ ! $ticketnumber =~ $regex ]] ; then
                return 1
	else
		return 0
	fi
}

#test for valid backup directory
#N.B. tests for 8 digits a dash then 5 digits, will stop working at some distant point in the future
check_valid_backup_dir(){
	local backupdir=$1
	local regex="^[0-9]{8}-[0-9]{5}$"
        if [[ ! $backupdir =~ $regex ]] ; then
                return 1
        else
                return 0
        fi
}



#checks to see if any characters other than numbers letters and underscores are present
check_valid_chars(){
	local input=$1
	regex="[^A-Za-z0-9_]"
	if [[ ! $input =~ $regex ]]; then
		return 1
	else
		return 0
	fi
}


# sends an email
ts.send_email(){
#description
if global.check_desc $1; then cat <<EOF
$FUNCNAME 

This functions sends an email. It takes the following options. 
SENDER RECIPIENT 'SUBJECT' 'MESSAGE'
All are required. It is prefereable to quote the message but not compulsory.
The subject must be quoted, otherwise it will be truncated at the first word
and the rest prepended to the message body.
EOF
    return
fi
#function...
    # there must be at least 4 arguments supplied
    if (( $# < 4 )); then
        return 4
    fi
    # get parameters
    local from="$1"
    shift
    local recipient="$1"
    shift
    local subject="$1"
    shift
    local message="$@"

    # check for valid email 
    # regex from http://www.regular-expressions.info/email.html
    # NOT WORKING

    if ! [[  $from =~ [A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,4} ]]; then
        echo "doh! $from"
        return 67   # EX_NOUSER       67      /* addressee unknown */
    elif ! [[ $recipient =~ ^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,4}$ ]]; then
         echo "doh!!"
        return 67   # see /usr/include/sysexits.h
    fi
    
    # send mail with mailx and return return value
    mailx -n -r "$from" -s "$subject"  "$recipient" < <(echo "$message")
    return $?
}


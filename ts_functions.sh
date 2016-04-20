#!/bin/bash

# user functions
#set -x #debugging

# use this function to determine if user is root
test_for_root(){
	if [[ $EUID -ne 0 ]]; then
		return 1
	else
		return 0
	fi
}

# determines if a file is writeable
# usage:
# check_file_write <file>
check_file_write(){

    	local file=$1

	# if file is a directory, change value of file to test if we can write
	if [[ -d $file ]]; then
        	file=${file/.write_test}
        	local remove="true"
    	fi

	# attempt to write file, place result in /dev/null
	touch "$file" &>/dev/null
    	local retval=$?

	# remove file since we're done with our test
    	if [[ $remove ]]; then
        	if [[ -e $file ]]; then
            		rm $file
        	fi
    	fi
	
	return $retval
}

# determines if a file is readable
# returns 5 if file does not exist, returns 4 if file is not readable
# returns 0 is file passes these tests
# usage:
# check_file_read <file>
check_file_read(){
        local file=$1

	# check if file exists
        if [[ ! -e $file ]]; then
                return 5
	# check if file is readable
        elif [[ ! -r $file ]]; then
                return 4
	# all checks passed!
        else
                return 0
        fi
}

# determines if a directory is readable
# returns 5 if dir does not exist, returns 4 if dir is not readable, returns 6 if dir is not a directory
# usage:
# check_dir_read <dir>
check_dir_read(){

        local dir=$1
	
	# check if dir exists
        if [[ ! -e $dir ]]; then
                return 5
	# check if dir is readable
        elif [[ ! -r $dir ]]; then
                return 4
	# check if dir is a directory
        elif [[ ! -d $dir ]]; then
		return 6
	# all checks passed!
	else
                return 0
        fi
}

choose_username(){

	local path=$1

	# read /etc/passwd for users
	while read line ; do
		# obtain username
		local user=$(echo $line | awk -F : '{print $1}')
		# obtain uid of username
		local user_uid=$(id -u $user)

		# if UID > 999 then we add the username to user_list
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

# echoes UID of a user
# usage:
# test_for_uid <user>
test_for_uid(){
	local my_user=$1
	local my_uid=$(id -u $my_user)
	echo $my_uid
}

# this function looks incomplete...
test_for_user(){

	local path=$2

	if [[ $path ]]; then
        	local chroot_path="chroot $path"
	fi

	$chroot_path id $my_user &>/dev/null # my_user is undefined
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
		if ! cp $path/etc/$file $path/etc/$file.freegeek_ts_backup.$isotime;then
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

	local error

	for elem in $@; do
		if ! _del $elem; then
            		error+="$elem "
        	fi
    	done

    	if [[ ! -z $error ]]; then
        	echo "could not delete ${error}"
        	return 1
    	else
        	return 0
    	fi
}

_del(){
	rm -r $1
	return $?
}

# test for valid ticket number
#N.B. actually tests for 5 digits, will stop working at some distant point in the future
check_ticket_number(){

	local ticketnumber=$1
	local regex="^[0-9]{5}$"

	if [[ ! $ticketnumber =~ $regex ]]; then
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
    	local regex2="^[0-9]{8}-[0-9]{5}-[A-Za-z0-9_].*$"

        if [[ $backupdir =~ $regex ]]; then
                return 0
        elif [[  $backupdir =~ $regex2 ]]; then
                return 0
        else
                return 1
        fi
}

#checks to see if any characters other than numbers letters and underscores are present
check_valid_chars(){

	local input=$1
    	local regex="[^-_a-zA-Z0-9]"

	if [[ $input =~ $regex ]]; then
		return 1
	else
		return 0
	fi
}


#!/bin/bash

# Script to manage users and groups based on input file using awk for parsing

USER_FILE="$1"
LOG_FILE="/var/log/user_management.log"
PASSWORD_FILE="/var/secure/user_passwords.csv"
ENCRYPTED_PASSWORD_FILE="/var/secure/encrypted_user_passwords.csv"
GROUP_PREFIX="grp_"

# Ensure log file and secure directories/files exist with proper permissions
mkdir -p /var/log
touch "$LOG_FILE"
chmod 600 "$LOG_FILE"

mkdir -p /var/secure
touch "$PASSWORD_FILE" "$ENCRYPTED_PASSWORD_FILE"
chmod 600 "$PASSWORD_FILE" "$ENCRYPTED_PASSWORD_FILE"

# Function to generate random passwords securely
generate_password() {
    openssl rand -base64 12 | tr -dc 'a-zA-Z0-9' | head -c 12
}

# Function to securely log actions
log_action() {
    echo "$(date) - $1" >> "$LOG_FILE"
}

# Function to create a group if it doesn't exist
create_group() {
    local group="$1"
    if ! getent group "$group" >/dev/null; then
        groupadd "$group"
        if [ $? -eq 0 ]; then
            log_action "Group $group created."
        else
            log_action "Failed to create group $group."
            return 1
        fi
    else
        log_action "Group $group already exists."
    fi
}

# Function to create a user if it doesn't exist
create_user() {
    local username="$1"
    if id "$username" &>/dev/null; then
        log_action "User $username already exists."
    else
        useradd -m -s /bin/bash "$username"
        if [ $? -eq 0 ]; then
            log_action "User $username created with home directory."
        else
            log_action "Failed to create user $username."
            return 1
        fi
    fi
}

# Function to add user to groups
add_user_to_groups() {
    local username="$1"
    local groups="$2"
    local success=1

    # Add user to personal group
    local personal_group="${GROUP_PREFIX}${username}"
    create_group "$personal_group"
    usermod -aG "$personal_group" "$username"
    if ! id -nG "$username" | grep -qw "$personal_group"; then
        log_action "Failed to add user $username to personal group $personal_group."
        success=0
    else
        log_action "User $username added to personal group $personal_group."
    fi

    # Add user to specified groups
    awk -v user="$username" -v group_prefix="$GROUP_PREFIX" -v log_file="$LOG_FILE" '
    BEGIN {
        FS=";"
        success=1
    }
    {
        gsub(/[[:space:]]/, "", $1)  # Remove whitespace from username
        username=$1
        gsub(/[[:space:]]/, "", $2)  # Remove whitespace from groups
        groups=$2
        split(groups, group_list, ",")
        
        # Add user to personal group
        personal_group=group_prefix username
        system("groupadd -f " personal_group)
        system("usermod -aG " personal_group " " username)
        if (system("id -nG " username " | grep -qw " personal_group) != 0) {
            system("echo \"Failed to add user " username " to personal group " personal_group ".\" >> " log_file)
            success=0
        } else {
            system("echo \"User " username " added to personal group " personal_group ".\" >> " log_file)
        }
        
        # Add user to specified groups
        for (i in group_list) {
            group=group_list[i]
            system("groupadd -f " group)
            system("usermod -aG " group " " username)
            if (system("id -nG " username " | grep -qw " group) != 0) {
                system("echo \"Failed to add user " username " to group " group ".\" >> " log_file)
                success=0
            } else {
                system("echo \"User " username " added to group " group ".\" >> " log_file)
            }
        }
    }
    END {
        exit success
    }' "$USER_FILE"

    return $?
}

# Function to set password securely
set_password() {
    local username="$1"
    local password="$2"

    # Store password securely in files
    echo "$username,$password" >> "$PASSWORD_FILE"
    local encrypted_password=$(openssl enc -aes-256-cbc -a -salt -pass pass:mysecretpassword <<< "$password")
    echo "$username,$encrypted_password" >> "$ENCRYPTED_PASSWORD_FILE"

    log_action "Password set securely for user $username."
}

# Function to check if user belongs to all specified groups
check_user_groups() {
    local username="$1"
    local groups="$2"
    local all_groups_exist=1

    IFS=',' read -ra group_list <<< "$groups"
    for group in "${group_list[@]}"; do
        if ! id -nG "$username" | grep -qw "$group"; then
            log_action "User $username does not belong to group $group."
            all_groups_exist=0
        fi
    done

    return $all_groups_exist
}

# Main script logic
while IFS=';' read -r username groups; do
    username=$(echo "$username" | tr -d '[:space:]')  # Remove whitespace

    # Create user if it doesn't exist
    create_user "$username"

    # Add user to personal group and specified groups
    if add_user_to_groups "$username" "$groups"; then
        log_action "User $username setup complete."
    else
        log_action "Failed to setup user $username completely."
    fi

    # Generate and set password for the user
    local password=$(generate_password)
    set_password "$username" "$password"

    # Check if user belongs to all specified groups
    if check_user_groups "$username" "$groups"; then
        log_action "User $username belongs to all specified groups."
    else
        log_action "User $username does not belong to all specified groups."
    fi

done < "$USER_FILE"

log_action "User creation script completed."

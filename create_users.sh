#!/bin/bash

#file paths
USER_FILE="/var/user_list/users.txt"
LOG_FILE="/var/log/user_management.log"
PASSWORD_FILE="/var/secure/user_passwords.txt"

# Ensure necessary directories and permissions
mkdir -p /var/log
mkdir -p /var/secure
touch $LOG_FILE
chmod 600 $PASSWORD_FILE
chmod 600 $LOG_FILE  # Ensure log file has secure permissions

# Function to generate random passwords securely
generate_password() {
    openssl rand -base64 12
}

# Function to securely log actions
log_action() {
    echo "$(date) - $1" >> $LOG_FILE
}

# Function to check if a group exists
group_exists() {
    getent group "$1" >/dev/null 2>&1
}

# Main script logic
while IFS=';' read -r user groups personal_group; do
    # Check if user already exists
    if id "$user" &>/dev/null; then
        log_action "User $user already exists."
    else
        # Create user and set up home directory
        useradd -m -s /bin/bash "$user"
        if [ $? -ne 0 ]; then
            log_action "Failed to create user $user."
            continue
        fi
        log_action "User $user created."
    fi

    # Ensure all specified groups are created and user is added to them
    IFS=',' read -ra group_list <<< "$groups"
    for group in "${group_list[@]}"; do
        if ! group_exists "$group"; then
            groupadd "$group"
            log_action "Group $group created."
        fi
        usermod -aG "$group" "$user"
        log_action "User $user added to group $group."
    done

    # Ensure personal group is created for each user
    if ! group_exists "$personal_group"; then
        groupadd "$personal_group"
        log_action "Personal group $personal_group created."
    fi
    usermod -aG "$personal_group" "$user"
    log_action "User $user added to personal group $personal_group."

    # Check if user is added to personal group
    if id -nG "$user" | grep -qw "$personal_group"; then
        log_action "User $user belongs to personal group $personal_group."
    else
        log_action "Failed to add user $user to personal group $personal_group."
    fi

    # Generate and set password securely
    password=$(generate_password)
    echo "$user:$password" | chpasswd
    log_action "Password set for user $user."

    # Store password securely
    echo "$user:$password" >> $PASSWORD_FILE

done < "$USER_FILE"

log_action "User creation script completed."

#!/bin/bash

# Check for root privileges
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit 1
fi

# Path to the CSV file
CSV_FILE="users.csv"

# Check if the CSV file exists
if [ ! -f "$CSV_FILE" ]; then
    echo "CSV file not found!"
    exit 1
fi

# Function to display user details in a table format
display_user_table() {
    echo -e "\n+----------------------------------------------------------------------------------------------------------------------------------------------------+"
    echo -e "| User          | Group0       | Group1       | Group2       | Group3       | Full Name                  | Room Number   | Work Phone  | Home Phone  | Other          | Password     |"
    echo -e "+----------------------------------------------------------------------------------------------------------------------------------------------------+"
    for user_info in "${users_info[@]}"; do
        IFS=';' read -r username group0 group1 group2 group3 fullname room workphone homephone other password <<< "$user_info"
        printf "| %-13s| %-12s| %-12s| %-12s| %-12s| %-25s| %-13s| %-11s| %-11s| %-13s| %-12s|\n" "$username" "$group0" "$group1" "$group2" "$group3" "$fullname" "$room" "$workphone" "$homephone" "$other" "$password"
        echo -e "+----------------------------------------------------------------------------------------------------------------------------------------------------+"
    done
}

# Read the CSV file and store user details, skipping the header line
declare -a users_info
{
    read # skip the header line
    while IFS=';' read -r username group0 group1 group2 group3 fullname room workphone homephone other password; do
        # Stop processing if EOF is encountered
        if [ "$username" == "EOF" ]; then
            break
        fi

        # Store user information
        users_info+=("$username;$group0;$group1;$group2;$group3;$fullname;$room;$workphone;$homephone;$other;$password")
    done
} < "$CSV_FILE"

# Display all users to be added
echo -e "\nUsers to be added:\n"
display_user_table

# Ask for user confirmation
read -p "Do you want to continue adding these users? (y/n): " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Operation aborted."
    exit 0
fi

# Add users and update /etc/ssh/sshd_config
for user_info in "${users_info[@]}"; do
    IFS=';' read -r username group0 group1 group2 group3 fullname room workphone homephone other password <<< "$user_info"
    
    # Check if user already exists
    if id "$username" &>/dev/null; then
        echo "User $username already exists. Skipping."
        continue
    fi

    # Add user and primary group
    adduser --gecos "$fullname,$room,$workphone,$homephone,$other" --disabled-password "$username"
    
    # Add user to additional groups
    usermod -aG "$group0" "$username"
    [ -n "$group1" ] && usermod -aG "$group1" "$username"
    [ -n "$group2" ] && usermod -aG "$group2" "$username"
    [ -n "$group3" ] && usermod -aG "$group3" "$username"

    # Ensure sudo rights if specified
    if [[ "$group3" == "sudo" ]]; then
        usermod -aG sudo "$username"
    fi

    # Set the user password
    echo "$username:$password" | chpasswd

    echo "User $username added successfully."
done

# Function to add users to /etc/ssh/sshd_config AllowUsers
update_sshd_config() {
    SSHD_CONFIG="/etc/ssh/sshd_config"
    ALLOW_USERS_LINE=$(grep "^AllowUsers" $SSHD_CONFIG)

    # Create AllowUsers line if it doesn't exist
    if [ -z "$ALLOW_USERS_LINE" ]; then
        echo "AllowUsers line not found in $SSHD_CONFIG, adding it."
        echo "AllowUsers" >> $SSHD_CONFIG
        ALLOW_USERS_LINE="AllowUsers"
    fi

    # Loop through users to be added
    for user_info in "${users_info[@]}"; do
        IFS=';' read -r username group0 group1 group2 group3 fullname room workphone homephone other password <<< "$user_info"
        
        # Check if user is already in AllowUsers line
        if ! grep -q "$username" <<< "$ALLOW_USERS_LINE"; then
            echo "Adding $username to AllowUsers."
            sed -i "/^AllowUsers/ s/$/ $username/" $SSHD_CONFIG
        else
            echo "$username is already in AllowUsers."
        fi
    done

    # Restart SSH service to apply changes
    systemctl restart sshd
}

# Update sshd_config to allow new users
update_sshd_config

echo "All users have been processed."

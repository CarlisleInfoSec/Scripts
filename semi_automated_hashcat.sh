#!/bin/bash

# Path to your dictionary file
DICT_FILE="rockyou.txt"

# Prompt for hash
read -p "Please paste the hash you want to crack: " hash

# Check if hash provided
if [ -z "$hash" ]; then
  echo "Error: No hash provided."
  exit 1
fi

# Auto-detect hash type
hash_type=$(hashid -m "$hash" | head -n 1 | awk -F: '{print $2}' | xargs)

# Handle unknown hash type
if [ -z "$hash_type" ]; then
  echo "Warning: Could not auto-detect hash type. Hashid output: $(hashid -m "$hash")"

  # Prompt for manual mode input
  read -p "Please enter the hashcat mode (-m value) from the hashid output: " manual_mode
  while [[ ! "$manual_mode" =~ ^[0-9]+$ ]]; do
    echo "Invalid mode. Please enter a number."
    read -p "Please enter the hashcat mode (-m value) from the hashid output: " manual_mode
  done
  hash_type="$manual_mode"
  echo "Using manual hash mode: $hash_type"
else
  echo "Detected hash type: $hash_type"
fi

# Prompt for password length
read -p "If you know the password length, enter the number of characters (or press Enter to skip): " pwd_length

# Create a temporary file to store the hash
temp_hash_file=$(mktemp)
echo "$hash" > "$temp_hash_file"

# Crack the hash with hashcat
if [ -n "$pwd_length" ]; then
  # Filter the dictionary file for passwords with the specified length
  filtered_dict_file=$(mktemp)
  awk -v len="$pwd_length" 'length($0) == len' "$DICT_FILE" > "$filtered_dict_file"

  hashcat_command="hashcat -m $hash_type -a 0 -w 4 $temp_hash_file $filtered_dict_file"
  hashcat_output=$(eval $hashcat_command)

  # Clean up the filtered dictionary file
  rm "$filtered_dict_file"
else
  hashcat_command="hashcat -m $hash_type -a 0 -w 4 $temp_hash_file $DICT_FILE"
  hashcat_output=$(eval $hashcat_command)
fi

# Check hashcat exit code
hashcat_exit_code=$?
if [ $hashcat_exit_code -ne 0 ]; then
  echo "Error: hashcat exited with code $hashcat_exit_code. Check hashcat output for details."
  echo "$hashcat_output"  # Print hashcat output for debugging
  rm "$temp_hash_file"  # Clean up temporary file
  exit 1
fi

# Parse hashcat output
cracked_password=$(hashcat --show -m $hash_type $temp_hash_file | awk -F: '{print $2}')

# Display results
if [ -n "$cracked_password" ]; then
  echo "Hash cracked!"
  echo "Password: $cracked_password"
else
  echo "Password not found."
fi

# Clean up temporary file
rm "$temp_hash_file"

exit 0

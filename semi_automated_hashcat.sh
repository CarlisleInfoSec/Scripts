#!/bin/bash

# Path to your dictionary file and rules file
DICT_FILE="rockyou.txt"
RULES_FILE="/usr/share/hashcat/rules/best64.rule"

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

# Define hash types that require a separate salt
SALT_REQUIRED_TYPES=("131" "132" "133" "134" "135" "200" "300" "7400" "7410" "7420" "14300" "14400" "1710" "9900" "12" "130" "22000" "8900" "13200" "8200" "19100")

# Check if the detected hash type requires a separate salt
needs_salt=false
for salt_type in "${SALT_REQUIRED_TYPES[@]}"; do
  if [ "$hash_type" == "$salt_type" ]; then
    needs_salt=true
    break
  fi
done

# Prompt for salt if needed
if [ "$needs_salt" == true ]; then
  read -p "This hash type requires a salt. Please enter the salt: " salt
fi

# Prompt for password length
read -p "If you know the password length, enter the number of characters or a range (e.g., 9-12) (or press Enter to skip): " pwd_length

# Create a temporary file to store the hash
temp_hash_file=$(mktemp)
if [ -n "$salt" ]; then
  echo "$hash:$salt" > "$temp_hash_file"
else
  echo "$hash" > "$temp_hash_file"
fi

# Function to filter dictionary file by length or range
filter_dict_file() {
  local length=$1
  local dict_file=$2
  local filtered_file=$3

  if [[ "$length" =~ ^[0-9]+-[0-9]+$ ]]; then
    # Length range provided (e.g., 9-12)
    local min_length=$(echo $length | cut -d'-' -f1)
    local max_length=$(echo $length | cut -d'-' -f2)
    grep -E "^.{$min_length,$max_length}$" "$dict_file" > "$filtered_file"
  elif [[ "$length" =~ ^[0-9]+$ ]]; then
    # Single length provided (e.g., 10)
    grep -E "^.{$length}$" "$dict_file" > "$filtered_file"
  else
    cp "$dict_file" "$filtered_file"
  fi
}

# Crack the hash with hashcat using rule-based attacks
if [ -n "$pwd_length" ]; then
  # Filter the dictionary file for passwords with the specified length or range
  filtered_dict_file=$(mktemp)
  filter_dict_file "$pwd_length" "$DICT_FILE" "$filtered_dict_file"

  hashcat_command="hashcat -m $hash_type -a 0 -r $RULES_FILE -w 4 $temp_hash_file $filtered_dict_file"
  hashcat_output=$(eval $hashcat_command)

  # Clean up the filtered dictionary file
  rm "$filtered_dict_file"
else
  hashcat_command="hashcat -m $hash_type -a 0 -r $RULES_FILE -w 4 $temp_hash_file $DICT_FILE"
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

#!/bin/bash

# Path to your dictionary file and rules file
DICT_FILE="rockyou.txt"
RULES_FILE="/usr/share/hashcat/rules/best64.rule"

# Helper function to display a help message
display_help() {
  echo "Usage: $0 [options]"
  echo ""
  echo "Options:"
  echo "  -h, --help            Show this help message"
  echo "  -d, --dict-file FILE  Path to the dictionary file (default: rockyou.txt)"
  echo "  -r, --rules-file FILE Path to the rules file (default: /usr/share/hashcat/rules/best64.rule)"
  echo "  -H, --hash HASH       The hash you want to crack"
  echo "  -m, --mode MODE       Hashcat mode to use"
  echo "  -p, --pwd-length LEN  Password length (or press Enter to skip)"
  echo "  -s, --salt SALT       Salt value for hash types requiring a salt"
  echo "  -n, --numeric-only    Indicates if the password is numeric only (for brute force)"
  exit 0
}

# Default values
hash=""
manual_mode=""
pwd_length=""
salt=""
numeric_only=false

# Parse command-line arguments
while [[ "$1" != "" ]]; do
  case $1 in
    -h | --help )
      display_help
      ;;
    -d | --dict-file )
      shift
      DICT_FILE="$1"
      ;;
    -r | --rules-file )
      shift
      RULES_FILE="$1"
      ;;
    -H | --hash )
      shift
      hash="$1"
      ;;
    -m | --mode )
      shift
      manual_mode="$1"
      ;;
    -p | --pwd-length )
      shift
      pwd_length="$1"
      ;;
    -n | --numeric-only )
      numeric_only=true
      ;;
    -s | --salt )
      shift
      salt="$1"
      ;;
    * )
      echo "Unknown option: $1"
      display_help
      ;;
  esac
  shift
done

# Prompt for hash if not provided
if [ -z "$hash" ]; then
  read -p "Please paste the hash you want to crack: " hash
fi

# Check if hash provided
if [ -z "$hash" ]; then
  echo "Error: No hash provided."
  exit 1
fi

# Prompt for password length if not provided
if [ -z "$pwd_length" ]; then
  read -p "If you know the password length, enter the number of characters (or press Enter to skip): " pwd_length
fi

# Ask if the password is numeric-only
read -p "Is the password numeric only? (y/n): " numeric_response
if [[ "$numeric_response" =~ ^[Yy]$ ]]; then
  numeric_only=true
fi

# Run hashid and show the output
echo "Running hashid to detect hash type..."
hashid_output=$(hashid -m "$hash")
echo "Hashid output:"
echo "$hashid_output"

# Ask for the mode
read -p "Please enter the hashcat mode (-m value) from the hashid output (or press Enter to auto-detect): " manual_mode

# Auto-detect hash type if not provided
if [ -z "$manual_mode" ]; then
  hash_type=$(echo "$hashid_output" | grep -o 'Hashcat Mode: [0-9]*' | awk '{print $3}' | head -n 1)
else
  hash_type="$manual_mode"
fi

# Debugging output
echo "Using hashcat mode: $hash_type"

# Define hash types that require a separate salt (and how they use it)
SALT_REQUIRED_TYPES=(
    "131:salt:hash"       # Example: MD5 with salt:hash
    "132:salt:hash"       # Example: MD5-Crypt with salt:hash
    "1450:key:hash"       # HMAC-SHA1 (key is the entire salt)
    "150:key:password"    # HMAC-SHA1 (key is prepended to the password)
    "16500:key_hex:hash"  # HMAC-SHA1-HEX (key is hex-encoded)
)

# Check if salt is needed and how to use it
needs_salt=false
salt_format=""
for salt_type in "${SALT_REQUIRED_TYPES[@]}"; do
    parts=(${salt_type//:/ }) # Split string by ':'
    if [[ "$hash_type" == "${parts[0]}" ]]; then
        needs_salt=true
        salt_format="${parts[1]}"
        break
    fi
done

# Prompt for salt/key if needed
if [ "$needs_salt" == true ]; then
    if [ -z "$salt" ]; then
        if [[ "$hash_type" == "16500" ]]; then
            read -p "This is HMAC-SHA1-HEX. Please enter the HEX-encoded key: " salt
        else
            read -p "This hash type requires a salt/key. Please enter it: " salt
        fi
    fi
    if [ -z "$salt" ]; then
        echo "Error: No salt/key provided for $hash_type."
        exit 1
    fi
fi

# Handle numeric brute force if specified
if [ "$numeric_only" == true ]; then
  if [[ "$pwd_length" =~ ^[0-9]+$ ]]; then
    echo "Performing brute force attack for a numeric password of $pwd_length digits..."
    mask=$(printf '?d%.0s' $(seq 1 $pwd_length))  # Generate mask with ?d repeated pwd_length times
  else
    echo "Performing brute force attack for numeric passwords (defaulting to length range 1-12)..."
    mask="?d?d?d?d?d?d?d?d?d?d?d?d"  # Broad numeric brute force mask
  fi
  brute_force_command="hashcat -m $hash_type -a 3 -w 4 '$hash:$salt' $mask"
  echo "Full brute force command line: $brute_force_command"
  eval "$brute_force_command"
  brute_force_exit_code=$?

  if [ $brute_force_exit_code -ne 0 ]; then
      echo "Error: Hashcat failed during brute force. Check output above for details."
      exit 1
  fi

  # Check for cracked password
  cracked_password=$(hashcat --show -m $hash_type <<< "$hash:$salt" | awk -F: '{print $2}')

  if [ -n "$cracked_password" ]; then
      echo "Hash cracked via brute force!"
      echo "Password: $cracked_password"
  else
      echo "Password not found with brute force."
  fi
  exit 0
fi

# Dictionary-based attack if not numeric
echo "Performing dictionary attack..."
if [ "$needs_salt" == true ]; then
    if [[ "$hash_type" == "16500" ]]; then
        hashcat_command="hashcat -m $hash_type -a 0 -r $RULES_FILE -w 4 '$salt:$hash' $DICT_FILE"
    elif [[ "$hash_type" == "150" ]]; then
        hashcat_command="hashcat -m $hash_type -a 0 -r $RULES_FILE -w 4 '$hash:$salt' $DICT_FILE"
    else
        hashcat_command="hashcat -m $hash_type -a 0 -r $RULES_FILE -w 4 '$salt:$hash' $DICT_FILE"
    fi
else
    hashcat_command="hashcat -m $hash_type -a 0 -r $RULES_FILE -w 4 '$hash' $DICT_FILE"
fi

echo "Full dictionary attack command line: $hashcat_command"
eval "$hashcat_command"
hashcat_exit_code=$?

if [ $hashcat_exit_code -ne 0 ]; then
  echo "Error: Hashcat failed during dictionary attack. Check output above for details."
  exit 1
fi

# Check for cracked password
cracked_password=$(hashcat --show -m $hash_type <<< "$hash:$salt" | awk -F: '{print $2}')

if [ -n "$cracked_password" ]; then
    echo "Hash cracked!"
    echo "Password: $cracked_password"
else
    echo "Password not found with dictionary attack."
fi

exit 0

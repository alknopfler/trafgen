#!/bin/bash
# unit test

# Function to generate a range of CPU cores from the physcpubind string
# Arguments: physcpubind_string num_cores
# Example usage: generate_core_range "physcpubind: 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23" 2
generate_core_range() {

    local physcpubind_str=$1
    local num_cores=$2
    local cores=$(echo "$physcpubind_str" | awk -F': ' '{print $2}')

    IFS=' ' read -r -a cores_array <<< "$cores"
    local cores_count=${#cores_array[@]}

    if [ "$num_cores" -lt 1 ] || [ "$num_cores" -gt "$cores_count" ]; then
        echo "Invalid number of cores requested"
        return 1
    fi

    local start_idx=$(( (cores_count - num_cores) / 2 ))
    local end_idx=$(( start_idx + num_cores - 1 ))
    local core_range="${cores_array[$start_idx]}-${cores_array[$end_idx]}"
    echo "$core_range"
}

physcpubind_str="physcpubind: 0 1 2 3"
num_cores=3
core_range=$(generate_core_range "$physcpubind_str" "$num_cores")
echo "Core range for $num_cores cores: $core_range"
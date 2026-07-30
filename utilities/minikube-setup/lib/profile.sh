#!/bin/bash
# Functions for listing, selecting, creating, and loading profiles

# Load profile settings and export as environment variables
load_profile_settings() {
    local config_file="$1"
    local profile_name="$2"
    local base_path="$3"
    local env_file="${base_path}/env/minikube_${profile_name}.env"
    mkdir -p "${base_path}/env"

    # Validate profile exists
    if ! jq -e ".Minikube_Settings.\"$profile_name\"" "$config_file" &>/dev/null; then
        die "Profile '$profile_name' not found in $config_file"
    fi

    # Write environment file
    jq -r ".Minikube_Settings.\"$profile_name\" | to_entries[] | \"export MINIKUBE_\(.key | ascii_upcase)=\(.value | @sh)\"" "$config_file" > "$env_file"

    # Source it to export in current shell
    source "$env_file"
    echo "$env_file"
}

# List available profiles with numbers
list_profiles() {
    local config_file="$1"
    jq -r '.Minikube_Settings | to_entries[] | "\(.key): Profile=\(.value.Profile_Name) Mem=\(.value.Memory) CPUs=\(.value.CPUs) Storage=\(.value.Storage) Runtime=\(.value.Container_Runtime)"' "$config_file" | nl -w2 -s'. '
}

# Interactive profile selection (or return default if non‑interactive)
select_profile() {
    local config_file="$1"
    local non_interactive="$2"
    local profiles=($(jq -r '.Minikube_Settings | keys[]' "$config_file"))

    if [[ "$non_interactive" == true ]]; then
        # Return first profile as default
        echo "${profiles[0]}"
        return
    fi

    echo "Available profiles:"
    list_profiles "$config_file"
    echo ""
    read -p "Select profile by number (default 1): " choice
    choice=${choice:-1}
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#profiles[@]} )); then
        die "Invalid selection"
    fi
    echo "${profiles[$((choice-1))]}"
}

# Create a new profile interactively
create_new_profile() {
    local config_file="$1"
    local base_path="$2"
    # This function would prompt for all settings and append to profiles.json
    # Implementation omitted for brevity – similar to original get_infra_configuration
    # but writes to the JSON file instead of an env file.
}

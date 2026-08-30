#!/usr/bin/env bash

declare -A VENDORS=(
    [0x10de]="NVIDIA"
    [0x1002]="AMD"
    [0x8086]="Intel"
)

SOFTWARE_VENDORS=("0x1414" "0x15ad" "0x80ee")

pci_class_name() {
    case "$1" in
        0x030000) echo "VGA" ;;
        0x030200) echo "3D" ;;
        0x038000) echo "Display" ;;
        *)        echo "Unknown" ;;
    esac
}

gpus=""
for dev in /sys/bus/pci/devices/*; do
    class=$(cat "$dev/class" 2>/dev/null | cut -c1-8)
    case "$class" in
        0x030000|0x030200|0x038000)
            vendor_id=$(cat "$dev/vendor" 2>/dev/null)
            # Skip software renderers
            skip=0
            for sw in "${SOFTWARE_VENDORS[@]}"; do
                if [[ "$vendor_id" == "$sw" ]]; then
                    skip=1
                    break
                fi
            done
            [[ $skip -eq 1 ]] && continue

            device_id=$(cat "$dev/device" 2>/dev/null)
            vendor_name="${VENDORS[$vendor_id]:-$vendor_id}"
            bdf=$(basename "$dev")
            bdf_short="${bdf#0000:}"
            class_name=$(pci_class_name "$class")
            gpus+="$bdf_short $class_name: $vendor_name Device $device_id\n"
            ;;
    esac
done

if [[ -n "$gpus" ]]; then
    echo -e "Real GPU(s) available:"
    echo -e "$gpus"
    
    if echo "$gpus" | grep -qi "NVIDIA"; then
        echo "→ NVIDIA GPU detected"
        if command -v nvidia-smi >/dev/null && nvidia-smi -L >/dev/null 2>&1; then
            echo "  NVIDIA driver is loaded and working"
            nvidia-smi -L
        fi
    fi
    if echo "$gpus" | grep -qi "AMD"; then
        echo "→ AMD GPU detected"
    fi
    if echo "$gpus" | grep -qi "Intel"; then
        echo "→ Intel GPU detected"
    fi
else
    echo "No real GPU detected (only software renderers or no device found)."
fi
#!/usr/bin/env bash

# IDOL OS detection (Ubuntu / macOS) — loads module/os-compat.sh when present
if [ -z "${IDOL_OS_COMPAT_LOADED:-}" ]; then
  _idol_os_src=""
  if [ -n "${IDOL_BASE_PATH:-}" ] && [ -f "${IDOL_BASE_PATH}/module/os-compat.sh" ]; then
    _idol_os_src="${IDOL_BASE_PATH}/module/os-compat.sh"
  else
    _idol_os_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
    _idol_os_probe="$_idol_os_dir"
    _idol_os_i=0
    while [ -n "$_idol_os_probe" ] && [ "$_idol_os_probe" != "/" ] && [ "$_idol_os_i" -lt 20 ]; do
      if [ -f "$_idol_os_probe/module/os-compat.sh" ]; then
        _idol_os_src="$_idol_os_probe/module/os-compat.sh"
        break
      fi
      _idol_os_probe="$(dirname "$_idol_os_probe")"
      _idol_os_i=$((_idol_os_i + 1))
    done
  fi
  if [ -n "$_idol_os_src" ]; then
    # shellcheck source=/dev/null
    . "$_idol_os_src"
  else
    case "$(uname -s 2>/dev/null)" in
      Darwin)
        export IDOL_HOST_OS=macos IDOL_OS_FAMILY=macos
        ;;
      Linux)
        export IDOL_OS_FAMILY=linux
        if [ -f /etc/os-release ] && grep -qi ubuntu /etc/os-release 2>/dev/null; then
          export IDOL_HOST_OS=ubuntu
        else
          export IDOL_HOST_OS=linux
        fi
        ;;
      *)
        export IDOL_HOST_OS=unknown IDOL_OS_FAMILY=unknown
        ;;
    esac
  fi
  unset _idol_os_src _idol_os_dir _idol_os_probe _idol_os_i
fi

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
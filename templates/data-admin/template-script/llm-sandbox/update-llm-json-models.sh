#!/bin/bash
# =============================================================================
# ollama_json_updater.sh  ← NOW UPDATES "name" + structured ollama_info
# =============================================================================

set -euo pipefail

JSON_FILE="${1:-}"

if [ -z "$JSON_FILE" ] || [ ! -f "$JSON_FILE" ]; then
  echo "❌ Usage: $0 default-models.json"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "❌ jq is required → sudo apt install jq"
  exit 1
fi

if ! docker exec ollama true 2>/dev/null; then
  echo "❌ Ollama container not reachable"
  exit 1
fi

# Backup
BACKUP="${JSON_FILE}.bak.$(date +%Y%m%d_%H%M%S)"
cp "$JSON_FILE" "$BACKUP"
echo "✅ Backup created → $BACKUP"

# Get Ollama models
echo "🔍 Fetching models from Ollama..."
mapfile -t OLLAMA_MODELS < <(docker exec ollama ollama list | tail -n +2 | awk '{print $1}')
echo "📦 Found ${#OLLAMA_MODELS[@]} models: ${OLLAMA_MODELS[*]}"

TEMP_JSON="${JSON_FILE}.tmp.$$"
cp "$JSON_FILE" "$TEMP_JSON"

# Parser: turns ollama show into clean structured JSON
parse_ollama_show() {
  docker exec ollama ollama show "$1" 2>/dev/null | python3 -c '
import sys, json, re
text = sys.stdin.read()
data = {
    "tag": sys.argv[1],
    "architecture": None,
    "parameter_count": None,
    "context_length": None,
    "embedding_length": None,
    "quantization": None,
    "capabilities": [],
    "default_parameters": {},
    "system_prompt": None
}
current_section = None
for line in text.splitlines():
    line = line.strip()
    if not line: continue
    if line in ["Model", "Capabilities", "Parameters", "System"]:
        current_section = line
        continue
    if current_section == "Model":
        if "architecture" in line.lower(): data["architecture"] = line.split()[-1]
        elif "parameters" in line.lower(): data["parameter_count"] = line.split()[-1]
        elif "context length" in line.lower(): data["context_length"] = int(line.split()[-1])
        elif "embedding length" in line.lower(): data["embedding_length"] = int(line.split()[-1])
        elif "quantization" in line.lower(): data["quantization"] = line.split()[-1]
    elif current_section == "Capabilities":
        if line: data["capabilities"].append(line.lower())
    elif current_section == "Parameters":
        if " " in line:
            key = line.split()[0]
            value = " ".join(line.split()[1:])
            if value.isdigit(): data["default_parameters"][key] = int(value)
            elif value.replace(".", "", 1).replace("-", "", 1).isdigit(): data["default_parameters"][key] = float(value)
            else: data["default_parameters"][key] = value
    elif current_section == "System":
        if data["system_prompt"] is None:
            data["system_prompt"] = line
        else:
            data["system_prompt"] += "\n" + line
print(json.dumps(data))
' "$1"
}

# Process each model
for model in "${OLLAMA_MODELS[@]}"; do
  echo "📥 Processing → $model"

  STRUCTURED=$(parse_ollama_show "$model" || echo '{"error": "failed to parse"}')

  jq --arg model_tag "$model" \
     --argjson structured "$STRUCTURED" '
    def update_array:
      map(
        if type == "object" and has("name") then
          (.name | ascii_downcase) as $n
          | ($model_tag | ascii_downcase | sub(":latest$"; "") | sub(":[^:]+$"; "")) as $m
          | if ($n | contains($m)) or ($m | contains($n)) then
              . + {
                "name": $structured.tag,           # ← UPDATED NAME with ollama tag
                "ollama_info": $structured
              }
            else . end
        else . end
      );

    if type == "array" then
      update_array
    elif type == "object" then
      if has("supported")      then .supported      = (.supported      | update_array)
      elif has("custom_required") then .custom_required = (.custom_required | update_array)
      elif has("models")       then .models         = (.models         | update_array)
      elif has("data")         then .data           = (.data           | update_array)
      elif has("items")        then .items          = (.items          | update_array)
      else .
      end
    else .
    end
  ' "$TEMP_JSON" > "${TEMP_JSON}.new" && mv "${TEMP_JSON}.new" "$TEMP_JSON"
done

mv "$TEMP_JSON" "$JSON_FILE"

echo ""
echo "🎉 SUCCESS! Updated $JSON_FILE"
echo "   • ${#OLLAMA_MODELS[@]} models processed"
echo "   • Top-level \"name\" is now the exact Ollama tag"
echo "   • Full structured \"ollama_info\" added"
echo ""
echo "🔍 Verification:"
jq -r '.supported[]? | select(has("ollama_info")) | "\(.name)  ←  ollama_info.tag = \(.ollama_info.tag)"' "$JSON_FILE" || true
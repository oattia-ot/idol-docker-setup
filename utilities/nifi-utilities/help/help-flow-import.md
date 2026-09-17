# NiFi Flow Import Script Documentation

## Overview
A robust Bash script for importing JSON flow templates into Apache NiFi with intelligent duplicate handling, automatic renaming, and comprehensive error checking. Perfect for CI/CD pipelines and automated deployments.

## Features
- ✅ **Intelligent Duplicate Handling** - Multiple strategies for name conflicts
- ✅ **Flexible Authentication** - Password, token, or no authentication
- ✅ **Auto-Renaming** - Automatically resolves naming conflicts
- ✅ **Flow State Control** - Option to import flows as disabled
- ✅ **Position Control** - Set precise canvas coordinates
- ✅ **Verbose Logging** - Detailed debugging output
- ✅ **Quiet Mode** - Minimal output for scripting
- ✅ **Interactive Mode** - User-friendly prompts
- ✅ **Non-interactive Mode** - Full automation for CI/CD
- ✅ **JSON Validation** - Optional validation with jq
- ✅ **Comprehensive Error Handling** - Clear error messages and exit codes

## Installation & Dependencies

### Required
- **curl** - For API calls to NiFi

### Recommended
- **jq** - For JSON parsing (enhanced features)

### Install Dependencies
```bash
# Debian/Ubuntu
sudo apt-get install curl jq

# RHEL/CentOS
sudo yum install curl jq

# macOS
brew install curl jq
```

## Usage

### Basic Syntax
```bash
./nifi-flow-import.sh [OPTIONS] <flow_file_path> <flow_name>
./nifi-flow-import.sh [OPTIONS] --file <flow_file_path> --name <flow_name>
```

### Positional Arguments
| Argument | Description | Required |
|----------|-------------|----------|
| `flow_file_path` | Path to JSON flow template file | Yes |
| `flow_name` | Name for the imported flow | Yes |

### Command Line Options

#### Required Options
| Option | Short | Description | Default |
|--------|-------|-------------|---------|
| `--file` | `-f` | Path to JSON flow template file | - |
| `--name` | `-n` | Name for the imported flow | - |

#### Connection Options
| Option | Short | Description | Default |
|--------|-------|-------------|---------|
| `--url` | `-u` | NiFi URL | `https://idol-docker-host:8443` |
| `--auth` | `-a` | Authentication method: `password`, `token`, `none` | `password` |
| `--username` | `-U` | Username for password auth | `admin` |
| `--password` | `-P` | Password for password auth | `Nifi-Admin1!` |
| `--token` | `-t` | Bearer token for token auth | - |

#### Flow Control Options
| Option | Short | Description | Default |
|--------|-------|-------------|---------|
| `--disable` | `-d` | Disable the imported flow | `true` |
| `--no-disable` | | Do NOT disable the imported flow | - |
| `--overwrite` | `-o` | Overwrite existing flow if name conflicts | `false` |
| `--rename` | `-r` | Auto-rename if name conflicts | `true` |
| `--position-x` | `-x` | X position for flow placement | `100` |
| `--position-y` | `-y` | Y position for flow placement | `100` |
| `--comments` | `-c` | Comments for the imported flow | "Imported via API - Created as DISABLED" |
| `--client-id` | `-C` | Custom client ID for the upload | Auto-generated |

#### Behavior Options
| Option | Short | Description | Default |
|--------|-------|-------------|---------|
| `--yes` | `-Y` | Skip all confirmation prompts | `false` |
| `--verbose` | `-v` | Enable verbose output | `false` |
| `--quiet` | `-q` | Suppress non-essential output | `false` |
| `--help` | `-h` | Display help message | - |

## Duplicate Handling Strategies

### 1. Delete Existing (`--overwrite`)
```bash
# Deletes existing flow and uploads new one
./nifi-flow-import.sh -f flow.json -n "MyFlow" -o -Y
```

### 2. Auto-Rename (`--rename`, DEFAULT)
```bash
# Automatically renames with suffix (MyFlow → MyFlow_1, MyFlow_2, etc.)
./nifi-flow-import.sh -f flow.json -n "MyFlow" -r
```

### 3. Interactive Prompt (when not using `--yes`)
```bash
# Presents options when duplicate detected
./nifi-flow-import.sh -f flow.json -n "MyFlow"
```

## Usage Examples

### 1. Basic Interactive Import
```bash
./nifi-flow-import.sh ./templates/basic.json "Basic Flow"
```

### 2. Automated CI/CD Pipeline
```bash
./nifi-flow-import.sh \
  -f ${WORKSPACE}/flow.json \
  -n "${JOB_NAME}-${BUILD_NUMBER}" \
  -c "Automated deploy from Jenkins" \
  --client-id "jenkins-${BUILD_TAG}" \
  -Y -r -u ${NIFI_URL}
```

### 3. Token Authentication
```bash
./nifi-flow-import.sh \
  -u https://idol-docker-host:8443 \
  -a token \
  -t "your-bearer-token" \
  -f ./flow.json \
  -n "Production Flow"
```

### 4. Overwrite Existing Flow
```bash
./nifi-flow-import.sh \
  --file ./templates/updated.json \
  --name "Production Flow" \
  --overwrite \
  --yes
```

### 5. Custom Configuration
```bash
./nifi-flow-import.sh \
  -x 200 -y 300 \
  -c "Production Import v2.0" \
  --client-id "deploy-script-001" \
  --no-disable \
  -f ./flow.json \
  -n "Production Flow v2"
```

### 6. Import Multiple Flows
```bash
# Flow 1
./nifi-flow-import.sh -f flow1.json -n "Flow1" -x 100 -y 100 -Y
# Flow 2
./nifi-flow-import.sh -f flow2.json -n "Flow2" -x 100 -y 500 -Y
# Flow 3
./nifi-flow-import.sh -f flow3.json -n "Flow3" -x 100 -y 900 -Y
```

### 7. Debug Mode
```bash
./nifi-flow-import.sh -f ./flow.json -n "Debug Flow" -v
```

## Flow File Format
The script expects a valid JSON flow template exported from NiFi:

```json
{
  "flow": {
    "processors": [ ... ],
    "connections": [ ... ],
    "processGroups": [ ... ],
    "remoteProcessGroups": [ ... ],
    "inputPorts": [ ... ],
    "outputPorts": [ ... ],
    "funnels": [ ... ],
    "labels": [ ... ]
  }
}
```

### Exporting from NiFi UI
1. Navigate to the process group in NiFi
2. Right-click on the process group
3. Select "Download flow"
4. Save as JSON file

## Authentication Methods

### 1. Password Authentication (DEFAULT)
Uses username/password to generate a token automatically:
```bash
./nifi-flow-import.sh -U customuser -P custompass -f flow.json -n "Flow"
```

### 2. Token Authentication
Use pre-generated bearer token:
```bash
./nifi-flow-import.sh -a token -t "your-token" -f flow.json -n "Flow"
```

### 3. No Authentication
For unsecured NiFi instances:
```bash
./nifi-flow-import.sh -a none -f flow.json -n "Flow"
```

## Flow States After Import

| State | Description | Default |
|-------|-------------|---------|
| **DISABLED** | Flow is disabled (recommended for imports) | ✅ Yes |
| **STOPPED** | Flow is stopped but enabled | No |
| **RUNNING** | Flow is running | No |
| **UNKNOWN** | Could not determine state | - |

## Exit Codes

| Code | Meaning | Description |
|------|---------|-------------|
| 0 | Success | Flow imported successfully |
| 1 | General Error | Unexpected error occurred |
| 2 | Invalid Arguments | Invalid command line options |
| 3 | File Not Found | Flow file doesn't exist or not readable |
| 4 | Authentication Failed | Could not authenticate with NiFi |
| 5 | API Connection Failed | Cannot connect to NiFi API |
| 6 | Upload Failed | Flow upload to NiFi failed |
| 7 | Duplicate Conflict | Flow name conflict not resolved |

## Configuration Defaults

| Setting | Default Value |
|---------|---------------|
| NiFi URL | `https://idol-docker-host:8443` |
| Username | `admin` |
| Password | `Nifi-Admin1!` |
| Position X | `100` |
| Position Y | `100` |
| Disable Flow | `true` |
| Auto Rename | `true` |
| Comments | "Imported via API - Created as DISABLED" |

## Troubleshooting

### Common Issues

#### Issue: "Flow file not found"
**Solution:** Use absolute paths or verify file exists:
```bash
./nifi-flow-import.sh "$(pwd)/flow.json" "MyFlow"
```

#### Issue: "Unable to access NiFi API"
**Solution:** Check:
1. NiFi server is running
2. URL is correct
3. Network connectivity
4. Authentication credentials
5. SSL certificates (if using self-signed)

#### Issue: "Duplicate flow detected"
**Solution:** Use one of these flags:
```bash
# Option 1: Overwrite
./nifi-flow-import.sh -f flow.json -n "MyFlow" -o -Y

# Option 2: Auto-rename
./nifi-flow-import.sh -f flow.json -n "MyFlow" -r -Y

# Option 3: Interactive
./nifi-flow-import.sh -f flow.json -n "MyFlow"
```

#### Issue: "Failed to disable flow"
**Solution:** The flow may be in an invalid state:
1. Check NiFi UI for errors
2. Manually disable from NiFi UI
3. Use `--no-disable` flag to skip disabling

### Verbose Debugging
Enable verbose mode to see detailed execution:
```bash
./nifi-flow-import.sh -f flow.json -n "DebugFlow" -v
```

## Best Practices

### 1. For CI/CD Pipelines
```bash
# Always use --yes for automation
# Use unique client IDs for tracking
# Set descriptive comments
./nifi-flow-import.sh \
  -f "$FLOW_FILE" \
  -n "$FLOW_NAME" \
  -c "Deployed by $CI_PROJECT_NAME @ $CI_COMMIT_SHA" \
  --client-id "$CI_PIPELINE_ID" \
  -Y -r
```

### 2. For Development
```bash
# Use interactive mode for testing
# Enable verbose output for debugging
# Start with disabled flows
./nifi-flow-import.sh ./dev-flow.json "Dev Flow" -v
```

### 3. For Production
```bash
# Use token authentication
# Disable flows on import
# Set proper coordinates for organization
./nifi-flow-import.sh \
  -a token -t "$PROD_TOKEN" \
  -f prod-flow.json \
  -n "Production v1.2" \
  -x 500 -y 500 \
  -c "Production deployment $(date)" \
  -Y
```

## Script Output Examples

### Successful Import (Interactive)
```
╔════════════════════════════════════════════════════════╗
║         NiFi Flow Import Mode                          ║
╚════════════════════════════════════════════════════════╝

✓ Using NiFi URL: https://idol-docker-host:8443

✓ Token generated successfully!

✓ Flow file found

✓ NiFi API is accessible

✓ No existing flow with this name found

✓ Flow uploaded successfully
Process Group ID: 018e6b9b-17d2-1000-ffff-ffffd5d5c6b4

✓ Disable request accepted
✓ Verified: Process group is DISABLED

✅ SUCCESS: The flow was imported and is DISABLED
```

### Quiet Mode (for scripting)
```
✓ Flow import completed: Production Flow -> 018e6b9b-17d2-1000-ffff-ffffd5d5c6b4 (DISABLED)
```

## API Endpoints Used
- `POST /nifi-api/access/token` - Generate authentication token
- `GET /nifi-api/flow/about` - Verify API accessibility
- `GET /nifi-api/flow/process-groups/root` - List existing process groups
- `DELETE /nifi-api/process-groups/{id}` - Delete existing process group
- `POST /nifi-api/process-groups/root/process-groups/upload` - Upload flow template
- `PUT /nifi-api/process-groups/{id}` - Update process group state
- `PUT /nifi-api/flow/process-groups/{id}` - Alternative state update

## Security Notes
1. **Passwords in command line** may be visible in process lists
2. **Consider using environment variables** for sensitive data:
   ```bash
   export NIFI_TOKEN="your-token"
   ./nifi-flow-import.sh -a token -t "$NIFI_TOKEN" -f flow.json -n "Flow"
   ```
3. **Use token authentication** in production environments
4. **Validate JSON files** before import to prevent malformed flows

## Version Compatibility
Tested with:
- Apache NiFi 1.x, 2.x
- Bash 4.4+
- curl 7.47+

## License & Support
This script is provided as-is for Apache NiFi flow management. For issues or enhancements, please ensure you have:
1. Valid NiFi JSON export
2. Proper network access to NiFi instance
3. Appropriate permissions for flow import

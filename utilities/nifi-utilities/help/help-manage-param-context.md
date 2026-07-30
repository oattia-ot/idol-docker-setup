# NiFi Parameter Context Manager

A comprehensive Bash script for managing Apache NiFi parameter contexts with support for create, delete, and list operations through both interactive and batch modes.

## Table of Contents
- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Authentication Methods](#authentication-methods)
- [Usage Modes](#usage-modes)
  - [Interactive Create Mode](#interactive-create-mode)
  - [JSON File Create Mode](#json-file-create-mode)
  - [List Mode](#list-mode)
  - [Delete Mode](#delete-mode)
- [Command-Line Options](#command-line-options)
- [JSON File Format](#json-file-format)
- [Examples](#examples)
- [Configuration](#configuration)
- [Error Handling](#error-handling)
- [Troubleshooting](#troubleshooting)

## Overview

The NiFi Parameter Context Manager provides a command-line interface to:
- Create parameter contexts with parameters
- Delete parameter contexts (individual, multiple, or all)
- List existing parameter contexts in various formats
- Import parameters from JSON files
- Interactive parameter entry

## Prerequisites

- **curl**: Required for API communication
- **jq**: Recommended for JSON validation and parsing (optional but highly recommended)

Install missing dependencies:
```bash
# Ubuntu/Debian
sudo apt-get install curl jq

# macOS
brew install curl jq

# CentOS/RHEL
sudo yum install curl jq
```

## Authentication Methods

The script supports three authentication methods:

1. **Password Authentication** (default)
   - Uses username/password to generate a bearer token
   - Default: `admin` / `Nifi-Admin1!`

2. **Token Authentication**
   - Uses an existing bearer token

3. **No Authentication**
   - For unsecured NiFi instances

## Usage Modes

### Interactive Create Mode
Prompts for parameters one by one:
```bash
# With positional arguments
./nifi-param-context.sh "Database Config" "DB connection parameters"

# With options
./nifi-param-context.sh --create --name "Database Config" --description "DB connection parameters"
```

### JSON File Create Mode
Loads parameters from a JSON file:
```bash
# With positional arguments
./nifi-param-context.sh "API Config" "API settings" ./params.json

# With options
./nifi-param-context.sh --create --name "API Config" --description "API settings" --file ./params.json
```

### List Mode
Display all parameter contexts:
```bash
# Table format (default)
./nifi-param-context.sh --list

# JSON format
./nifi-param-context.sh --list --output json

# CSV format
./nifi-param-context.sh --list --output csv
```

### Delete Mode
Delete parameter contexts:
```bash
# Delete specific context by ID
./nifi-param-context.sh --delete --context-id "context-id-here"

# Delete contexts from file
./nifi-param-context.sh --delete --file contexts_to_delete.txt

# Delete ALL contexts (use with caution!)
./nifi-param-context.sh --delete-all --yes
```

## Command-Line Options

| Option | Short | Description | Default |
|--------|-------|-------------|---------|
| `--help` | `-h` | Display help message | |
| `--url` | `-u` | NiFi URL | `https://idol-docker-host:8443` |
| `--auth` | `-a` | Authentication method: `password`, `token`, `none` | `password` |
| `--username` | `-U` | Username for password auth | `admin` |
| `--password` | `-P` | Password for password auth | `Nifi-Admin1!` |
| `--token` | `-t` | Bearer token for token auth | |
| `--list` | `-l` | List all parameter contexts | |
| `--output` | `-o` | Output format: `table`, `json`, `csv` | `table` |
| `--create` | `-C` | Create parameter context | |
| `--delete` | `-D` | Delete parameter context(s) | |
| `--delete-all` | | Delete ALL parameter contexts | |
| `--context-id` | | Specific context ID to delete | |
| `--name` | `-n` | Context name for create mode | |
| `--description` | `-d` | Description for create mode | |
| `--file` | `-f` | File containing contexts/parameters | |
| `--yes` | `-y` | Skip confirmation prompts | |

## JSON File Format

The JSON file must contain an array of parameter objects:

```json
[
  {
    "parameter": {
      "name": "database_url",
      "description": "Database connection URL",
      "sensitive": false,
      "value": "jdbc:postgresql://localhost:5432/mydb"
    }
  },
  {
    "parameter": {
      "name": "database_password",
      "description": "Database password",
      "sensitive": true,
      "value": "secretPassword123"
    }
  }
]
```

## Examples

### Basic Operations
```bash
# Interactive mode with default description
./nifi-param-context.sh "My Parameters"

# JSON file mode
./nifi-param-context.sh "Production Config" "Production settings" ./prod_params.json

# List contexts in table format
./nifi-param-context.sh -l

# List contexts in JSON format
./nifi-param-context.sh -l -o json
```

### Authentication Examples
```bash
# Password authentication with custom credentials
./nifi-param-context.sh -u https://nifi.example.com:8443 \
  -a password -U myuser -P mypass -l

# Token authentication
./nifi-param-context.sh -u https://nifi.example.com:8443 \
  -a token -t eyJhbGc... -D --context-id "abc123"

# No authentication
./nifi-param-context.sh -u http://localhost:8080 -a none -l
```

### Batch Operations
```bash
# Create from JSON file
./nifi-param-context.sh -C -n "Batch Config" \
  -d "Created via batch" -f ./batch_params.json -y

# Delete multiple contexts from file
./nifi-param-context.sh -D -f ./contexts_to_delete.txt

# Delete all contexts without confirmation
./nifi-param-context.sh --delete-all -y
```

### Positional Arguments (Legacy Support)
```bash
# All three positional arguments
./nifi-param-context.sh "Context Name" "Description" ./params.json

# Name and description only (interactive)
./nifi-param-context.sh "Context Name" "Description"

# Name only (interactive with default description)
./nifi-param-context.sh "Context Name"
```

## Configuration

Default connection settings (can be overridden via command-line):

| Variable | Default Value |
|----------|---------------|
| `NIFI_URL` | `https://idol-docker-host:8443` |
| `USERNAME` | `admin` |
| `PASSWORD` | `Nifi-Admin1!` |

## Error Handling

The script provides detailed error messages for common issues:

1. **Connection Errors**: Check NiFi URL and network connectivity
2. **Authentication Errors**: Verify credentials or token validity
3. **JSON Validation Errors**: Use `jq` to validate JSON files
4. **Context Not Found**: Verify context ID or name exists
5. **Duplicate Context**: Choose to cancel or create with modified name

## Troubleshooting

### Common Issues

1. **"Failed to generate token"**
   ```bash
   # Verify credentials
   ./nifi-param-context.sh -l -U admin -P Nifi-Admin1!
   
   # Check if NiFi is running
   curl -k https://idol-docker-host:8443/nifi-api/access/token
   ```

2. **"Invalid JSON response"**
   ```bash
   # Test API connectivity
   curl -k https://idol-docker-host:8443/nifi-api/flow/parameter-contexts
   
   # Check if jq is installed
   which jq
   ```

3. **"Context not found"**
   ```bash
   # List all contexts to verify names/IDs
   ./nifi-param-context.sh -l -o json | jq '.[] | .name'
   ```

### Debug Mode
For troubleshooting, you can add debug output:
```bash
# Add to script beginning
set -x

# Or run with debug
bash -x ./nifi-param-context.sh -l
```

### Security Notes
- Tokens and passwords are passed in command-line arguments (consider using environment variables for production)
- Sensitive parameter values are masked in outputs
- Use HTTPS for production environments
- Review NiFi security configuration for appropriate access controls

### Performance Tips
- For large numbers of contexts, use `--output json` or `--output csv`
- When creating many contexts, consider using batch JSON files
- The script includes progress indicators for long operations

---

**Note**: Always test operations in a non-production environment first. The `--delete-all` option is irreversible and will delete all parameter contexts without the ability to recover them.
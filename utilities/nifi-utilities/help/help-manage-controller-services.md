# NiFi Controller Services Manager

A comprehensive Bash script for managing Apache NiFi controller services across all process groups, supporting both interactive and batch operations. The script recursively searches all process groups at all nesting levels, making it ideal for complex NiFi deployments.

## Synopsis

```
./nifi-manage-controller-services.sh [OPTIONS]
```

## Description

Lists, enables, disables, or updates controller services in Apache NiFi.  
Supports both interactive selection and batch operations.

## Overview

This script provides a powerful interface for listing, enabling, disabling, and updating controller services in Apache NiFi.

## Features

- **Recursive Discovery**: Automatically discovers all controller services across all process groups
- **Multiple Output Formats**: Table (colored), JSON, and CSV output options
- **Batch Operations**: Enable, disable, or update multiple services at once
- **Flexible Filtering**: Filter services by state, name, type, or location
- **Property Management**: Update service properties while preserving existing configurations
- **Interactive Mode**: User-friendly prompts for configuration and actions
- **Authentication Support**: Password-based or token-based authentication

## Requirements

- `curl` - Required for API calls
- `jq` - Required for JSON parsing

### Installation

**Ubuntu/Debian:**
```bash
sudo apt-get install curl jq
```

**macOS:**
```bash
brew install curl jq
```

## Quick Start

```bash
# Interactive mode
./nifi-manage-controller-services.sh

# List all services
./nifi-manage-controller-services.sh --list

# Enable all disabled services
./nifi-manage-controller-services.sh --enable --filter-state DISABLED --yes
```

## Usage

```
./nifi-manage-controller-services.sh [OPTIONS]
```

## Command-Line Options

### Connection Options

| Option | Short | Description | Default |
|--------|-------|-------------|---------|
| `--url` | `-u` | NiFi URL | `https://idol-docker-host:8443` |
| `--auth` | `-a` | Authentication method: `password`, `token`, or `none` | `password` |
| `--username` | `-U` | Username for password authentication | `admin` |
| `--password` | `-P` | Password for password authentication | `Nifi-Admin1!` |
| `--token` | `-t` | Bearer token for token authentication | - |

### Listing Options

| Option | Short | Description | Default |
|--------|-------|-------------|---------|
| `--list` | `-l` | List all controller services and exit | - |
| `--output` | `-o` | Output format: `table`, `json`, or `csv` | `table` |

### Batch Operation Options

| Option | Short | Description |
|--------|-------|-------------|
| `--enable` | `-e` | Enable controller services in batch mode |
| `--disable` | `-d` | Disable controller services in batch mode |
| `--update-properties` | `-p` | Update controller service properties in batch mode |
| `--service` | `-s` | Specific service ID or number to operate on |
| `--file` | `-f` | File containing service IDs or numbers (one per line) |
| `--all` | | Apply operation to ALL controller services |
| `--yes` | `-y` | Skip confirmation prompts in batch mode |

### Property Update Options

| Option | Description |
|--------|-------------|
| `--property KEY=VALUE` | Set a specific property (can be used multiple times) |
| `--properties-file FILE` | JSON file containing properties to update |
| `--properties-json JSON` | JSON string containing properties to update |

### Filtering Options

| Option | Description |
|--------|-------------|
| `--filter-state STATE` | Filter by state: `ENABLED`, `DISABLED`, `ENABLING`, `DISABLING` |
| `--filter-name PATTERN` | Filter by name (case-insensitive regex) |
| `--filter-type PATTERN` | Filter by type (case-insensitive regex) |
| `--filter-location PATTERN` | Filter by location/path (case-insensitive regex) |

## Usage Modes

### 1. Interactive Mode

Run without arguments to enter interactive mode with guided prompts:

```bash
./nifi-manage-controller-services.sh
```

The script will prompt you for:
- NiFi URL
- Authentication method
- Credentials (if needed)
- Action to perform

### 2. List Controller Services

Display all controller services from all process groups:

```bash
# Default table format
./nifi-manage-controller-services.sh --list

# JSON output
./nifi-manage-controller-services.sh --list --output json

# CSV output for spreadsheet import
./nifi-manage-controller-services.sh --list --output csv

# List only disabled services
./nifi-manage-controller-services.sh --list --filter-state DISABLED

# List database-related services
./nifi-manage-controller-services.sh --list --filter-name 'database'
```

### 3. Batch Enable/Disable

Enable or disable services in batch mode:

```bash
# Enable all services
./nifi-manage-controller-services.sh --enable --all --yes

# Disable all services
./nifi-manage-controller-services.sh --disable --all --yes

# Enable a specific service by number
./nifi-manage-controller-services.sh --enable --service 3

# Disable services from a file
./nifi-manage-controller-services.sh --disable --file services.txt --yes

# Enable all disabled services
./nifi-manage-controller-services.sh --enable --filter-state DISABLED --yes

# Disable all services in a specific location
./nifi-manage-controller-services.sh --disable --filter-location "Production" --yes
```

### 4. Batch Update Properties

Update service properties in batch mode:

```bash
# Update a single property for a specific service
./nifi-manage-controller-services.sh --update-properties --service 3 \
  --property 'Database Connection URL=jdbc:mysql://localhost/db'
./nifi-manage-controller-services.sh -p -s 3 --property 'db.url=jdbc:mysql://localhost/db'

# Update multiple properties
./nifi-manage-controller-services.sh --update-properties --service 5 \
  --property 'Max Wait Time=500 millis' \
  --property 'Max Total Connections=50'

# Update properties from a JSON file
./nifi-manage-controller-services.sh --update-properties --file services.txt \
  --properties-file config.json --yes
./nifi-manage-controller-services.sh -p -f services.txt --properties-file props.json

# Update all DBCPConnectionPool services
./nifi-manage-controller-services.sh --update-properties \
  --filter-type 'DBCPConnectionPool' \
  --property 'Max Total Connections=100' --yes
./nifi-manage-controller-services.sh -p --all --property 'timeout=30'
```

## Filtering Examples

Filters can be combined for precise targeting:

```bash
# Find all disabled database services in production
./nifi-manage-controller-services.sh --list \
  --filter-state DISABLED \
  --filter-name 'database' \
  --filter-location 'Production'

# Enable all disabled SSL context services
./nifi-manage-controller-services.sh --enable \
  --filter-state DISABLED \
  --filter-type 'SSLContextService' --yes

# List all services with "pool" in their name
./nifi-manage-controller-services.sh --list --filter-name 'pool'
```

## Property Update Details

### Property Merging Behavior

When updating properties, the script **merges** new values with existing properties:

- Existing properties not specified in the update are **preserved**
- Properties specified in the update **overwrite** existing values
- New properties are **added** to the service configuration

### Property Update Methods

**1. Command-line properties:**
```bash
--property 'Property Name=Value'
```

**2. JSON file:**
```bash
--properties-file config.json
```

JSON file format:
```json
{
  "Database Connection URL": "jdbc:mysql://newhost/db",
  "Max Wait Time": "500 millis",
  "Max Total Connections": "100"
}
```

**3. JSON string:**
```bash
--properties-json '{"timeout":"30","retries":"3"}'
```

## Service File Format

When using `--file` to specify multiple services, create a text file with one service ID or number per line:

```text
# Comments are supported
1
3
5

# Can also use service IDs
a1b2c3d4-1234-5678-abcd-ef0123456789

# Blank lines are ignored
```

## Authentication

### Password Authentication (Default)

```bash
./nifi-manage-controller-services.sh --list \
  --username admin \
  --password MySecurePassword
```

### Token Authentication

```bash
# Generate token first
TOKEN=$(curl -k -s -X POST "https://nifi-host:8443/nifi-api/access/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=admin&password=MyPassword")

# Use token
./nifi-manage-controller-services.sh --list --token "$TOKEN"
```

### No Authentication

```bash
./nifi-manage-controller-services.sh --list --auth none
```

## Output Formats

### Table Format (Default)

Human-readable colored output with service details:

```
Available Controller Services
(From All Process Groups)

1. StandardSSLContextService ● [ENABLED]
   ├─ Type: org.apache.nifi.ssl.StandardSSLContextService
   ├─ Location: NiFi Flow > Production > Security
   └─ ID: 12345678-1234-5678-abcd-ef0123456789

Summary:
  Total Services: 15
  Enabled: 10
  Disabled: 5
```

### JSON Format

Machine-readable JSON array:

```json
[
  {
    "id": "12345678-1234-5678-abcd-ef0123456789",
    "name": "StandardSSLContextService",
    "state": "ENABLED",
    "type": "org.apache.nifi.ssl.StandardSSLContextService",
    "location": "NiFi Flow > Production > Security"
  }
]
```

### CSV Format

Spreadsheet-compatible format:

```csv
ID,Name,State,Type,Location
"12345678-1234-5678-abcd-ef0123456789","StandardSSLContextService","ENABLED","org.apache.nifi.ssl.StandardSSLContextService","NiFi Flow > Production > Security"
```

## Common Workflows

### Maintenance Window: Disable All Services

```bash
# Create backup list
./nifi-manage-controller-services.sh --list --output json > services-backup.json

# Disable all services
./nifi-manage-controller-services.sh --disable --all --yes
```

### Enable Specific Services After Maintenance

```bash
# Create file with service numbers to re-enable
echo "1" > enable-list.txt
echo "3" >> enable-list.txt
echo "7" >> enable-list.txt

# Enable services from file
./nifi-manage-controller-services.sh --enable --file enable-list.txt --yes
```

### Update Database Connection Pools

```bash
# Update all DBCP services with new connection settings
./nifi-manage-controller-services.sh --update-properties \
  --filter-type 'DBCPConnectionPool' \
  --property 'Database Connection URL=jdbc:mysql://newhost:3306/mydb' \
  --property 'Max Total Connections=50' \
  --property 'Max Wait Time=500 millis' \
  --yes
```

### Audit All Services

```bash
# Export all services to CSV for review
./nifi-manage-controller-services.sh --list --output csv > nifi-services-audit.csv

# Filter and export only enabled services
./nifi-manage-controller-services.sh --list \
  --filter-state ENABLED \
  --output json > enabled-services.json
```

## Error Handling

The script provides detailed error messages for common issues:

- **Connection failures**: Verify NiFi URL and network connectivity
- **Authentication errors**: Check credentials and permissions
- **Invalid service IDs**: Verify service exists and ID is correct
- **Property update failures**: Check property names match service configuration

## Return Codes

- `0` - Success
- `1` - Error (connection, authentication, invalid arguments, etc.)

## Tips and Best Practices

1. **Always test with `--list` first** to verify your filters before batch operations
2. **Use `--yes` flag carefully** - it skips all confirmation prompts
3. **Filter precisely** to avoid unintended changes to services
4. **Backup configurations** before bulk property updates
5. **Use service files** for repeatable operations across environments
6. **Check service dependencies** before disabling services

## Troubleshooting

### Script won't connect to NiFi

```bash
# Verify NiFi is accessible
curl -k https://your-nifi-host:8443/nifi

# Test authentication
curl -k -X POST "https://your-nifi-host:8443/nifi-api/access/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=admin&password=yourpassword"
```

### jq not found

```bash
# Install jq
sudo apt-get install jq  # Ubuntu/Debian
brew install jq          # macOS
```

### Permission denied

```bash
# Make script executable
chmod +x nifi-manage-controller-services.sh
```

## Examples by Use Case

### Development Environment Setup

```bash
# Enable all services for development
./nifi-manage-controller-services.sh --enable --all --yes
```

### Production Deployment

```bash
# List all services and review
./nifi-manage-controller-services.sh --list --output table

# Enable only production services from a curated list
./nifi-manage-controller-services.sh --enable --file prod-services.txt --yes
```

### Migration Between Environments

```bash
# Export service list from source
./nifi-manage-controller-services.sh --list --output json > source-services.json

# Review and create target list
# ... manual review ...

# Configure services in target
./nifi-manage-controller-services.sh --update-properties \
  --file target-services.txt \
  --properties-file target-config.json --yes
```

## Advanced Usage

### Scripting and Automation

```bash
#!/bin/bash
# Automated service management script

# Get disabled services count
DISABLED_COUNT=$(./nifi-manage-controller-services.sh --list \
  --filter-state DISABLED --output json | jq '. | length')

if [ "$DISABLED_COUNT" -gt 0 ]; then
  echo "Found $DISABLED_COUNT disabled services"
  # Enable them
  ./nifi-manage-controller-services.sh --enable \
    --filter-state DISABLED --yes
fi
```

### Integration with CI/CD

```bash
# In deployment pipeline
./nifi-manage-controller-services.sh --update-properties \
  --filter-name "DatabasePool" \
  --property "Database Connection URL=${DB_URL}" \
  --property "Database User=${DB_USER}" \
  --yes
```

## Configuration

Default NiFi connection settings:  
NIFI_URL = https://idol-docker-host:8443  
USERNAME = admin  
PASSWORD = Nifi-Admin1!

## Examples

```bash
# List all disabled services as JSON
./nifi-manage-controller-services.sh -l --filter-state DISABLED -o json

# Enable all disabled database-related services
./nifi-manage-controller-services.sh -e --filter-state DISABLED --filter-name 'database' -y

# Update connection pool properties for all matching services
./nifi-manage-controller-services.sh -p --filter-type 'DBCPConnectionPool' --property 'Max Total Connections=50' -y

# Disable specific services from a file
./nifi-manage-controller-services.sh -d -f disabled_services.txt -y
```
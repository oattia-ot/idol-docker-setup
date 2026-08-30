# NiFi GitHub Flow Registry Client - Master Script Edition

## 📋 Overview

The `nifi-manage-api-main.sh` script is a comprehensive command-line tool for managing Apache NiFi GitHub Flow Registries and Parameter Contexts. This enhanced version features master script styling, color formatting, and extensive functionality for automating NiFi administration tasks.

## ✨ Key Features

- **🔐 Authentication Management** - Secure connection to NiFi instances
- **📁 Registry Client Operations** - Create, list, and manage GitHub-based flow registries
- **🗂️ Flow Version Control** - Manage buckets, flows, and versions
- **⚙️ Parameter Context Management** - Create and manage parameter contexts
- **🔒 SSL Certificate Management** - Export and test SSL certificates
- **🎨 Interactive & Non-interactive Modes** - Both CLI and interactive menu interfaces
- **📊 Rich Visual Feedback** - Color-coded output with progress indicators
- **🔧 Comprehensive Error Handling** - Detailed error messages and troubleshooting

## 🚀 Quick Start

### Prerequisites

```bash
# Required dependencies
sudo apt-get install curl jq  # Debian/Ubuntu
# or
sudo yum install curl jq      # RHEL/CentOS
# or
brew install curl jq          # macOS
```

### Basic Usage

```bash
# Run in interactive mode (recommended for beginners)
./nifi-manage-api-main.sh --interactive

# Show help
./nifi-manage-api-main.sh --help

# Test connection to NiFi
./nifi-manage-api-main.sh --url https://nifi:8443/nifi-api test-connection
```

## ⚙️ Configuration

### Environment Variables

Set these in your shell or `.env` file:

```bash
# Required for authentication
export NIFI_API_URL="https://your-nifi-host:8443/nifi-api"
export NIFI_USERNAME="admin"
export NIFI_PASSWORD="your-password"

# GitHub Configuration
export GITHUB_REPO_URL="https://github.com/your-org/your-repo.git"
export GITHUB_TOKEN="ghp_your_token_here"
export GITHUB_BRANCH="main"
export GITHUB_FLOW_DIR="nifi-flows"

# SSL Settings
export SSL_VERIFY="false"  # Set to true for production
```

### Command Line Options

| Option | Description | Default |
|--------|-------------|---------|
| `-h, --help` | Show help message | - |
| `-i, --interactive` | Run in interactive mode | false |
| `-u, --url URL` | NiFi API URL | `https://idol-docker-host:8443/nifi-api` |
| `-U, --username USER` | NiFi username | `admin` |
| `-P, --password PASS` | NiFi password | `Nifi-Admin1!` |
| `--github-repo URL` | GitHub repository URL | - |
| `--github-token TOKEN` | GitHub personal access token | - |
| `--ssl-verify BOOL` | Verify SSL certificates | `false` |
| `-v, --verbose` | Enable verbose output | false |
| `-q, --quiet` | Suppress non-essential output | false |

## 📚 Detailed Usage Examples

### 1. Authentication & Connection Testing

```bash
# Test connection to NiFi
./nifi-manage-api-main.sh \
  --url https://nifi.company.com:8443/nifi-api \
  --username admin \
  --password AdminPass123! \
  test-connection

# Get NiFi version
./nifi-manage-api-main.sh get-version
```

### 2. GitHub Registry Management

```bash
# Create a GitHub flow registry
./nifi-manage-api-main.sh \
  --github-repo https://github.com/mycompany/nifi-flows.git \
  --github-token ghp_abc123def456 \
  create-registry

# List all registry clients
./nifi-manage-api-main.sh list-registries

# Get specific registry details
./nifi-manage-api-main.sh get-registry 12345678-90ab-cdef-1234-567890abcdef
```

### 3. Flow Registry Operations

```bash
# List buckets in a registry
./nifi-manage-api-main.sh list-buckets

# List flows in a specific bucket
./nifi-manage-api-main.sh list-flows \
  "registry-id-here" \
  "bucket-id-here"

# List versions of a specific flow
./nifi-manage-api-main.sh list-flow-versions \
  "registry-id" \
  "bucket-id" \
  "flow-id"
```

### 4. Version Control

```bash
# Start version control for a process group
./nifi-manage-api-main.sh start-version-control \
  "process-group-id" \
  "bucket-id" \
  "My Flow Name" \
  "Description of the flow" \
  "Initial version commit message"
```

### 5. Parameter Context Management

```bash
# List all parameter contexts
./nifi-manage-api-main.sh list-parameter-contexts

# Create a new parameter context
./nifi-manage-api-main.sh create-parameter-context \
  "Production Parameters" \
  "Parameters for production environment"

# Get parameter context details
./nifi-manage-api-main.sh get-parameter-context "context-id-here"
```

### 6. SSL Certificate Management

```bash
# Export NiFi SSL certificate
./nifi-manage-api-main.sh export-cert \
  nifi.company.com \
  8443 \
  nifi-cert.pem

# Use the exported certificate
export SSL_VERIFY=true
export CERT_PATH=./nifi-cert.pem
```

## 🎮 Interactive Mode

The interactive mode provides a user-friendly menu interface:

```bash
./nifi-manage-api-main.sh --interactive
```

### Interactive Menu Sections:

1. **Authentication & System**
   - Authenticate with NiFi
   - Test NiFi Connection
   - Get NiFi Version
   - Show Configuration

2. **Registry Client Operations**
   - List Registry Types
   - Create GitHub Registry Client
   - List All Registries
   - Get Registry Client by ID
   - Delete Registry Client

3. **Flow Registry Operations**
   - List Buckets
   - List Flows in Bucket
   - List Flow Versions
   - Start Version Control

4. **Parameter Context Operations**
   - List Parameter Contexts
   - Get Parameter Context Details
   - Create Parameter Context

5. **SSL & Certificate Management**
   - Export NiFi SSL Certificate

6. **Script Options**
   - Toggle Verbose Mode
   - Toggle Quiet Mode

## 🔧 Advanced Configuration

### Custom GitHub Configuration

```bash
# Advanced registry creation with custom settings
export GITHUB_REPO_URL="https://github.com/company/nifi-config.git"
export GITHUB_BRANCH="develop"
export GITHUB_FLOW_DIR="config/flows"
export GITHUB_TOKEN=$(cat ~/.github/token)

# The script will use:
# - Repository path: config/flows/
# - Default branch: develop
# - GitHub API: https://api.github.com
```

### SSL Configuration

```bash
# For production with SSL verification
export SSL_VERIFY="true"

# Export and use custom certificates
./nifi-manage-api-main.sh export-cert nifi-prod.company.com 8443 prod-cert.pem
export NIFI_API_URL="https://nifi-prod.company.com:8443/nifi-api"
```

## 🐛 Troubleshooting

### Common Issues

1. **Connection Failed (HTTP 000)**
   ```bash
   # Check NiFi is running
   curl -k https://nifi:8443/nifi-api/flow/about
   
   # Try without SSL verification
   export SSL_VERIFY=false
   ```

2. **Authentication Failed (HTTP 401)**
   ```bash
   # Verify credentials
   echo "Testing credentials..."
   curl -k -X POST "https://nifi:8443/nifi-api/access/token" \
     -H "Content-Type: application/x-www-form-urlencoded" \
     -d "username=admin&password=your-password"
   ```

3. **GitHub Token Issues**
   ```bash
   # Ensure token has correct permissions:
   # - repo (full control)
   # - workflow (if using GitHub Actions)
   # - read:org (if organization repository)
   ```

4. **Missing Dependencies**
   ```bash
   # Check all dependencies
   command -v curl && echo "✓ curl found" || echo "✗ curl missing"
   command -v jq && echo "✓ jq found" || echo "✗ jq missing"
   command -v openssl && echo "✓ openssl found" || echo "✗ openssl missing"
   ```

### Debug Mode

Enable verbose output for detailed debugging:

```bash
# Command line
./nifi-manage-api-main.sh --verbose --interactive

# Environment variable
export VERBOSE=true
./nifi-manage-api-main.sh --interactive
```

## 📝 Logging & Output

### Log Levels

- **INFO** (`[INFO]`) - General information (blue)
- **SUCCESS** (`[SUCCESS]`) - Successful operations (green)
- **WARNING** (`[WARNING]`) - Warnings (yellow)
- **ERROR** (`[ERROR]`) - Errors (red)
- **VERBOSE** (`[VERBOSE]`) - Detailed debug info (gray, only with `--verbose`)

### Output Formatting

The script uses color-coded output:

- **Green**: Success messages and IDs
- **Blue**: Information and section headers
- **Yellow**: Warnings and prompts
- **Red**: Errors and failures
- **Gray**: Detailed information and metadata
- **White**: Important data values

## 🔄 API Reference

### NiFi API Endpoints Used

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/access/token` | POST | Authentication |
| `/flow/about` | GET | Get NiFi version and info |
| `/controller/registry-types` | GET | List registry types |
| `/controller/registry-clients` | GET/POST | List/create registry clients |
| `/controller/registry-clients/{id}` | GET/DELETE | Get/delete specific registry |
| `/flow/registries/{id}/buckets` | GET | List buckets |
| `/flow/registries/{id}/buckets/{bucket}/flows` | GET | List flows |
| `/flow/registries/{id}/buckets/{bucket}/flows/{flow}/versions` | GET | List flow versions |
| `/versions/process-groups/{id}` | POST | Start version control |
| `/flow/parameter-contexts` | GET | List parameter contexts |
| `/parameter-contexts` | POST | Create parameter context |
| `/parameter-contexts/{id}` | GET | Get parameter context |

### GitHub Integration

The script creates a GitHub Flow Registry Client with these properties:

- **Type**: `org.apache.nifi.github.GitHubFlowRegistryClient`
- **API URL**: `https://api.github.com`
- **Authentication**: Personal Access Token
- **Repository Structure**: `{GITHUB_FLOW_DIR}/{bucket-name}/`

## 🛡️ Security Best Practices

1. **Token Management**
   - Use environment variables for sensitive data
   - Never hardcode tokens in scripts
   - Use GitHub fine-grained tokens with minimal permissions

2. **SSL/TLS**
   - Enable SSL verification in production
   - Export and trust NiFi certificates
   - Use secure cipher suites

3. **Access Control**
   - Use NiFi roles and policies
   - Implement GitHub repository access controls
   - Regular token rotation

## 📁 Project Structure

```
nifi-manage-api-main.sh
├── Configuration Section
│   ├── Color Definitions
│   ├── Default Configuration
│   └── Global Variables
├── Helper Functions
│   ├── Logging Functions
│   ├── API Call Wrapper
│   └── UI Functions
├── Authentication Module
│   ├── authenticate()
│   ├── verify_token()
│   └── get_nifi_version()
├── Registry Management
│   ├── list_registry_types()
│   ├── create_github_registry()
│   ├── list_all_registries()
│   └── get_registry_client()
├── Flow Operations
│   ├── list_buckets()
│   ├── list_flows()
│   ├── list_flow_versions()
│   └── start_version_control()
├── Parameter Context
│   ├── list_parameter_contexts()
│   ├── create_parameter_context()
│   └── get_parameter_context()
├── SSL Management
│   ├── test_connection()
│   └── export_nifi_certificate()
└── Main Execution
    ├── Interactive Mode
    ├── Command Parsing
    └── Usage Display
```

## 🔄 Updating the Script

### Adding New Features

1. **New Functions**: Add functions following existing patterns
2. **Menu Integration**: Update `show_menu()` for interactive mode
3. **Argument Parsing**: Update `parse_args()` for CLI mode
4. **Documentation**: Update this README and help text

### Version Compatibility

- **NiFi 2.x**: Fully compatible
- **GitHub API v3**: Compatible
- **GitHub API v4** (GraphQL): Not currently supported

## 📄 License & Attribution

This script is provided as-is for managing Apache NiFi instances. It includes enhancements for better user experience and comprehensive functionality.

### Dependencies

- **curl**: HTTP client for API calls
- **jq**: JSON processor for response handling
- **openssl**: SSL certificate management (optional)

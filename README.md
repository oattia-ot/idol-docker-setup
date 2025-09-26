# IDOL Setup and Installation Guide

This README documents the complete configuration and installation process for OpenText Knowledge Discovery (IDOL) deployment.

## 🚀 Features

- **Prerequisite Validation**: Automatically checks for Java, OpenSSL, Docker, and Docker Compose
- **Auto-Installation**: Installs Docker and Docker Compose if missing
- **License Management**: Configures IDOL license server with validation
- **Interactive Configuration**: Collects IDOL setup parameters including version, type, and network settings
- **Data Persistence**: Preserves data outside containers, including NiFi persistence
- **Network Intelligence**: Validates network interfaces and assists with host/guest IP selection
- **Comprehensive Logging**: Logs all operations with timestamps for troubleshooting

## 📋 Requirements

- **Operating System**: WSL Ubuntu 24.04 (Tested with 6 processors, 50 GB disk, and 64 GB memory)
- **Privileges**: Root or sudo access required
- **Network**: Internet connection for Docker installation
- **License**: IDOL license file (`licensekey.dat`) 
    - You need to provide the following info in order to generate it:
      1) Host Name
      2) Mail Address
      3) MAC Address
- **Authentication**: IDOL Docker personal access token

## Overview

The IDOL setup process involves parameter collection, environment configuration, installation, and container deployment. This guide documents the setup for a secure NiFi deployment with IDOL version 25.2 including License Server configuration.

## Prerequisites Validation

The script can optionally validate the following prerequisites:
- Java runtime environment
- OpenSSL for certificate management
- Docker engine
- Docker Compose plugin
- User permissions for Docker operations

**Note**: Prerequisites validation can be skipped during setup if requirements are already met.

## Installation Workflow

### Step 1: Parameter Collection
```bash
cd setup-idol/
./collect-setup-parameters.sh
```
- Configures network settings
- Sets up data persistence options
- Validates license and Docker access
- Optionally validates prerequisites

### Step 2: Environment Setup
```bash
source env/export-env-variables.sh
```
- Loads all configuration variables into the shell environment
- Required before running the installation script

### Step 3: IDOL Installation
```bash
./install-idol.sh
```
- Prepares IDOL installation packages
- Configures security certificates
- Sets up persistent storage volumes
- Prepares Docker Compose configurations

### Step 5: Container Deployment
```bash
cd /opt/idol/idol-containers-toolkit/basic-idol/
./deploy.sh up -d
```
- Deploys IDOL containers using Docker Compose
- Starts all services in detached mode
- Applies final configurations
- Establishes service connectivity

### Step 6: (Optional) Check if IDOL License Server is availabe if not start it:
cd idol-docker-setup/licenseserver-setup/
./deploy-license-server.sh
> **Note**
> Although the IDOL License Server is automatically deployed during setup, you can use the section 6 instructions to manually install it if necessary.

## Environment Variables

The script generates the following environment variables (sourced via `export-env-variables.sh`):

## Data Preservation Options

The script offers two data persistence strategies:

### 1. Preserve Data Outside Container (Recommended) ✅
- Data persists when containers are removed/recreated
- Enables backup and recovery procedures
- Typically selected for IDOL core components (Content and Find)

### 2. Keep Data Inside Container
- Data is lost when container is removed
- Simpler setup but higher risk of data loss
- May be selected for NiFi components based on requirements

## Log Files

All setup logs are stored in:
```
/opt/setup-idol/logs/
```

Log file naming: `collect-setup-parameters_YYYYMMDD.log`

## Post-Installation Steps

After successful deployment, verify the installation:

1. **Check Container Status**: `docker ps` to verify all containers are running
2. **License Server**: Confirm license server connectivity
3. **NiFi Access**: Access NiFi web interface at `https://${IDOL_HOST_FQDN}:${IDOL_NIFI_PORT_NUMBER}`
4. **NiFi Registry**: Access registry at `http://idol-docker-host:18080/nifi-registry`
5. **IDOL Find**: Verify IDOL Find interface is accessible
6. **Data Ingestion**: Begin ingesting content through NiFi workflows

## Security Considerations

- SSL/TLS encryption enabled for all communications
- NiFi secured with HTTPS on configured secure port
- Docker access token authentication required
- Valid license key mandatory for deployment
- Network isolation through Docker bridge networks
- Persistent data stored outside containers for security

## Troubleshooting

### Common Issues
- **License Server**: Ensure license server is running and accessible
- **Docker Authentication**: Verify Docker Personal Access Token is valid
- **Prerequisites**: Run prerequisite validation if installation fails
- **Permissions**: Check Docker group membership and file permissions
- **Network**: Verify selected IP addresses are accessible
- **Storage**: Ensure persistent storage paths exist and are writable

### Validation Commands
```bash
# Check Docker access
docker login

# Verify license file exists
ls -la ${IDOL_PRESERVE_PATH}/licensekey.dat

# Test network connectivity
ping ${IDOL_NET_HOST_IP}

# Check container status
docker ps -a

# View logs
docker-compose logs
```

## 📁 Directory Structure

```
.
├── idol-secure-setup/             # Secure IDOL setup configurations
├── idol-standard-setup/           # Standard IDOL setup configurations
├── licenseserver-setup/           # License server configuration files
├── nifi-templates/                # NiFi flow templates
├── persistent-data/               # Container data persistence directory
├── prerequisites/                 # System prerequisite checks and installers
├── utilities/                     # Helper scripts and utilities
├── logs/                          # Operation logs with timestamps
├── env/                           # Environment variable files
├── collect-setup-parameters.sh*   # Main Parameter collection script
├── install-idol.sh*               # Main IDOL installation script
└── README.md                      # Project documentation
```

---
**Note**: This script is designed specifically for Ubuntu 24.04. Using it on other distributions may require modifications.


## Conclusion

You have successfully installed OpenText™ Knowledge Discovery (IDOL) on Docker Compose. You can now start configuring IDOL.

Let me know if you need any modifications!

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/enhancement`)
3. Commit your changes (`git commit -am 'Add enhancement'`)
4. Push to the branch (`git push origin feature/enhancement`)
5. Create a Pull Request

## 📄 License

This project is for internal use and distribution under the terms specified by OpenText IDOL licensing agreements.

## 🆘 Support

For issues and questions:
1. Check the troubleshooting section above
2. Review log files in `./logs/`
3. Consult OpenText IDOL documentation
4. Contact your system administrator

---

## Acknowledgments 🙏

A heartfelt thank you to my colleague **Vinay Joseph** for guiding me through the development of this technological solution. Your unwavering support and profound insights were instrumental in transforming our challenge into a meaningful technological contribution.

**With deepest gratitude,**
Oren Attia

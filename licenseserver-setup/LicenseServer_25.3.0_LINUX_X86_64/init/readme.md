# IDOL init
Script / configuration file templates for process control of IDOL component services. Templates are provided for SystemV `init`, systemd `systemctl` and upstart `initctl` flavours of init system.

## Template Variables
The example values in the table below are for an installation of a Content component, where the executable file is at `/opt/autonomy/content/content.exe` and the configuration file is at `/opt/autonomy/content/content.cfg`. The user and group to run the process as are both `content` respectively.


|Variable|Flavours|Explanation|Example Value|
|--------|--------|-----------|-------------|
|`__COMPONENT_LD_LIBRARY_PATH__`|All|Custom LD_LIBRARY_PATH|/mylibs|
|`__COMPONENT_NAME__`|All|Name of the product|Content|
|`__COMPONENT_INSTALL_DIR__`|All|Installation directory of the component|`/opt/autonomy/content`|
|`__COMPONENT_BASENAME__`|All|Basename of all component files|content|
|`__USER__`|All|User to run the process as|`content`|
|`__GROUP__`|All|Group to run the process as|`content`|
|`__COMPONENT_ACI_PORT__`|SystemV|ACI Port of the component|5500|
|`__COMPONENT_SERVICE_PORT__`|SystemV|Service Port of the component|5502|
|`__ENVIRONMENT_FILE__`|systemd, SystemV|Absolute path to an environment file|`/home/user/environ`|

## Usage
All templates need the template variables that match your desired flavour on init system to be filled in as described in the 'Template Variables' section. 
The templates assume that the files are named according to the basename. For example, a basename of "content" implies that the executable is `content.exe` and the config file is `content.cfg`.
Some template variable assignments are commented out as they are not needed by default - if they are required, the lines should be uncommented. All instances of these are accompanied by an explanatory comment for ease of identification.
The completed template file should be renamed such that the `.template` suffix is removed and the `idol-component` portion is renamed to however you wish to refer to the service in your chosen flavour of process control.

### SystemV
Copy the completed template file to the SystemV init directory (typically `/etc/init.d`) and use as you would any other SystemV init script.
If using a bash-style environment file to set environment variables for the process, uncomment the line source'ing the environment file and fill in the `__ENVIRONMENT_FILE__` template variable.

### systemd
Copy the completed template file to the systemd init directory (typically `/etc/systemd/system`) and use as you would any other systemd service configuration file.
If using a systemd-style environment file to set environment variables for the process, uncomment the EnvironmentFile= line and fill in the `__ENVIRONMENT_FILE__` template variable.

### upstart
Copy the completed template file to the upstart init directory (typically `/etc/init`) and use as you would any other upstart job configuration file.
Set any environment variables using the upstart `env` and `export` stanzas. For example, to set the environment variables `FOO` and `HELLO` too `bar` and `world` respectively:
```
env FOO=bar
export FOO
env HELLO=world
export HELLO
```

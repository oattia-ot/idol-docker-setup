# IDOL Monitoring Stack Manager

This Bash script manages the IDOL Monitoring Stack, which includes various Docker-based services for container management, monitoring, logging, and metrics visualization. It uses a Docker Compose file (`docker-compose.monitoring.yml`) to control the services.

## Usage

```
./monitor.sh [command] [service]
```

- **[command]**: One of the available commands (required).
- **[service]**: The target service name or `all` (optional; defaults to `all` if not specified for most commands).

If no arguments are provided, the script displays the help message.

## Commands

- **start [service]**: Start a specific service or all services. Pulls and starts containers in detached mode.  
  *Example*: `./monitor.sh start grafana` (starts only Grafana)

- **stop [service]**: Stop a specific service or all services. For individual services, also removes the stopped container.  
  *Example*: `./monitor.sh stop all` (stops all services)

- **restart [service]**: Restart a specific service or all services.  
  *Example*: `./monitor.sh restart prometheus` (restarts Prometheus)

- **status [service]**: Show the status of a specific service or all services. Displays service name, status (RUNNING, STOPPED, or NOT CREATED), port, and description.  
  *Example*: `./monitor.sh status all` (shows status of all services)

- **logs [service]**: Show real-time logs for a specific service or all services (use Ctrl+C to exit).  
  *Example*: `./monitor.sh logs dozzle` (shows Dozzle logs)

- **enable [service]**: Enable and start a specific service or all services (equivalent to `start`).  
  *Example*: `./monitor.sh enable yacht` (enables and starts Yacht)

- **disable [service]**: Disable a specific service or all services. Stops and removes containers; for `all`, also removes volumes.  
  *Example*: `./monitor.sh disable loki` (disables Loki)

- **urls**: Show URLs for all services, including their status, ports, and descriptions. (No [service] argument needed.)  
  *Example*: `./monitor.sh urls` (shows all service URLs)

- **help**: Show the help message (this documentation).  
  *Example*: `./monitor.sh help` (displays help)

## Services

Services are sorted by port number. Each service runs in a Docker container prefixed with `idol-` (e.g., `idol-grafana`).

| Service        | Description                      | Port  |
|----------------|----------------------------------|-------|
| yacht         | Container Management UI          | 5001 |
| dockge        | Docker Compose Stack Manager     | 5002 |
| dozzle        | Real-time Log Viewer             | 5003 |
| cadvisor      | Container Metrics Collector      | 5004 |
| prometheus    | Metrics Collection & Storage     | 5005 |
| grafana       | Metrics Visualization Dashboard  | 5006 |
| loki          | Log Aggregation System           | 5007 |
| promtail      | Log Shipper for Loki             | 5008 |
| dokemon       | Simple Docker Monitor            | 5009 |
| node-exporter | System Metrics Exporter          | 5010 |
| monitor-ui    | Config Monitor UI (Flask)        | 5011 |
| all           | All services                     | N/A  |

- **Access URLs**: Services are accessible at `http://localhost:<port>`.
- **Default Credentials**: For most services, use `admin / opentext1!`. For Yacht, use `admin@idol.local / opentext1!`.

## Notes

- The script requires Docker and Docker Compose to be installed.
- It checks for the presence of `docker-compose.monitoring.yml` before most operations.
- Colors are used in terminal output for better readability (e.g., green for success, red for errors).
- For `disable all`, volumes are removed to fully clean up.
- Service status is determined by checking running and existing containers via `docker ps`.
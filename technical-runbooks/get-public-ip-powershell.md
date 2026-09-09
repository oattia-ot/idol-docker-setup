# Get-PublicIP.ps1

> A simple PowerShell script to retrieve and display your **public IP address** along with location and ISP details.

---

## 📋 Overview

This script makes two HTTP requests to free public APIs to fetch:
- Your **public IP address**
- Your **geographic location** (city, region, country)
- Your **ISP / organization**

---

## 📄 Full Script

```powershell
# Get-PublicIP.ps1
# Get your public IP address

try {
    $ip = Invoke-RestMethod -Uri 'https://api.ipify.org' -Method Get -TimeoutSec 10
    Write-Host "Your Public IP Address: " -NoNewline -ForegroundColor Cyan
    Write-Host $ip -ForegroundColor Green

    # Optional: Get more details
    $details = Invoke-RestMethod -Uri 'https://ipinfo.io/json' -Method Get -TimeoutSec 10
    Write-Host "Location          : $($details.city), $($details.region), $($details.country)" -ForegroundColor Gray
    Write-Host "ISP               : $($details.org)" -ForegroundColor Gray
}
catch {
    Write-Host "Failed to retrieve IP address. Please check your internet connection." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
}
```

---

## 🔍 Line-by-Line Explanation

### Error Handling Block — `try { ... } catch { ... }`

The entire logic is wrapped in a `try/catch` block. If anything goes wrong (no internet, API timeout, etc.), execution jumps to the `catch` block and prints a friendly error instead of crashing.

---

### Step 1 — Fetch the Public IP

```powershell
$ip = Invoke-RestMethod -Uri 'https://api.ipify.org' -Method Get -TimeoutSec 10
```

| Part | Explanation |
|------|-------------|
| `Invoke-RestMethod` | PowerShell cmdlet that sends an HTTP request and parses the response |
| `-Uri 'https://api.ipify.org'` | A free API that returns your public IP as plain text (e.g. `203.0.113.42`) |
| `-Method Get` | Uses the HTTP GET method |
| `-TimeoutSec 10` | Aborts the request if the server doesn't respond within 10 seconds |
| `$ip` | Stores the returned IP address string |

---

### Step 2 — Display the IP Address

```powershell
Write-Host "Your Public IP Address: " -NoNewline -ForegroundColor Cyan
Write-Host $ip -ForegroundColor Green
```

| Part | Explanation |
|------|-------------|
| `Write-Host` | Prints text to the console |
| `-NoNewline` | Keeps the cursor on the same line so the IP prints right after the label |
| `-ForegroundColor Cyan` | Colors the label text cyan |
| `-ForegroundColor Green` | Colors the IP address green for easy reading |

---

### Step 3 — Fetch Extended Details

```powershell
$details = Invoke-RestMethod -Uri 'https://ipinfo.io/json' -Method Get -TimeoutSec 10
```

| Part | Explanation |
|------|-------------|
| `https://ipinfo.io/json` | A free API that returns a JSON object containing IP metadata |
| `$details` | Stores the parsed JSON response as a PowerShell object |

The JSON response from `ipinfo.io` looks like this:

```json
{
  "ip": "203.0.113.42",
  "city": "Jerusalem",
  "region": "Jerusalem",
  "country": "IL",
  "org": "AS12345 Example ISP Ltd"
}
```

---

### Step 4 — Display Location and ISP

```powershell
Write-Host "Location : $($details.city), $($details.region), $($details.country)" -ForegroundColor Gray
Write-Host "ISP      : $($details.org)" -ForegroundColor Gray
```

| Part | Explanation |
|------|-------------|
| `$($details.city)` | Accesses the `city` property of the `$details` object using subexpression syntax `$()` |
| `$($details.region)` | The state or region |
| `$($details.country)` | Two-letter country code (e.g. `IL`, `US`) |
| `$($details.org)` | The ISP or organization that owns the IP block |
| `-ForegroundColor Gray` | Displayed in gray to visually separate from the main IP |

---

### Step 5 — Error Handler

```powershell
catch {
    Write-Host "Failed to retrieve IP address. Please check your internet connection." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
}
```

| Part | Explanation |
|------|-------------|
| `catch { }` | Runs only if the `try` block throws an error |
| `$_` | The automatic variable representing the current error object |
| `$_.Exception.Message` | Extracts the technical error message for debugging |
| `-ForegroundColor Red` | Highlights errors in red |

---

## 🖥️ Example Output

```
Your Public IP Address: 203.0.113.42
Location          : Jerusalem, Jerusalem, IL
ISP               : AS12345 Example ISP Ltd
```

---

## ▶️ How to Run

1. Save the script as `Get-PublicIP.ps1`
2. Open **PowerShell** (or Windows Terminal)
3. Run:

```powershell
.\Get-PublicIP.ps1
```

> **Note:** If you get an execution policy error, run this first:
> ```powershell
> Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
> ```

---

## 🌐 APIs Used

| API | URL | Returns |
|-----|-----|---------|
| ipify | `https://api.ipify.org` | Plain-text public IP |
| ipinfo.io | `https://ipinfo.io/json` | JSON with IP, location, ISP |

Both APIs are **free** and require **no API key** for basic usage.

---

## ⚠️ Notes

- Results depend on your **current network connection** (VPN, proxy, etc. will affect the reported IP).
- `ipinfo.io` free tier allows up to **50,000 requests/month**.
- The `-TimeoutSec 10` parameter prevents the script from hanging indefinitely on slow connections.
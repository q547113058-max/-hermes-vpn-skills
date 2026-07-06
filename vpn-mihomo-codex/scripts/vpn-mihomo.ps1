# Public template. Replace the placeholder subscription URL in a private local copy only. Do not commit real tokens.
param(
  [Parameter(Position = 0)]
  [ValidateSet("start", "start-global", "stop", "status", "test", "check", "prefer")]
  [string]$Action = "status"
)

$ErrorActionPreference = "Stop"

$SubscriptionUrl = "https://example.invalid/api/subscribe?token=<token>&flag=1"
$RuntimeDir = "D:\create-video\.tools\mihomo-runtime"
$ProxyPort = 17890
$ControllerPort = 19090
$Secret = "set-your-secret"
$PreferredProxyName = "美国 a 顶级路线 负载均衡 x2"
$WingetMihomo = "C:\Users\54711\AppData\Local\Microsoft\WinGet\Packages\MetaCubeX.Mihomo_Microsoft.Winget.Source_8wekyb3d8bbwe\mihomo-windows-amd64.exe"

function Find-Mihomo {
  if (Test-Path $WingetMihomo) {
    return $WingetMihomo
  }

  $cmd = Get-Command mihomo -ErrorAction SilentlyContinue
  if ($cmd) {
    return $cmd.Source
  }

  $found = Get-ChildItem -Path "$env:LOCALAPPDATA\Microsoft\WinGet\Packages", "C:\Program Files", "D:\Program Files" `
    -Recurse -Filter "mihomo*.exe" -ErrorAction SilentlyContinue |
    Select-Object -First 1
  if ($found) {
    return $found.FullName
  }

  throw "Mihomo executable not found. Install MetaCubeX.Mihomo first."
}

function ConvertFrom-Base64Loose([string]$Text) {
  $clean = ($Text.Trim() -replace "\s", "")
  $pad = (4 - ($clean.Length % 4)) % 4
  if ($pad -gt 0) {
    $clean = $clean + ("=" * $pad)
  }
  return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($clean))
}

function ConvertFrom-QueryString([string]$Query) {
  $result = @{}
  foreach ($part in ($Query.TrimStart("?") -split "&")) {
    if (-not $part) { continue }
    $kv = $part -split "=", 2
    $key = [Uri]::UnescapeDataString($kv[0])
    $value = if ($kv.Count -gt 1) { [Uri]::UnescapeDataString($kv[1]) } else { "" }
    $result[$key] = $value
  }
  return $result
}

function ConvertTo-YamlScalar([object]$Value) {
  if ($null -eq $Value) { return "''" }
  $text = [string]$Value
  return "'" + ($text -replace "'", "''") + "'"
}

function Add-YamlLine([System.Text.StringBuilder]$Builder, [int]$Indent, [string]$Line) {
  [void]$Builder.AppendLine((" " * $Indent) + $Line)
}

function ConvertTo-MihomoYaml([string]$SubscriptionContent) {
  $decoded = ConvertFrom-Base64Loose $SubscriptionContent
  $nodes = @()
  foreach ($line in ($decoded -split "`r?`n")) {
    $entry = $line.Trim()
    if (-not $entry -or $entry -notmatch "^[a-zA-Z0-9+.-]+://") { continue }

    try {
      if ($entry.StartsWith("vmess://")) {
        $json = ConvertFrom-Base64Loose $entry.Substring(8)
        $node = $json | ConvertFrom-Json
        $server = [string]$node.add
        if (-not $server -or $server -eq "127.0.0.1" -or $server.Contains(":") -or $node.type -eq "info") { continue }

        $network = [string]$node.net
        if ($network -eq "tcp" -and [string]$node.type -eq "http") {
          $network = "http"
        }

        $nodes += [ordered]@{
          type = "vmess"
          name = if ($node.ps) { [string]$node.ps } else { "vmess-$($nodes.Count + 1)" }
          server = $server
          port = [int]$node.port
          uuid = [string]$node.id
          alterId = if ($node.aid) { [int]$node.aid } else { 0 }
          cipher = if ($node.scy) { [string]$node.scy } else { "auto" }
          tls = ([string]$node.tls -eq "tls")
          network = $network
          servername = if ($node.sni) { [string]$node.sni } elseif ($node.host) { [string]$node.host } else { "" }
          host = [string]$node.host
          path = if ($node.path) { [string]$node.path } else { "/" }
        }
      } elseif ($entry.StartsWith("vless://")) {
        $uri = [Uri]$entry
        $query = ConvertFrom-QueryString $uri.Query
        $uuid = $uri.UserInfo
        $server = $uri.Host
        if (-not $server -or $server -eq "127.0.0.1" -or $server.Contains(":")) { continue }

        $name = [Uri]::UnescapeDataString($uri.Fragment)
        if (-not $name) { $name = "vless-$($nodes.Count + 1)" }
        $network = if ($query["type"]) { $query["type"] } else { "tcp" }
        if ($network -eq "tcp" -and $query["headerType"] -eq "http") {
          $network = "http"
        }

        $nodes += [ordered]@{
          type = "vless"
          name = $name
          server = $server
          port = [int]$uri.Port
          uuid = $uuid
          tls = ($query["security"] -eq "tls")
          network = $network
          servername = if ($query["sni"]) { $query["sni"] } elseif ($query["host"]) { $query["host"] } else { "" }
          host = if ($query["host"]) { $query["host"] } else { "" }
          path = if ($query["path"]) { $query["path"] } else { "/" }
          flow = if ($query["flow"]) { $query["flow"] } else { "" }
        }
      }
    } catch {
      continue
    }
  }

  if (-not $nodes.Count) {
    throw "Subscription decoded but no usable vmess/vless nodes were found."
  }

  $builder = [System.Text.StringBuilder]::new()
  Add-YamlLine $builder 0 "mixed-port: $ProxyPort"
  Add-YamlLine $builder 0 "port: 0"
  Add-YamlLine $builder 0 "socks-port: 0"
  Add-YamlLine $builder 0 "allow-lan: false"
  Add-YamlLine $builder 0 "mode: rule"
  Add-YamlLine $builder 0 "log-level: warning"
  Add-YamlLine $builder 0 "external-controller: 127.0.0.1:$ControllerPort"
  Add-YamlLine $builder 0 "secret: $(ConvertTo-YamlScalar $Secret)"
  Add-YamlLine $builder 0 "proxies:"

  foreach ($node in $nodes) {
    Add-YamlLine $builder 2 "- name: $(ConvertTo-YamlScalar $node.name)"
    Add-YamlLine $builder 4 "type: $($node.type)"
    Add-YamlLine $builder 4 "server: $(ConvertTo-YamlScalar $node.server)"
    Add-YamlLine $builder 4 "port: $($node.port)"
    Add-YamlLine $builder 4 "uuid: $(ConvertTo-YamlScalar $node.uuid)"
    if ($node.type -eq "vmess") {
      Add-YamlLine $builder 4 "alterId: $($node.alterId)"
      Add-YamlLine $builder 4 "cipher: $(ConvertTo-YamlScalar $node.cipher)"
    }
    if ($node.type -eq "vless" -and $node.flow) {
      Add-YamlLine $builder 4 "flow: $(ConvertTo-YamlScalar $node.flow)"
    }
    Add-YamlLine $builder 4 "udp: true"
    Add-YamlLine $builder 4 "tls: $($node.tls.ToString().ToLowerInvariant())"
    if ($node.servername) {
      Add-YamlLine $builder 4 "servername: $(ConvertTo-YamlScalar $node.servername)"
    }
    if ($node.network -and $node.network -ne "tcp") {
      Add-YamlLine $builder 4 "network: $($node.network)"
      if ($node.network -eq "ws") {
        Add-YamlLine $builder 4 "ws-opts:"
        Add-YamlLine $builder 6 "path: $(ConvertTo-YamlScalar $node.path)"
        if ($node.host) {
          Add-YamlLine $builder 6 "headers:"
          Add-YamlLine $builder 8 "Host: $(ConvertTo-YamlScalar $node.host)"
        }
      } elseif ($node.network -eq "http") {
        Add-YamlLine $builder 4 "http-opts:"
        Add-YamlLine $builder 6 "method: GET"
        Add-YamlLine $builder 6 "path:"
        Add-YamlLine $builder 8 "- $(ConvertTo-YamlScalar $node.path)"
        if ($node.host) {
          Add-YamlLine $builder 6 "headers:"
          Add-YamlLine $builder 8 "Host:"
          Add-YamlLine $builder 10 "- $(ConvertTo-YamlScalar $node.host)"
        }
      } elseif ($node.network -eq "grpc") {
        Add-YamlLine $builder 4 "grpc-opts:"
        Add-YamlLine $builder 6 "grpc-service-name: $(ConvertTo-YamlScalar $node.path.TrimStart('/'))"
      }
    }
  }

  Add-YamlLine $builder 0 "proxy-groups:"
  Add-YamlLine $builder 2 "- name: PROXY"
  Add-YamlLine $builder 4 "type: select"
  Add-YamlLine $builder 4 "proxies:"
  if ($nodes | Where-Object { $_.name -eq $PreferredProxyName } | Select-Object -First 1) {
    Add-YamlLine $builder 6 "- $(ConvertTo-YamlScalar $PreferredProxyName)"
  }
  Add-YamlLine $builder 6 "- AUTO"
  foreach ($node in $nodes) {
    if ($node.name -eq $PreferredProxyName) { continue }
    Add-YamlLine $builder 6 "- $(ConvertTo-YamlScalar $node.name)"
  }
  Add-YamlLine $builder 2 "- name: AUTO"
  Add-YamlLine $builder 4 "type: url-test"
  Add-YamlLine $builder 4 "url: https://www.gstatic.com/generate_204"
  Add-YamlLine $builder 4 "interval: 300"
  Add-YamlLine $builder 4 "proxies:"
  foreach ($node in $nodes) {
    Add-YamlLine $builder 6 "- $(ConvertTo-YamlScalar $node.name)"
  }
  Add-YamlLine $builder 0 "rules:"
  Add-YamlLine $builder 2 "- MATCH,PROXY"

  [pscustomobject]@{
    Yaml = $builder.ToString()
    NodeCount = $nodes.Count
    ProtocolCounts = ($nodes | Group-Object { $_["type"] } | ForEach-Object { [pscustomobject]@{ Type = $_.Name; Count = $_.Count } })
  }
}

function Get-SubscriptionConfig {
  $content = (Invoke-WebRequest -Uri $SubscriptionUrl -UseBasicParsing -Headers @{ "User-Agent" = "clash-verge/v2.5.1" } -TimeoutSec 60).Content
  if ($content -match "(?m)^\s*proxies\s*:" -and $content -match "(?m)^\s*proxy-groups\s*:") {
    $cfg = $content
    if ($cfg -match "mixed-port:") {
      $cfg = $cfg -replace "(?m)^mixed-port:\s*\d+", "mixed-port: $ProxyPort"
    } else {
      $cfg = "mixed-port: $ProxyPort`n" + $cfg
    }
    $cfg = $cfg -replace "(?m)^port:\s*\d+", "port: 0"
    $cfg = $cfg -replace "(?m)^socks-port:\s*\d+", "socks-port: 0"
    if ($cfg -match "external-controller:") {
      $cfg = $cfg -replace "(?m)^external-controller:\s*.*", "external-controller: 127.0.0.1:$ControllerPort"
    } else {
      $cfg = "external-controller: 127.0.0.1:$ControllerPort`n" + $cfg
    }
    if ($cfg -match "secret:") {
      $cfg = $cfg -replace "(?m)^secret:\s*.*", "secret: $Secret"
    } else {
      $cfg = "secret: $Secret`n" + $cfg
    }
    return [pscustomobject]@{ Yaml = $cfg; NodeCount = $null; ProtocolCounts = @(); Format = "clash-yaml" }
  }

  $converted = ConvertTo-MihomoYaml $content
  $converted | Add-Member -NotePropertyName Format -NotePropertyValue "base64-v2ray" -Force
  return $converted
}

function Test-MihomoConfig([string]$Mihomo, [string]$ConfigPath) {
  $output = & $Mihomo -t -d $RuntimeDir -f $ConfigPath 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw "Mihomo config test failed: $($output -join '; ')"
  }
}

function Stop-MihomoRuntime {
  $escaped = [regex]::Escape($RuntimeDir)
  Get-CimInstance Win32_Process |
    Where-Object { $_.Name -like "mihomo*.exe" -and $_.CommandLine -match $escaped } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
}

function Set-SystemProxy([bool]$Enabled) {
  $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
  if ($Enabled) {
    Set-ItemProperty -Path $path -Name ProxyEnable -Value 1
    Set-ItemProperty -Path $path -Name ProxyServer -Value "127.0.0.1:$ProxyPort"
  } else {
    Set-ItemProperty -Path $path -Name ProxyEnable -Value 0
  }

  $sig = '[DllImport("wininet.dll", SetLastError=true)] public static extern bool InternetSetOption(IntPtr hInternet, int dwOption, IntPtr lpBuffer, int dwBufferLength);'
  Add-Type -MemberDefinition $sig -Name WinINet -Namespace Native -ErrorAction SilentlyContinue
  [Native.WinINet]::InternetSetOption([IntPtr]::Zero, 39, [IntPtr]::Zero, 0) | Out-Null
  [Native.WinINet]::InternetSetOption([IntPtr]::Zero, 37, [IntPtr]::Zero, 0) | Out-Null
}

function Disable-LocalSystemProxy {
  $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
  $proxy = Get-ItemProperty -Path $path | Select-Object ProxyEnable, ProxyServer
  if ([bool]$proxy.ProxyEnable -and $proxy.ProxyServer -eq "127.0.0.1:$ProxyPort") {
    Set-SystemProxy $false
  }
}

function Get-Status {
  $ports = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
    Where-Object { $_.LocalPort -in @($ProxyPort, $ControllerPort) } |
    Select-Object LocalAddress, LocalPort, OwningProcess

  $proxy = Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" |
    Select-Object ProxyEnable, ProxyServer

  [pscustomobject]@{
    ProxyPortListening = [bool]($ports | Where-Object { $_.LocalPort -eq $ProxyPort })
    ControllerListening = [bool]($ports | Where-Object { $_.LocalPort -eq $ControllerPort })
    SystemProxyEnabled = [bool]$proxy.ProxyEnable
    SystemProxyServer = $proxy.ProxyServer
  }
}

function Start-MihomoRuntime([bool]$EnableSystemProxy = $false) {
  $mihomo = Find-Mihomo
  New-Item -ItemType Directory -Force -Path $RuntimeDir | Out-Null
  Stop-MihomoRuntime

  $subscription = Get-SubscriptionConfig
  $configPath = Join-Path $RuntimeDir "config.yaml"
  Set-Content -Encoding utf8 -LiteralPath $configPath -Value $subscription.Yaml
  Test-MihomoConfig $mihomo $configPath

  $mmdbCandidates = @(
    "C:\Users\54711\AppData\Roaming\io.github.clash-verge-rev.clash-verge-rev\Country.mmdb",
    "C:\Users\54711\AppData\Roaming\com.follow\clash\GEOIP.metadb"
  )
  foreach ($candidate in $mmdbCandidates) {
    if (Test-Path $candidate) {
      Copy-Item -LiteralPath $candidate -Destination (Join-Path $RuntimeDir "Country.mmdb") -Force
      break
    }
  }

  Start-Process -FilePath $mihomo `
    -ArgumentList @("-d", $RuntimeDir, "-f", $configPath) `
    -RedirectStandardOutput (Join-Path $RuntimeDir "out.log") `
    -RedirectStandardError (Join-Path $RuntimeDir "err.log") `
    -WindowStyle Hidden

  $ready = $false
  foreach ($i in 1..12) {
    Start-Sleep -Milliseconds 500
    $status = Get-Status
    if ($status.ProxyPortListening -and $status.ControllerListening) {
      $ready = $true
      break
    }
  }
  if (-not $ready) {
    Stop-MihomoRuntime
    throw "Mihomo did not start listening on $ProxyPort and $ControllerPort. System proxy was not enabled."
  }

  if ($EnableSystemProxy) {
    Set-SystemProxy $true
  } else {
    Disable-LocalSystemProxy
  }
  Get-Status
}

function Check-Subscription {
  $mihomo = Find-Mihomo
  New-Item -ItemType Directory -Force -Path $RuntimeDir | Out-Null
  $subscription = Get-SubscriptionConfig
  $configPath = Join-Path $RuntimeDir "check-config.yaml"
  Set-Content -Encoding utf8 -LiteralPath $configPath -Value $subscription.Yaml
  Test-MihomoConfig $mihomo $configPath
  $status = Get-Status

  [pscustomobject]@{
    Fetch = "OK"
    Format = $subscription.Format
    NodeCount = $subscription.NodeCount
    Protocols = ($subscription.ProtocolCounts | ForEach-Object { "$($_.Type)=$($_.Count)" }) -join ", "
    MihomoConfigTest = "PASS"
    SystemProxyEnabled = $status.SystemProxyEnabled
    PortsListening = ($status.ProxyPortListening -or $status.ControllerListening)
  }
}

function Test-Mihomo {
  $status = Get-Status
  if (-not $status.ControllerListening) {
    throw "Mihomo controller is not listening. Run start first."
  }

  $google = try {
    (Invoke-WebRequest -Uri "https://www.google.com/generate_204" -Proxy "http://127.0.0.1:$ProxyPort" -UseBasicParsing -TimeoutSec 20).StatusCode
  } catch {
    "ERR: $($_.Exception.Message)"
  }

  $headers = @{ Authorization = "Bearer $Secret" }
  $base = "http://127.0.0.1:$ControllerPort"
  $group = [Uri]::EscapeDataString("鈾伙笍 鑷姩閫夋嫨")
  $delay = try {
    $json = (Invoke-WebRequest -Uri "$base/group/$group/delay?timeout=8000&url=https%3A%2F%2Fwww.gstatic.com%2Fgenerate_204" -Headers $headers -UseBasicParsing -TimeoutSec 20).Content | ConvertFrom-Json
    $json.PSObject.Properties |
      Sort-Object Value |
      Select-Object -First 8 |
      ForEach-Object { [pscustomobject]@{ Node = $_.Name; DelayMs = $_.Value } }
  } catch {
    @([pscustomobject]@{ Node = "delay-test-error"; DelayMs = $_.Exception.Message })
  }

  [pscustomobject]@{
    Proxy = "127.0.0.1:$ProxyPort"
    GoogleGenerate204 = $google
    FastNodes = $delay
  }
}

function Set-PreferredProxy {
  $status = Get-Status
  if (-not $status.ControllerListening) {
    throw "Mihomo controller is not listening. Run start first."
  }

  $headers = @{ Authorization = "Bearer $Secret" }
  $base = "http://127.0.0.1:$ControllerPort"
  $json = @{ name = $PreferredProxyName } | ConvertTo-Json -Compress
  $body = [Text.Encoding]::UTF8.GetBytes($json)
  Invoke-RestMethod -Uri "$base/proxies/PROXY" -Method Put -Headers $headers -ContentType "application/json; charset=utf-8" -Body $body | Out-Null
  $proxy = Invoke-RestMethod -Uri "$base/proxies/PROXY" -Headers $headers

  [pscustomobject]@{
    Group = "PROXY"
    PreferredProxy = $PreferredProxyName
    Current = $proxy.now
  }
}

switch ($Action) {
  "start" { Start-MihomoRuntime }
  "start-global" { Start-MihomoRuntime -EnableSystemProxy $true }
  "stop" {
    Stop-MihomoRuntime
    Disable-LocalSystemProxy
    Get-Status
  }
  "status" { Get-Status }
  "test" { Test-Mihomo }
  "check" { Check-Subscription }
  "prefer" { Set-PreferredProxy }
}


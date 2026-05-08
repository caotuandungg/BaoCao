param(
  [string]$SchemaPath = "$PSScriptRoot\..\schema\log-schema-v1.schema.json",
  [string[]]$LogPath
)

$ErrorActionPreference = "Stop"

function Read-JsonFile {
  param([string]$Path)

  if (-not (Test-Path -LiteralPath $Path)) {
    throw "File not found: $Path"
  }

  return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Has-Property {
  param(
    [object]$Object,
    [string]$Name
  )

  return $null -ne $Object.PSObject.Properties[$Name]
}

function Add-Error {
  param(
    [System.Collections.Generic.List[string]]$Errors,
    [string]$Message
  )

  [void]$Errors.Add($Message)
}

function Test-StandardLog {
  param(
    [object]$Record,
    [object]$Schema
  )

  $errors = [System.Collections.Generic.List[string]]::new()

  foreach ($field in $Schema.required) {
    if (-not (Has-Property $Record $field)) {
      Add-Error $errors "Missing required field '$field'"
    }
  }

  if (Has-Property $Record "@timestamp") {
    $timestamp = $Record.PSObject.Properties["@timestamp"].Value
    $parsed = [datetime]::MinValue
    if (-not [datetime]::TryParse($timestamp, [ref]$parsed)) {
      Add-Error $errors "Field '@timestamp' must be ISO date-time"
    }
  }

  if (Has-Property $Record "environment") {
    $allowed = @("dev", "test", "staging", "prod", "lab")
    if ($Record.environment -notin $allowed) {
      Add-Error $errors "Field 'environment' must be one of: $($allowed -join ', ')"
    }
  }

  if (Has-Property $Record "level") {
    $allowed = @("DEBUG", "INFO", "WARN", "ERROR", "FATAL")
    if ($Record.level -notin $allowed) {
      Add-Error $errors "Field 'level' must be one of: $($allowed -join ', ')"
    }
  }

  foreach ($field in @("service", "message")) {
    if ((Has-Property $Record $field) -and [string]::IsNullOrWhiteSpace($Record.$field)) {
      Add-Error $errors "Field '$field' must not be empty"
    }
  }

  if (Has-Property $Record "log_scope") {
    $allowed = @("internal", "external")
    if ($Record.log_scope -notin $allowed) {
      Add-Error $errors "Field 'log_scope' must be one of: $($allowed -join ', ')"
    }
  }

  if (Has-Property $Record "log_schema") {
    if (-not (Has-Property $Record.log_schema "name")) {
      Add-Error $errors "Missing required field 'log_schema.name'"
    } elseif ($Record.log_schema.name -ne "dung-standard-log") {
      Add-Error $errors "Field 'log_schema.name' must be 'dung-standard-log'"
    }

    if (-not (Has-Property $Record.log_schema "version")) {
      Add-Error $errors "Missing required field 'log_schema.version'"
    } elseif ($Record.log_schema.version -ne "1.0") {
      Add-Error $errors "Field 'log_schema.version' must be '1.0'"
    }
  }

  if (Has-Property $Record "pipeline") {
    if (-not (Has-Property $Record.pipeline "stage")) {
      Add-Error $errors "Missing required field 'pipeline.stage'"
    } else {
      $allowed = @("raw", "parsed", "normalized", "enriched", "indexed")
      if ($Record.pipeline.stage -notin $allowed) {
        Add-Error $errors "Field 'pipeline.stage' must be one of: $($allowed -join ', ')"
      }
    }

    if (-not (Has-Property $Record.pipeline "normalized")) {
      Add-Error $errors "Missing required field 'pipeline.normalized'"
    } elseif ($Record.pipeline.normalized -isnot [bool]) {
      Add-Error $errors "Field 'pipeline.normalized' must be boolean"
    }
  }

  return $errors
}

$schema = Read-JsonFile $SchemaPath
$failed = 0

if (-not $LogPath -or $LogPath.Count -eq 0) {
  $cases = @(
    @{
      Path = "$PSScriptRoot\..\schema\sample-valid-log.json"
      ShouldPass = $true
    },
    @{
      Path = "$PSScriptRoot\..\schema\sample-invalid-log.json"
      ShouldPass = $false
    }
  )
} else {
  $cases = @()
  foreach ($path in $LogPath) {
    $cases += @{
      Path = $path
      ShouldPass = $true
    }
  }
}

foreach ($case in $cases) {
  $path = $case.Path
  $record = Read-JsonFile $path
  $errors = Test-StandardLog -Record $record -Schema $schema
  $passedValidation = $errors.Count -eq 0

  if ($passedValidation -and $case.ShouldPass) {
    Write-Host "[PASS] $path"
  } elseif ((-not $passedValidation) -and (-not $case.ShouldPass)) {
    Write-Host "[PASS] $path failed as expected"
    foreach ($errorItem in $errors) {
      Write-Host "  - $errorItem"
    }
  } elseif ($passedValidation -and (-not $case.ShouldPass)) {
    $failed++
    Write-Host "[FAIL] $path should have failed validation"
  } else {
    $failed++
    Write-Host "[FAIL] $path should have passed validation"
    foreach ($errorItem in $errors) {
      Write-Host "  - $errorItem"
    }
  }
}

if ($failed -gt 0) {
  exit 1
}

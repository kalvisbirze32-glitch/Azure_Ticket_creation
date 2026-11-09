param(
    [Parameter(Mandatory)][string]$Title,
    [Parameter(Mandatory)][string]$MarkdownFile,
    [string]$Type,
    [int]$ParentId,
    [string]$EnvFile = (Join-Path $PSScriptRoot '.env')
)

$ErrorActionPreference = 'Stop'

$cfg = @{}
Get-Content -LiteralPath $EnvFile -Encoding UTF8 | ForEach-Object {
    if ($_ -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$') {
        $cfg[$Matches[1]] = $Matches[2].Trim('"').Trim("'")
    }
}

foreach ($k in 'ADO_ORG_URL', 'ADO_PROJECT', 'ADO_PAT') {
    if (-not $cfg[$k]) { throw "Missing $k in $EnvFile" }
}
$type = if ($Type) { $Type } elseif ($cfg['ADO_WORK_ITEM_TYPE']) { $cfg['ADO_WORK_ITEM_TYPE'] } else { 'Task' }

$body = [string](Get-Content -LiteralPath $MarkdownFile -Raw -Encoding UTF8)

$ops = @(
    @{ op = 'add'; path = '/fields/System.Title'; value = $Title },
    @{ op = 'add'; path = '/fields/System.Description'; value = $body },
    @{ op = 'add'; path = '/multilineFieldsFormat/System.Description'; value = 'Markdown' }
)
if ($cfg['ADO_AREA_PATH']) { $ops += @{ op = 'add'; path = '/fields/System.AreaPath'; value = $cfg['ADO_AREA_PATH'] } }
if ($cfg['ADO_ITERATION_PATH']) { $ops += @{ op = 'add'; path = '/fields/System.IterationPath'; value = $cfg['ADO_ITERATION_PATH'] } }
if ($ParentId) {
    $ops += @{
        op = 'add'; path = '/relations/-'
        value = @{ rel = 'System.LinkTypes.Hierarchy-Reverse'; url = "$($cfg['ADO_ORG_URL'].TrimEnd('/'))/_apis/wit/workItems/$ParentId" }
    }
}

$json = ConvertTo-Json -InputObject $ops -Depth 5
$auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($cfg['ADO_PAT'])"))
$uri = "$($cfg['ADO_ORG_URL'].TrimEnd('/'))/$([uri]::EscapeDataString($cfg['ADO_PROJECT']))/_apis/wit/workitems/`$$([uri]::EscapeDataString($type))?api-version=7.1"

$resp = Invoke-RestMethod -Method Post -Uri $uri `
    -Headers @{ Authorization = "Basic $auth" } `
    -ContentType 'application/json-patch+json' `
    -Body ([Text.Encoding]::UTF8.GetBytes($json))

"Created #$($resp.id): $($resp._links.html.href)"

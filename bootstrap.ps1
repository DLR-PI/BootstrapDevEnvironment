param([string]$url, [string]$bootstrapFolder, [string]$bootstrapName, [string]$authUrl, [string]$clientId, [string]$redirectUri, [String[]]$scope, [string]$psMessage)
[Reflection.Assembly]::LoadWithPartialName("System.Web") | Out-Null; 
function Get-oAuth2AccessToken { 
    [CmdletBinding()] 
    param (
        [Parameter(Mandatory = $true)] [string] $AuthUrl, 
        [Parameter(Mandatory = $true)] [string] $ClientId, 
        [Parameter(Mandatory = $true)] [string] $RedirectUri, 
        [int] $SleepInterval = 2, 
        [Parameter(Mandatory = $true)] [String[]] $Scope
    ) 
    try {
        foreach ($item in $Scope) { 
            $ScopeString += $item + '+'; 
        } 

        $ScopeString = $ScopeString.TrimEnd('+'); 
        $RequestUrl = '{0}?client_id={1}&redirect_uri={2}&response_type=token&scope={3}' -f $AuthUrl, $ClientId, $RedirectUri, $ScopeString; 
        Write-Host ('[-] Requesting access token.'); 
        $IE = New-Object -ComObject InternetExplorer.Application; 
        $IE.Navigate($RequestUrl); 
        $IE.Visible = $true; 
        Write-Host -NoNewline ("[-] Waiting for access token, Exit here (Ctrl+C) if unsuccesful"); 
        while ($IE.LocationUrl -notmatch 'access_token=') { 
            Write-Host -NoNewline ".";
            Start-Sleep -Seconds $SleepInterval; 

            if ([console]::KeyAvailable)
            {
                $key = [system.console]::readkey($true)
                if (($key.key -eq "Esc"))
                {
                    Write-Host ("`n[-] No access token is found. Now using powershell prompt."); 
                    return $null;
                }
            }
        } 
        
        if ($IE.LocationUrl -notmatch 'access_token=') { 
            Write-Host ("`n[-] No access token is found. Now using powershell prompt."); 
            return $null; 
        } 

        Write-Host ("`n[-] Access token is found."); 
        [Void]($IE.LocationUrl -match '=([^&]*)'); 
        $accessToken = $Matches[1]; 
        $IE.Quit(); 
        return [System.Web.HttpUtility]::UrlDecode($accessToken); 
    }
    catch {
        return $null; 
    }
} 

function UnzipFile { 
    [CmdletBinding()] 
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)] [string]$file, 
        [string]$destination = (Get-Location).Path
    ) 
    try { 
        $shell = New-Object -ComObject Shell.Application; 
        ($shell.NameSpace($file)).items() | ForEach-Object { 
            $shell.Namespace($destination).copyhere($shell.NameSpace($_).items()); 
        } 
    } catch { 
        Write-Warning -Message "Unexpected Error. Error details: $_.Exception.Message";  
    } 
} 

function GetHeaders([string]$authUrl, [string]$clientId, [string]$redirectUri, [String[]]$scope, [string]$psMessage) {
    $headers = @{}; 
    $headers.Add("Content-Type", "application/octet-stream"); 
    $accessToken = Get-oAuth2AccessToken -AuthUrl "$authUrl" -ClientId "$clientId" -RedirectUri "$redirectUri" -Scope $scope; 
    if ($accessToken) { 
        $headers.Add("Authorization", ("Bearer {0}" -f $accessToken)); 
    } else { 
        $BitbucketCredential = Get-Credential -Message $psMessage; 
        if (!$BitbucketCredential) { 
            Write-Host "[-] Powershell prompt canceled.";
            Write-Host "[-] Cannot continue without credentials.";
            return $null; 
        }
    
        $username = $BitbucketCredential.UserName; 
        $password = $BitbucketCredential.GetNetworkCredential().Password; 
        $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $username, $password))); 
        $headers.Add("Authorization", ("Basic {0}" -f $base64AuthInfo)); 
    } 
    return $headers;
}

function RemoveItemIfExists($file) {
    If (Test-path $file) { 
        Remove-item $file; 
    } 
}
function CreateEmptyDirectory($folder) {
    If (Test-path $folder) { 
        Remove-item $folder -Recurse:$true -Force:$true -Confirm:$false -Verbose:$false; 
    } 
    New-Item -ItemType Directory -Path $folder | Out-Null; 
}

if (!$url -or !$bootstrapName) {
    Write-Host "Not enough parameters."
    return;
}

$rnd = Get-Random; 
Set-Location -Path $bootstrapFolder; 
$zipFilePath = "$bootstrapFolder$bootstrapName.zip"; 
$zipFolderPath = "$bootstrapFolder$bootstrapName\"; 
$url = ("{0}?rnd=$rnd" -f $url); 


$headers = GetHeaders -authUrl $authUrl -clientId $clientId -redirectUri $redirectUri -scope $scope -psMessage $psMessage;
if ($headers) {
    Write-Host "[-] Downloading repository.";
    RemoveItemIfExists $zipFilePath;
    Invoke-WebRequest -Method Get -Uri $url -OutFile $zipFilePath -Headers $headers;

    Write-Host "[-] Extracting zip file.";
    CreateEmptyDirectory $zipFolderPath;
    $zipFilePath | UnzipFile -Destination $zipFolderPath;
    Remove-Item -Path $zipFilePath;
    Write-Host '[-] Finished successfully';
}

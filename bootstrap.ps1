param(
    [string] $url, 
    [string] $bootstrapFolder, 
    [string] $bootstrapName, 
    [string] $authUrl, 
    [string] $tokenDomain, 
    [string] $tokenQuery, 
    [string] $clientId, 
    [string] $redirectUri, 
    [String[]] $scope, 
    [string] $psMessage
)

[Reflection.Assembly]::LoadWithPartialName("System.Web") | Out-Null; 
function Get-oAuth2AccessToken { 
    [CmdletBinding()] 
    param (
        [string] $authUrl, 
        [String] $tokenDomain,
        [String] $tokenQuery,
        [string] $clientId, 
        [string] $redirectUri, 
        [String[]] $scope
    ) 
    try {
        foreach ($item in $scope) { 
            $scopeString += $item + '+'; 
        } 

        $scopeString = $scopeString.TrimEnd('+'); 
        $RequestUrl = '{0}?client_id={1}&redirect_uri={2}&response_type=token&scope={3}' -f $authUrl, $clientId, $redirectUri, $scopeString; 
        
        Write-Host ('[-] Requesting access token.'); 
        $IE = New-Object -ComObject InternetExplorer.Application; 
        $IE.Navigate($RequestUrl); 
        $IE.Visible = $true; 
        
        $tryCount = 0;
        $lastUrl = "";
        Write-Host -NoNewline ("[-] Waiting for access token, Exit here (Ctrl+C) if unsuccesful"); 
        while ($IE.LocationUrl -notmatch $tokenDomain -or $IE.LocationUrl -notmatch $tokenQuery) { 

            if (($tryCount % 20) -eq 0) {
                Write-Host -NoNewline ".";
            }

            if ($lastUrl -ne $IE.LocationUrl) {
                $lastUrl = $IE.LocationUrl
            }

            Start-Sleep -Milliseconds 100;

            if ([console]::KeyAvailable) {
                $key = [system.console]::readkey($true)
                if (($key.key -eq "Esc"))
                {
                    Write-Host ("`n[-] No access token is found. Now using powershell prompt."); 
                    return $null;
                }
            }

            $tryCount++;
        } 
        
        if ($IE.LocationUrl -notmatch $tokenQuery) { 
            Write-Host ("`n[-] No access token is found. Now using powershell prompt."); 
            return $null; 
        } 

        Write-Host ("`n[-] Access token is found."); 
        [Void]($IE.LocationUrl -match "$tokenQuery([^&]*)"); 
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

function GetHeaders(
    [string] $authUrl, 
    [string] $tokenDomain, 
    [string] $tokenQuery, 
    [string] $clientId, 
    [string] $redirectUri, 
    [String[]] $scope, 
    [string] $psMessage
) {
    $headers = @{}; 
    $headers.Add("Content-Type", "application/octet-stream"); 
    $accessToken = Get-oAuth2AccessToken -authUrl $authUrl -tokenDomain $tokenDomain -tokenQuery $tokenQuery -clientId $clientId -redirectUri $redirectUri -scope $scope; 
    if ($accessToken) { 
        $headers.Add("Authorization", ("Bearer {0}" -f $accessToken)); 
    } else { 
        $Credential = Get-Credential -Message $psMessage; 
        if (!$Credential) { 
            Write-Host "[-] Powershell prompt canceled.";
            Write-Host "[-] Cannot continue without credentials.";
            return $null; 
        }
    
        $username = $Credential.UserName; 
        $password = $Credential.GetNetworkCredential().Password; 
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


$headers = GetHeaders -authUrl $authUrl -tokenDomain $tokenDomain -tokenQuery $tokenQuery -clientId $clientId -redirectUri $redirectUri -scope $scope -psMessage $psMessage;
if ($headers) {
    Write-Host "[-] Removing old zip file if exists: $zipFilePath";
    RemoveItemIfExists $zipFilePath;

    Write-Host "[-] Downloading repository.";
    Invoke-WebRequest -Method Get -Uri $url -OutFile $zipFilePath -Headers $headers;

    If (!(Test-path -Path $zipFilePath)) { 
        Write-Host "[-] File is not downloaded.";
    } 

    Write-Host "[-] Creating an empty folder: $zipFolderPath";
    CreateEmptyDirectory $zipFolderPath;

    Write-Host "[-] Extracting zip file: $zipFilePath";
    $zipFilePath | UnzipFile -Destination $zipFolderPath;

    Write-Host "[-] Removing zip file: $zipFilePath";
    Remove-Item -Path $zipFilePath;

    Write-Host '[-] Finished successfully';

    Invoke-Expression ("{0}start.ps1" -f $zipFolderPath);
}

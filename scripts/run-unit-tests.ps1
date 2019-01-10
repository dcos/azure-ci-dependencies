Param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("dcos-go", "dcos-metrics", "dcos-diagnostics", "dcos-net")]
    [string]$Component,
    [Parameter(Mandatory=$true)]
    [string]$Directory
)

$LIBSODIUM_GIT_URL = "https://github.com/jedisct1/libsodium"

$GOLANG_DOWNLOAD_LINK = "https://dl.google.com/go/go1.11.windows-amd64.msi"
$GIT_DOWNLOAD_LINK = "https://github.com/git-for-windows/git/releases/download/v2.16.1.windows.3/Git-2.16.1.3-64-bit.exe"
$7_ZIP_DOWNLOAD_LINK = "https://www.7-zip.org/a/7z1801-x64.exe"
$2012_RUNTIME_DOWNLOAD_LINK = "https://download.microsoft.com/download/1/6/B/16B06F60-3B20-4FF2-B699-5E9B7962F9AE/VSU_4/vcredist_x64.exe"
$2013_RUNTIME_DOWNLOAD_LINK = "https://download.microsoft.com/download/2/E/6/2E61CFA4-993B-4DD4-91DA-3737CD5CD6E3/vcredist_x64.exe"
$DIG_DOWNLOAD_LINK = "https://downloads.mesosphere.io/ms-azure/assets/dig-x64.zip"
$OTP_DOWNLOAD_LINK = "http://erlang.org/download/otp_win64_21.1.exe"
$VS_2017_DOWNLOAD_LINK = "https://download.visualstudio.microsoft.com/download/pr/11886246/045b56eb413191d03850ecc425172a7d/vs_Community.exe"
$MSYS2_DOWNLOAD_LINK = "http://downloads.mesosphere.io/ms-azure/assets/msys2-x64.zip"

$GIT_DIR = Join-Path $env:ProgramFiles "Git"
$GO_DIR = Join-Path $env:SystemDrive "go"
$7_ZIP_DIR = Join-Path $env:ProgramFiles "7-Zip"
$DIG_DIR = Join-Path $env:ProgramFiles "Dig"
$OTP_DIR = Join-Path $env:ProgramFiles "erlang"
$VS_2017_DIR = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\2017\Community"


function Add-ToSystemPath {
    Param(
        [Parameter(Mandatory=$false)]
        [string[]]$Path
    )
    if(!$Path) {
        return
    }
    $systemPath = [System.Environment]::GetEnvironmentVariable('Path', 'Machine').Split(';')
    $currentPath = $env:PATH.Split(';')
    foreach($p in $Path) {
        if($p -notin $systemPath) {
            $systemPath += $p
        }
        if($p -notin $currentPath) {
            $currentPath += $p
        }
    }
    $env:PATH = $currentPath -join ';'
    setx.exe /M PATH ($systemPath -join ';')
    if($LASTEXITCODE) {
        Throw "Failed to set the new system path"
    }
}

function Start-ExecCall {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$FilePath,
        [Parameter(Mandatory=$false)]
        [string[]]$ArgumentList
    )
    $parameters = @{
        'FilePath' = $FilePath
        'NoNewWindow' = $true
        'Wait' = $true
        'PassThru' = $true
    }
    if($ArgumentList) {
        $parameters['ArgumentList'] = $ArgumentList
    }
    $execCall = "$FilePath $($ArgumentList -join ' ')"
    Write-Output "Executing: $execCall"
    $p = Start-Process @parameters
    if($p.ExitCode -ne 0) {
        Throw "Failed to execute: $execCall"
    }
}

function Start-ExecuteWithRetry {
    Param(
        [Parameter(Mandatory=$true)]
        [Alias("Command")]
        [ScriptBlock]$ScriptBlock,
        [int]$MaxRetryCount=10,
        [int]$RetryInterval=3,
        [string]$RetryMessage,
        [array]$ArgumentList=@()
    )
    $currentErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $retryCount = 0
    while ($true) {
        try {
            $res = Invoke-Command -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList
            $ErrorActionPreference = $currentErrorActionPreference
            return $res
        } catch [System.Exception] {
            $retryCount++
            if ($retryCount -gt $MaxRetryCount) {
                $ErrorActionPreference = $currentErrorActionPreference
                Throw
            } else {
                if($RetryMessage) {
                    Write-Host $RetryMessage
                } elseif($_) {
                    Write-Host $_
                }
                Start-Sleep $RetryInterval
            }
        }
    }
}

function Start-FileDownload {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$URL,
        [Parameter(Mandatory=$true)]
        [string]$Destination
    )
    $webclient = New-Object System.Net.WebClient
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
    Start-ExecuteWithRetry { $webclient.DownloadFile($URL, $Destination) }
}

function Install-CITool {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$InstallerPath,
        [Parameter(Mandatory=$false)]
        [string]$InstallDirectory,
        [Parameter(Mandatory=$false)]
        [string[]]$ArgumentList,
        [Parameter(Mandatory=$false)]
        [string[]]$EnvironmentPath
    )
    if($InstallDirectory -and (Test-Path $InstallDirectory)) {
        Write-Output "$InstallerPath is already installed."
        Add-ToSystemPath -Path $EnvironmentPath
        return
    }
    $parameters = @{
        'FilePath' = $InstallerPath
        'NoNewWindow' = $true
        'Wait' = $true
        'PassThru' = $true
    }
    if($ArgumentList) {
        $parameters['ArgumentList'] = $ArgumentList
    }
    if($InstallerPath.EndsWith('.msi')) {
        $parameters['FilePath'] = 'msiexec.exe'
        $parameters['ArgumentList'] = @("/i", $InstallerPath) + $ArgumentList
    }
    Write-Output "Installing $InstallerPath"
    $p = Start-Process @parameters
    if($p.ExitCode -ne 0) {
        Throw "Failed to install: $InstallerPath"
    }
    Add-ToSystemPath -Path $EnvironmentPath
    Write-Output "Successfully installed: $InstallerPath"
}

function Install-7Zip {
    Write-Output "Installing 7-Zip"
    $installer = Join-Path $env:TEMP "7z-x64.exe"
    Start-FileDownload -URL $7_ZIP_DOWNLOAD_LINK -Destination $installer
    Install-CITool -InstallerPath $installer `
                   -InstallDirectory $7_ZIP_DIR `
                   -ArgumentList @("/S") `
                   -EnvironmentPath @($7_ZIP_DIR)
    Remove-Item -Force -Path $installer -ErrorAction SilentlyContinue
}

function Install-ZipCITool {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$ZipPath,
        [Parameter(Mandatory=$true)]
        [string]$InstallDirectory,
        [Parameter(Mandatory=$false)]
        [string[]]$EnvironmentPath
    )
    if(Test-Path $InstallDirectory) {
        Write-Output "$ZipPath is already installed."
        Add-ToSystemPath -Path $EnvironmentPath
        return
    }
    New-Item -ItemType "Directory" -Path $InstallDirectory
    $extension = $ZipPath.Split('.')[-1]
    if($extension -ne "zip") {
        Throw "ERROR: $ZipPath is not a zip package"
    }
    7z.exe x $ZipPath -o"$InstallDirectory" -y
    if($LASTEXITCODE) {
        Throw "ERROR: Failed to extract $ZipPath to $InstallDirectory"
    }
    Add-ToSystemPath $EnvironmentPath
}

function Install-Msys2 {
    Write-Output "Installing Msys2"
    $zipPath = Join-Path $env:TEMP "msys2.zip"
    Start-FileDownload -URL $MSYS2_DOWNLOAD_LINK -Destination $zipPath
    $installDir = Join-Path $env:SystemDrive "msys2"
    try {
        Install-ZipCITool -ZipPath $zipPath `
                          -InstallDirectory $installDir `
                          -EnvironmentPath @("$installDir\usr\bin", "$installDir\mingw64\bin")
    } catch {
        Remove-Item -Recurse -Force $installDir
        Throw
    }
    pacman.exe -S mingw-w64-x86_64-gcc --noconfirm
    if($LASTEXITCODE) {
        Throw "ERROR: Failed to install gcc via MSys2 pacman"
    }
}

function Install-Git {
    Write-Output "Installing Git"
    $installer = Join-Path $env:TEMP "git-installer-64bit.exe"
    Start-FileDownload -URL $GIT_DOWNLOAD_LINK -Destination $installer
    Install-CITool -InstallerPath $installer `
                   -InstallDirectory $GIT_DIR `
                   -ArgumentList @("/VERYSILENT") `
                   -EnvironmentPath @($GIT_DIR, "${GIT_DIR}\cmd", "${GIT_DIR}\usr\bin")
    # Checkout as-is, commit as-is, otherwise some tests will fail (example: gofmt)
    git.exe config --global core.autocrlf false
    if($LASTEXITCODE) {
        Throw "Failed to set core.autocrlf"
    }
    # Enable sym-links system-wide
    git.exe config --system core.symlinks true
    if($LASTEXITCODE) {
        Throw "Failed to set core.symlinks"
    }
}

function Install-Golang {
    Write-Output "Installing Golang"
    $installer = Join-Path $env:TEMP "golang.msi"
    Start-FileDownload -URL $GOLANG_DOWNLOAD_LINK -Destination $installer
    Install-CITool -InstallerPath $installer `
                   -InstallDirectory $GO_DIR `
                   -ArgumentList @("/qb") `
                   -EnvironmentPath @("$GO_DIR\bin")
    $goPath = Join-Path $HOME "golang"
    if(Test-Path $goPath) {
        Remove-Item -Recurse -Force $goPath
    }
    New-Item -ItemType "Directory" -Path $goPath
    Add-ToSystemPath -Path @("${GO_DIR}\bin", "${goPath}\bin")
    $env:GOPATH = $goPath
}

function Install-GoDependencies {
    $deps = @(
        "github.com/sirupsen/logrus",
        "github.com/antonholmquist/jason"
    )
    foreach($d in $deps) {
        go.exe get $d
        if($LASTEXITCODE) {
            Throw "Failed to install $d"
        }
    }
}

function Install-Dig {
    Write-Output "Installing Visual Studio 2012 Runtime"
    $installer = Join-Path $env:TEMP "vcredist_2012_x64.exe"
    Start-FileDownload -URL $2012_RUNTIME_DOWNLOAD_LINK -Destination $installer
    Install-CITool -InstallerPath $installer -ArgumentList @("/install", "/passive")
    Remove-Item -Force -Path $installer -ErrorAction SilentlyContinue
    Write-Output "Installing Dig x64"
    $zipPath = Join-Path $env:TEMP "dig-x64.zip"
    Start-FileDownload -URL $DIG_DOWNLOAD_LINK -Destination $zipPath
    try {
        Install-ZipCITool -ZipPath $zipPath `
                          -InstallDirectory $DIG_DIR `
                          -EnvironmentPath @("$DIG_DIR\bin")
    } catch {
        Remove-Item -Recurse -Force $DIG_DIR
        Throw
    }
    Remove-Item -Force -Path $zipPath -ErrorAction SilentlyContinue
}

function Install-OTP {
    Write-Output "Installing Visual Studio 2013 Runtime"
    $installer = Join-Path $env:TEMP "vcredist_2013_x64.exe"
    Start-FileDownload -URL $2013_RUNTIME_DOWNLOAD_LINK -Destination $installer
    Install-CITool -InstallerPath $installer -ArgumentList @("/install", "/passive")
    Remove-Item -Force -Path $installer -ErrorAction SilentlyContinue
    Write-Output "Installing Erlang OTP distribution"
    $filePath = Join-Path $env:TEMP "otp_win64.exe"
    Start-FileDownload -URL $OTP_DOWNLOAD_LINK -Destination $filePath
    Install-CITool -InstallerPath $filePath -InstallDirectory $OTP_DIR `
                   -ArgumentList @("/S", "/D=$OTP_DIR") -EnvironmentPath @("$OTP_DIR\bin")
    Remove-Item -Force -Path $filePath -ErrorAction SilentlyContinue
    $config = @(
        "[erlang]",
        "Bindir=$("$OTP_DIR\erts-10.1\bin" -replace '\\', '\\')",
        "Progname=erl",
        "Rootdir=$($OTP_DIR -replace '\\', '\\')"
    )
    Set-Content -Path "$OTP_DIR\bin\erl.ini" -Value $config
    Set-Content -Path "$OTP_DIR\erts-10.1\bin\erl.ini" -Value $config
}

function Install-VisualStudio2017 {
    Write-Output "Installing Visual Studio 2017 Community"
    $installerArguments = @(
        "--add", "Microsoft.VisualStudio.Workload.NativeDesktop",
        "--quiet", "--wait", "--includeRecommended"
    )
    $installer = Join-Path $env:TEMP "vs_2017_community.exe"
    Start-FileDownload -URL $VS_2017_DOWNLOAD_LINK -Destination $installer
    Install-CITool -InstallerPath $installer `
                   -InstallDirectory $VS_2017_DIR `
                   -ArgumentList $installerArguments
}

function Set-WindowsSDK {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$VCXProjFile,
        [Parameter(Mandatory=$true)]
        [string]$Version
    )

    [xml]$settings = Get-Content $VCXProjFile
    $target = $settings.Project.PropertyGroup | ? { $_.Label -eq "Globals" }
    if($target.WindowsTargetPlatformVersion) {
        $target.WindowsTargetPlatformVersion = $Version
    } else {
        $element = $settings.CreateElement('WindowsTargetPlatformVersion', $settings.DocumentElement.NamespaceURI)
        $element.InnerText = $Version
        $target.AppendChild($element) | Out-Null
    }
    $settings.Save($VCXProjFile)
}

function Set-VCVariables {
    Param(
        [string]$Platform="amd64"
    )
    $vcPath = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\2017\Community\VC\Auxiliary\Build\"
    $vcVars = cmd.exe /c "`"${vcPath}\vcvarsall.bat`" $Platform & set"
    if($LASTEXITCODE) {
        Throw "Failed to get all VC variables via the vcvarsall.bat script"
    }
    $vcVars | Foreach-Object {
        if ($_ -match "=") {
            $v = $_.split("=")
            Set-Item -Force -Path "ENV:\$($v[0])" -Value "$($v[1])"
        }
    }
}

function Start-LibsodiumBuild {
    Set-VCVariables
    $libsodiumGitDir = Join-Path $Directory "libsodium"
    if(Test-Path $libsodiumGitDir) {
        Remove-Item -Recurse -Force $libsodiumGitDir
    }
    git.exe clone $LIBSODIUM_GIT_URL $libsodiumGitDir
    if($LASTEXITCODE) {
        Throw "Failed to clone dcos-net dependency: $LIBSODIUM_GIT_URL"
    }
    Write-Output "Starting the libsodium build"
    Set-WindowsSDK -VCXProjFile "$libsodiumGitDir\builds\msvc\vs2017\libsodium\libsodium.vcxproj" -Version "10.0.17134.0"
    MSBuild.exe "$libsodiumGitDir\builds\msvc\vs2017\libsodium.sln" /nologo /target:Build /p:Platform=x64 /p:Configuration=DynRelease
    if($LASTEXITCODE) {
        Throw "Failed to build dcos-net dependency: $LIBSODIUM_GIT_URL"
    }
    $dynamicDir = Join-Path $libsodiumGitDir "bin\x64\Release\v141\dynamic"
    $env:LDFLAGS=" /LIBPATH:$($dynamicDir -replace '\\', '/') libsodium.lib "
    $includeDir = Join-Path $libsodiumGitDir "src/libsodium/include"
    $env:CFLAGS=" -I$($includeDir -replace '\\', '/') "
    $env:PATH = "$libsodiumGitDir\bin\x64\Release\v141\dynamic;" + $env:PATH
    Write-Output "Successfully built dcos-net dependency: $LIBSODIUM_GIT_URL"
}

function Start-DCOSGoUnitTests {
    $dcosDir = Join-Path $env:GOPATH "src\github.com\dcos"
    if(!(Test-Path $dcosDir)) {
        New-Item -ItemType Directory -Path $dcosDir
    }
    $dcosGoDir = Join-Path $dcosDir "dcos-go"
    if(Test-Path $dcosGoDir) {
        Remove-Item -Recurse -Force $dcosGoDir
    }
    Copy-Item -Recurse -Force $Directory $dcosGoDir
    Push-Location $dcosGoDir
    try {
        # Run the tests
        .\scripts\test.ps1
        if($LASTEXITCODE) {
            Throw "Failed to run dcos-go unit tests"
        }
    } finally {
        Pop-Location
    }
}

function Start-DCOSMetricsUnitTests {
    $dcosDir = Join-Path $env:GOPATH "src\github.com\dcos"
    if(!(Test-Path $dcosDir)) {
        New-Item -ItemType Directory -Path $dcosDir
    }
    $dcosMetricsDir = Join-Path $dcosDir "dcos-metrics"
    if(Test-Path $dcosMetricsDir) {
        Remove-Item -Recurse -Force $dcosMetricsDir
    }
    Copy-Item -Recurse -Force $Directory $dcosMetricsDir
    Push-Location $dcosMetricsDir
    try {
        # Need to build before to fix dependencies
        .\scripts\build.ps1 collector
        if($LASTEXITCODE) {
            Throw "Failed to run: .\scripts\build.ps1 collector"
        }
        # Run the tests
        .\scripts\test.ps1 collector unit
        if($LASTEXITCODE) {
            Throw "Failed to run: .\scripts\build.ps1 collector unit"
        }
    } finally {
        Pop-Location
    }
}

function Start-DCOSDiagnosticsUnitTests {
    $dcosDir = Join-Path $env:GOPATH "src\github.com\dcos"
    if(!(Test-Path $dcosDir)) {
        New-Item -ItemType Directory -Path $dcosDir
    }
    $dcosDiagnostics = Join-Path $dcosDir "dcos-diagnostics"
    if(Test-Path $dcosDiagnostics) {
        Remove-Item -Recurse -Force $dcosDiagnostics
    }
    Copy-Item -Recurse -Force $Directory $dcosDiagnostics
    Push-Location $dcosDiagnostics
    try {
        # Run the tests
        .\scripts\make.ps1 test
        if($LASTEXITCODE) {
            Throw "Failed to run dcos-diagnostics unit tests"
        }
    } finally {
        Pop-Location
    }
}

function Start-DCOSNetTests {
    Push-Location $Directory
    Start-ExecCall -FilePath "escript.exe" -ArgumentList @(".\rebar3", "as", "windows", "release")
    Start-ExecCall -FilePath "escript.exe" -ArgumentList @(".\rebar3", "as", "test,windows", "eunit", "-v")
    Start-ExecCall -FilePath "escript.exe" -ArgumentList @(".\rebar3", "as", "test,windows", "xref")
    Start-ExecCall -FilePath "escript.exe" -ArgumentList @(".\rebar3", "as", "test,windows", "cover")
    Start-ExecCall -FilePath "escript.exe" -ArgumentList @(".\rebar3", "dialyzer")
    Start-ExecCall -FilePath "escript.exe" -ArgumentList @(".\rebar3", "edoc")
    Start-ExecCall -FilePath "escript.exe" -ArgumentList @(".\rebar3", "as", "test,windows", "ct", "--suite=apps/dcos_dns/test/dcos_dns_SUITE","-v")
    Pop-Location
}


try {
    switch($Component) {
        "dcos-go" {
            Install-7Zip
            Install-Msys2
            Install-Git
            Install-Golang
            Install-GoDependencies
            Start-DCOSGoUnitTests
        }
        "dcos-metrics" {
            Install-Git
            Install-Golang
            Install-GoDependencies
            Start-DCOSMetricsUnitTests
        }
        "dcos-diagnostics" {
            Install-7Zip
            Install-Msys2
            Install-Git
            Install-Golang
            Start-DCOSDiagnosticsUnitTests
        }
        "dcos-net" {
            Install-Git
            Install-7Zip
            Install-Dig
            Install-OTP
            Install-VisualStudio2017
            Start-LibsodiumBuild
            Start-DCOSNetTests
        }
        default {
            Throw "Cannot run unit tests for $Component"
        }
    }
} catch {
    Write-Output $_.ToString()
    Write-Output $_.ScriptStackTrace
    exit 1
}
exit 0

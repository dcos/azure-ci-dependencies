$ErrorActionPreference = "Stop"


function Start-DCOSWindowsBuild {
    .\build_local_windows.ps1
    if($LASTEXITCODE) {
        Throw "DC/OS Windows build failed"
    }
    Write-Output "Successful DC/OS Windows build"
}


try {
    Start-DCOSWindowsBuild
} catch {
    Write-Output $_.ToString()
    Write-Output $_.ScriptStackTrace
    exit 1
}
exit 0

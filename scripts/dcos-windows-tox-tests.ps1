$ErrorActionPreference = "Stop"

$EXPECTED_PYTHON_VERSION = "Python 3.6.5"


function Confirm-DCOSToxRequirements {
    # - Make sure the correct Python version is installed
    $pythonVersion = python.exe --version
    if($LASTEXITCODE) {
        Throw "Failed to get the Python version"
    }
    if($pythonVersion -ne $EXPECTED_PYTHON_VERSION) {
        Throw "Python has the wrong version! Expected $EXPECTED_PYTHON_VERSION and found $pythonVersion"
    }
    # - Make sure pip is present
    pip.exe --version 2>&1 > $null
    if($LASTEXITCODE) {
        Throw "Failed to get the Python pip version. Perhaps it's not installed or not available in the PATH"
    }
    # - Install Python tox if it's not already installed
    $toxPackage = pip.exe freeze | Where-Object { $_.StartsWith('tox==') }
    if (!$toxPackage) {
        pip.exe install tox
        if($LASTEXITCODE) {
            Throw "Failed to install Python tox"
        }
    }
}

function Start-DCOSToxUnitTests {
    python.exe -m tox
    if($LASTEXITCODE) {
        Throw "Tox unit tests failed"
    }
}


try {
    Confirm-DCOSToxRequirements
    Start-DCOSToxUnitTests
} catch {
    Write-Output $_.ToString()
    Write-Output $_.ScriptStackTrace
}
exit 0

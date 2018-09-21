This directory contains the following scripts:

* `windows-ci-server-setup.ps1` - Performs an unattended installation of all the prerequisites needed for the DC/OS Windows build and Tox unit tests. It should be run only once when setting the up the Windows CI agent.
* `dcos-windows-buid.ps1` - Used to perform a local DC/OS Windows build. It assumes that the current working directory is a checkout of the upstream [dcos/dcos](https://github.com/dcos/dcos) repository. All the prerequisites must be already installed before executing this script.
* `dcos-windows-tox-tests.ps1` - Used to execute the DC/OS Windows Tox unit tests. It assumes that the current working directory is a checkout of the upstream [dcos/dcos](https://github.com/dcos/dcos) repository.
* `run-unit-tests.ps1` - Generalized PowerShell script to run the Windows unit tests against any of the 4 projects: `dcos-go`, `dcos-metrics`, `dcos-diagnostics` and `dcos-net`.
  
  You need to locally check-out the Git repository and execute the script as such:
  ```
  .\run-unit-tests.ps1 -Component "dcos-net" -Directory "<local_git_repository>"
  ```
  
  where `<local_git_repository>` points to the local Git directory of the component specified via `Component` parameter.

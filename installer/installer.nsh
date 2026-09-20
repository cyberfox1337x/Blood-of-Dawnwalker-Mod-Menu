!macro cyberfox1337x_function MODULE_NAME
!macroend
!insertmacro cyberfox1337x_function "dawnwalker_runtime_nsis"

!define DAWNWALKER_RUNTIME_ROOT "$INSTDIR\resources\dawnwalker-runtime"
!define DAWNWALKER_RUNTIME_HELPER "${DAWNWALKER_RUNTIME_ROOT}\DawnwalkerRuntimeInstaller.ps1"

!macro customInstall
  DetailPrint "Validating and installing the official Dawnwalker offline runtime..."
  nsExec::ExecToStack '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "${DAWNWALKER_RUNTIME_HELPER}" -Action Install -PayloadRoot "${DAWNWALKER_RUNTIME_ROOT}" -ApplicationVersion "${VERSION}"'
  Pop $0
  Pop $1
  ${If} $0 != 0
    MessageBox MB_ICONSTOP|MB_OK "The Dawnwalker runtime was not installed.$\r$\n$\r$\n$1"
    Abort
  ${EndIf}
!macroend

!macro customUnInstall
  DetailPrint "Restoring the pre-install Dawnwalker runtime state..."
  nsExec::ExecToStack '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "${DAWNWALKER_RUNTIME_HELPER}" -Action Uninstall'
  Pop $0
  Pop $1
  ${If} $0 != 0
    MessageBox MB_ICONSTOP|MB_OK "The Dawnwalker runtime could not be restored, so the menu was not uninstalled.$\r$\n$\r$\n$1"
    Abort
  ${EndIf}
!macroend

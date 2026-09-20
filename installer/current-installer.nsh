!macro cyberfox1337x_function MODULE_NAME
!macroend
!insertmacro cyberfox1337x_function "dawnwalker_current_runtime_nsis"
!define DAWNWALKER_CURRENT_ROOT "$INSTDIR\resources\current-runtime"
!define DAWNWALKER_CURRENT_HELPER "${DAWNWALKER_CURRENT_ROOT}\DawnwalkerImportedRuntimeInstaller.ps1"
!macro customInit
  InitPluginsDir
  File /oname=$PLUGINSDIR\DawnwalkerImportedRuntimeInstaller.ps1 "${PROJECT_DIR}\installer\DawnwalkerImportedRuntimeInstaller.ps1"
  File /oname=$PLUGINSDIR\DawnwalkerRuntimeInstaller.ps1 "${PROJECT_DIR}\installer\DawnwalkerRuntimeInstaller.ps1"
  File /oname=$PLUGINSDIR\official-build.json "${PROJECT_DIR}\installer\current-runtime\official-build.json"
  nsExec::ExecToStack '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy RemoteSigned -File "$PLUGINSDIR\DawnwalkerImportedRuntimeInstaller.ps1" -Action Preflight -PayloadRoot "$PLUGINSDIR"'
  Pop $0
  Pop $1
  ${If} $0 != 0
    MessageBox MB_ICONSTOP|MB_OK "Dawnwalker installation checks did not pass.$\r$\n$\r$\n$1"
    Abort
  ${EndIf}
!macroend
!macro customInstall
  DetailPrint "Installing the exact-build Dawnwalker mod runtime with rollback backups..."
  nsExec::ExecToStack '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy RemoteSigned -File "${DAWNWALKER_CURRENT_HELPER}" -Action Install -PayloadRoot "${DAWNWALKER_CURRENT_ROOT}" -ApplicationVersion "${VERSION}"'
  Pop $0
  Pop $1
  ${If} $0 != 0
    MessageBox MB_ICONSTOP|MB_OK "The Dawnwalker runtime was not installed.$\r$\n$\r$\n$1"
    Abort
  ${EndIf}
!macroend
!macro customUnInstall
  ; Preserve runtime ownership through an app upgrade; the new helper updates it transactionally.
  ${IfNot} ${isUpdated}
  DetailPrint "Restoring the Dawnwalker runtime backup..."
  nsExec::ExecToStack '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy RemoteSigned -File "${DAWNWALKER_CURRENT_HELPER}" -Action Uninstall -PayloadRoot "${DAWNWALKER_CURRENT_ROOT}"'
  Pop $0
  Pop $1
  ${If} $0 != 0
    MessageBox MB_ICONSTOP|MB_OK "Runtime restoration did not finish, so the menu was not uninstalled.$\r$\n$\r$\n$1"
    Abort
  ${EndIf}
  ${EndIf}
!macroend

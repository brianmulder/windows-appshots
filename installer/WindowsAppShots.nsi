Unicode True

!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "FileFunc.nsh"
!include "Sections.nsh"
!include "x64.nsh"

!define APP_NAME "Windows AppShots"
!define APP_VERSION "0.1.1"
!define APP_PUBLISHER "Brian Mulder"
!define APP_ID "WindowsAppShots"
!define SOURCE_ROOT ".."

Var StateRoot

Name "${APP_NAME}"
OutFile "${SOURCE_ROOT}\dist\WindowsAppShots-Setup-${APP_VERSION}.exe"
InstallDir "$LOCALAPPDATA\Programs\WindowsAppShots"
InstallDirRegKey HKCU "Software\${APP_ID}" "InstallDir"
RequestExecutionLevel user
SetCompressor /SOLID lzma
SetDateSave off
CRCCheck force
BrandingText "${APP_NAME}"
Icon "${SOURCE_ROOT}\assets\branding\windows\windows-appshots.ico"
UninstallIcon "${SOURCE_ROOT}\assets\branding\windows\windows-appshots.ico"

VIProductVersion "0.1.1.0"
VIAddVersionKey /LANG=1033 "ProductName" "${APP_NAME}"
VIAddVersionKey /LANG=1033 "CompanyName" "${APP_PUBLISHER}"
VIAddVersionKey /LANG=1033 "FileDescription" "${APP_NAME} installer"
VIAddVersionKey /LANG=1033 "FileVersion" "${APP_VERSION}.0"
VIAddVersionKey /LANG=1033 "ProductVersion" "${APP_VERSION}"
VIAddVersionKey /LANG=1033 "LegalCopyright" "Copyright (c) 2026 Brian Mulder"

!define MUI_ABORTWARNING
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "${SOURCE_ROOT}\LICENSE"
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

Section "Windows AppShots (required)" SEC_CORE
  SectionIn RO
  SetShellVarContext current
  ; A running watcher owns the installed executable. Ask that exact, verified
  ; watcher to stop before replacing files during an upgrade.
  IfFileExists "$INSTDIR\bin\AppshotCapture.exe" 0 upgrade_stop_done
  nsExec::ExecToStack '"$INSTDIR\bin\AppshotCapture.exe" stop --state-root "$StateRoot"'
  Pop $0
  Pop $1
  ${If} $0 != 0
    IfSilent +2
    MessageBox MB_ICONSTOP|MB_OK "Windows AppShots could not stop the existing watcher.$\r$\n$\r$\n$1"
    Abort
  ${EndIf}
upgrade_stop_done:
  ; Remove the pre-release skill surface when upgrading an older local build.
  Delete "$INSTDIR\skills\capture-windows-appshot\SKILL.md"
  RMDir "$INSTDIR\skills\capture-windows-appshot"
  RMDir "$INSTDIR\skills"
  SetOutPath "$INSTDIR\bin"
  File "${SOURCE_ROOT}\bin\AppshotCapture.exe"
  SetOutPath "$INSTDIR\mcp"
  File "${SOURCE_ROOT}\mcp\server-lib.mjs"
  File "${SOURCE_ROOT}\mcp\server.mjs"
  SetOutPath "$INSTDIR\.agents\plugins"
  File "${SOURCE_ROOT}\.agents\plugins\marketplace.json"
  SetOutPath "$INSTDIR\.codex-plugin"
  File "${SOURCE_ROOT}\.codex-plugin\plugin.json"
  SetOutPath "$INSTDIR\assets\branding"
  File "${SOURCE_ROOT}\assets\branding\app-icon-256.png"
  SetOutPath "$INSTDIR\scripts"
  File "${SOURCE_ROOT}\scripts\register-codex.ps1"
  File "${SOURCE_ROOT}\scripts\unregister-codex.ps1"
  SetOutPath "$INSTDIR"
  File "${SOURCE_ROOT}\.mcp.json"
  File "${SOURCE_ROOT}\package.json"
  File "${SOURCE_ROOT}\README.md"
  File "${SOURCE_ROOT}\CONTRIBUTING.md"
  File "${SOURCE_ROOT}\SECURITY.md"
  File "${SOURCE_ROOT}\PRIVACY.md"
  File "${SOURCE_ROOT}\CODE_SIGNING.md"
  File "${SOURCE_ROOT}\LICENSE"

  WriteUninstaller "$INSTDIR\uninstall.exe"
  WriteRegStr HKCU "Software\${APP_ID}" "InstallDir" "$INSTDIR"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_ID}" "DisplayName" "${APP_NAME}"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_ID}" "DisplayVersion" "${APP_VERSION}"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_ID}" "Publisher" "${APP_PUBLISHER}"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_ID}" "DisplayIcon" "$INSTDIR\bin\AppshotCapture.exe"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_ID}" "UninstallString" '"$INSTDIR\uninstall.exe"'
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_ID}" "NoModify" 1
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_ID}" "NoRepair" 1

  CreateDirectory "$SMPROGRAMS\Windows AppShots"
  CreateShortCut "$SMPROGRAMS\Windows AppShots\Windows AppShots watcher.lnk" "$INSTDIR\bin\AppshotCapture.exe" 'watch --state-root "$LOCALAPPDATA\WindowsAppshots" --tray true' "$INSTDIR\bin\AppshotCapture.exe"
  CreateShortCut "$SMPROGRAMS\Windows AppShots\Open capture folder.lnk" "$WINDIR\explorer.exe" '"$LOCALAPPDATA\WindowsAppshots\captures"'
  CreateShortCut "$SMPROGRAMS\Windows AppShots\Uninstall Windows AppShots.lnk" "$INSTDIR\uninstall.exe"
SectionEnd

Section "Register the plugin with Codex" SEC_CODEX
  nsExec::ExecToStack '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "$INSTDIR\scripts\register-codex.ps1" -AppRoot "$INSTDIR"'
  Pop $0
  Pop $1
  ${If} $0 != 0
    IfSilent register_done
    MessageBox MB_ICONEXCLAMATION|MB_OK "Windows AppShots was installed, but Codex registration could not be refreshed.$\r$\n$\r$\n$1"
  ${Else}
    IfSilent register_done
    MessageBox MB_ICONINFORMATION|MB_OK "Windows AppShots was installed and registered.$\r$\n$\r$\nFully quit and restart Codex before using the plugin. An already-running Codex process can keep stale skill metadata from an older installation."
  ${EndIf}
register_done:
SectionEnd

Section /o "Start the watcher with a tray icon when I sign in" SEC_TRAY
  SetShellVarContext current
  CreateShortCut "$SMSTARTUP\Windows AppShots.lnk" "$INSTDIR\bin\AppshotCapture.exe" 'watch --state-root "$LOCALAPPDATA\WindowsAppshots" --tray true' "$INSTDIR\bin\AppshotCapture.exe"
  IfSilent tray_done
  Exec '"$INSTDIR\bin\AppshotCapture.exe" watch --state-root "$LOCALAPPDATA\WindowsAppshots" --tray true'
tray_done:
SectionEnd

!insertmacro MUI_FUNCTION_DESCRIPTION_BEGIN
  !insertmacro MUI_DESCRIPTION_TEXT ${SEC_CORE} "Install the Windows capture helper, Codex MCP plugin, documentation, and uninstaller."
  !insertmacro MUI_DESCRIPTION_TEXT ${SEC_CODEX} "Register this local installation as a Codex plugin marketplace and install the plugin."
  !insertmacro MUI_DESCRIPTION_TEXT ${SEC_TRAY} "Start the watcher at sign-in with a visible tray icon. The MCP server can otherwise start it headlessly when needed."
!insertmacro MUI_FUNCTION_DESCRIPTION_END

Function .onInit
  ${IfNot} ${RunningX64}
    MessageBox MB_ICONSTOP|MB_OK "Windows AppShots requires 64-bit Windows."
    Abort
  ${EndIf}
  ReadEnvStr $StateRoot "WINDOWS_APPSHOTS_STATE_ROOT"
  ${If} $StateRoot == ""
    StrCpy $StateRoot "$LOCALAPPDATA\WindowsAppshots"
  ${EndIf}
  ${GetParameters} $R0
  ClearErrors
  ${GetOptions} $R0 "/NOCODEX" $R1
  IfErrors code_option_done
  !insertmacro UnselectSection ${SEC_CODEX}
code_option_done:
  ClearErrors
  ${GetOptions} $R0 "/TRAYSTARTUP" $R1
  IfErrors tray_option_done
  !insertmacro SelectSection ${SEC_TRAY}
tray_option_done:
FunctionEnd

Section "Uninstall"
  SetShellVarContext current
  nsExec::ExecToStack '"$INSTDIR\bin\AppshotCapture.exe" stop --state-root "$LOCALAPPDATA\WindowsAppshots"'
  Pop $0
  Pop $1
  nsExec::ExecToStack '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "$INSTDIR\scripts\unregister-codex.ps1" -AppRoot "$INSTDIR"'
  Pop $0
  Pop $1

  Delete "$SMSTARTUP\Windows AppShots.lnk"
  Delete "$SMPROGRAMS\Windows AppShots\Windows AppShots watcher.lnk"
  Delete "$SMPROGRAMS\Windows AppShots\Open capture folder.lnk"
  Delete "$SMPROGRAMS\Windows AppShots\Uninstall Windows AppShots.lnk"
  RMDir "$SMPROGRAMS\Windows AppShots"

  Delete "$INSTDIR\bin\AppshotCapture.exe"
  Delete "$INSTDIR\mcp\server-lib.mjs"
  Delete "$INSTDIR\mcp\server.mjs"
  Delete "$INSTDIR\skills\capture-windows-appshot\SKILL.md"
  Delete "$INSTDIR\.agents\plugins\marketplace.json"
  Delete "$INSTDIR\.codex-plugin\plugin.json"
  Delete "$INSTDIR\assets\branding\app-icon-256.png"
  Delete "$INSTDIR\scripts\register-codex.ps1"
  Delete "$INSTDIR\scripts\unregister-codex.ps1"
  Delete "$INSTDIR\.mcp.json"
  Delete "$INSTDIR\package.json"
  Delete "$INSTDIR\README.md"
  Delete "$INSTDIR\CONTRIBUTING.md"
  Delete "$INSTDIR\SECURITY.md"
  Delete "$INSTDIR\PRIVACY.md"
  Delete "$INSTDIR\CODE_SIGNING.md"
  Delete "$INSTDIR\LICENSE"
  Delete "$INSTDIR\uninstall.exe"

  RMDir "$INSTDIR\bin"
  RMDir "$INSTDIR\mcp"
  RMDir "$INSTDIR\skills\capture-windows-appshot"
  RMDir "$INSTDIR\skills"
  RMDir "$INSTDIR\.agents\plugins"
  RMDir "$INSTDIR\.agents"
  RMDir "$INSTDIR\.codex-plugin"
  RMDir "$INSTDIR\assets\branding"
  RMDir "$INSTDIR\assets"
  RMDir "$INSTDIR\scripts"
  RMDir "$INSTDIR"

  DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_ID}"
  DeleteRegKey HKCU "Software\${APP_ID}"
  ; Capture bundles under LocalAppData\WindowsAppshots are deliberately retained.
SectionEnd

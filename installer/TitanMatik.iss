#ifndef BuildVersion
  #define BuildVersion "0.0.0"
#endif
[Setup]
AppId={{973DB70F-DF7C-4CB7-9E9C-F28CD3468540}
AppName=TitanMatik
SetupIconFile=TitanMatik.ico
AppVersion={#BuildVersion}
DefaultDirName={localappdata}\TitanMatik
AppendDefaultDirName=no
DefaultGroupName=TitanMatik
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
DisableDirPage=no
DisableReadyPage=yes
UsePreviousAppDir=yes
OutputDir=..\build\installer
OutputBaseFilename=TitanMatik_Setup
Compression=lzma2
SolidCompression=yes
CloseApplications=no
RestartApplications=no
Uninstallable=no
WizardStyle=modern
SetupLogging=yes
[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
[Messages]
russian.SelectDirDesc=Выберите папку TitanMatik
russian.SelectDirLabel3=Для обновления укажите папку, где уже находится HeroWarsBro.exe. Установщик заменит файлы программы и сохранит ваши настройки и лицензию. Для первой установки можно оставить предложенную папку.
[Run]
Filename: "{app}\HeroWarsBro.exe"; Description: "Запустить TitanMatik"; WorkingDir: "{app}"; Flags: nowait postinstall skipifsilent
[Files]
#include "payload.iss"
[Icons]
Name: "{userdesktop}\TitanMatik"; Filename: "{app}\HeroWarsBro.exe"; WorkingDir: "{app}"; IconFilename: "{app}\TitanMatik.ico"
Name: "{userprograms}\TitanMatik"; Filename: "{app}\HeroWarsBro.exe"; WorkingDir: "{app}"; IconFilename: "{app}\TitanMatik.ico"
[Registry]
Root: HKCU; Subkey: "Software\TitanMatik"; ValueType: string; ValueName: "InstallDir"; ValueData: "{app}"
[Code]
var BackupPath: String; Completed: Boolean; Started: Boolean; Failed: Boolean;
    BackupComplete: Boolean; OriginallyAbsent: TArrayOfString;
    InstallCandidates: TStringList; ChooseInstall: TInputOptionWizardPage;
    AutoInstallFound: Boolean;
    InstallIntent: TInputOptionWizardPage; LocateLegacy: Boolean;
type
  TProcessEntry = record
    Size, Usage, ProcessId, DefaultHeapId, ModuleId, Threads, ParentProcessId: LongWord;
    Priority: Integer;
    Flags: LongWord;
    ExeFile: array[0..259] of Char;
  end;
  TBackupFindData = record
    Attributes: LongWord;
    CreationTime, LastAccessTime, LastWriteTime: TFileTime;
    SizeHigh, SizeLow, Reserved0, Reserved1: LongWord;
    FileName: array[0..259] of Char;
    AlternateName: array[0..13] of Char;
  end;
function BackupFindFirst(Name: String; var Data: TBackupFindData): LongWord;
  external 'FindFirstFileW@kernel32.dll stdcall';
function BackupFindNext(Handle: LongWord; var Data: TBackupFindData): Boolean;
  external 'FindNextFileW@kernel32.dll stdcall';
function BackupFindClose(Handle: LongWord): Boolean;
  external 'FindClose@kernel32.dll stdcall';
function FileAttributes(Name: String): LongWord;
  external 'GetFileAttributesW@kernel32.dll stdcall';
function CreateToolhelp32Snapshot(Flags, ProcessId: LongWord): LongWord;
  external 'CreateToolhelp32Snapshot@kernel32.dll stdcall';
function Process32First(Handle: LongWord; var Entry: TProcessEntry): Boolean;
  external 'Process32FirstW@kernel32.dll stdcall';
function Process32Next(Handle: LongWord; var Entry: TProcessEntry): Boolean;
  external 'Process32NextW@kernel32.dll stdcall';
function CloseHandle(Handle: LongWord): Boolean;
  external 'CloseHandle@kernel32.dll stdcall';

procedure RememberOriginal(Relative: String);
var Attr: LongWord; ErrorCode, Count: Integer;
begin
  Attr := FileAttributes(ExpandConstant('{app}') + '\' + Relative);
  ErrorCode := DLLGetLastError;
  if Attr = $FFFFFFFF then begin
    if (ErrorCode <> 2) and (ErrorCode <> 3) then
      RaiseException('Cannot inspect original file: ' + Relative);
    Count := GetArrayLength(OriginallyAbsent);
    SetArrayLength(OriginallyAbsent, Count + 1);
    OriginallyAbsent[Count] := Relative;
  end else if (Attr and (FILE_ATTRIBUTE_DIRECTORY or $400)) <> 0 then
    RaiseException('Unexpected directory or link at payload path: ' + Relative);
end;

function WasOriginallyAbsent(Relative: String): Boolean;
var Index: Integer;
begin
  Result := False;
  for Index := 0 to GetArrayLength(OriginallyAbsent) - 1 do
    if CompareText(OriginallyAbsent[Index], Relative) = 0 then begin
      Result := True;
      exit;
    end;
end;

procedure RestoreFile(Relative: String);
var Dest, Old: String;
begin
  Dest := ExpandConstant('{app}') + '\' + Relative;
  Old := BackupPath + '\' + Relative;
  if BackupComplete and FileExists(Old) then begin
    if not FileCopy(Old, Dest, False) then begin
      Failed := True;
      Log('ROLLBACK FAILED: ' + Dest);
    end;
  end else if WasOriginallyAbsent(Relative) then begin
    if FileExists(Dest) and not DeleteFile(Dest) then begin
      Failed := True;
      Log('ROLLBACK DELETE FAILED: ' + Dest);
    end;
  end else begin
    Failed := True;
    Log('ROLLBACK ORIGINAL NOT DELETED: backup missing for ' + Dest);
  end;
end;

procedure RemoveDuplicateDesktopLinks(Directory: String);
var Found: TFindRec; Shell, Link: Variant; Path, Target, Args, CopyPath: String;
begin
  if not FindFirst(AddBackslash(Directory) + '*.lnk', Found) then exit;
  try
    repeat
      if CompareText(Found.Name, 'TitanMatik.lnk') <> 0 then begin
        Path := AddBackslash(Directory) + Found.Name;
        try
          Shell := CreateOleObject('WScript.Shell');
          { WScript shortcut filenames are limited by the Windows ANSI code page.
            Inspect a temporary ASCII filename; delete only the verified original. }
          CopyPath := ExpandConstant('{tmp}\inspect-shortcut.lnk');
          if not FileCopy(Path, CopyPath, False) then RaiseException('Cannot read shortcut');
          Link := Shell.CreateShortcut(GetShortName(CopyPath));
          Target := Link.TargetPath;
          Args := Link.Arguments;
          if (CompareText(Target, ExpandConstant('{app}\HeroWarsBro.exe')) = 0) or
            ((CompareText(ExtractFileName(Target), 'powershell.exe') = 0) and
             (CompareText(Found.Name, 'Обновить TitanMatik.lnk') = 0) and
             (Pos(Lowercase(ExpandConstant('{app}\TitanMatik.Update.ps1')), Lowercase(Args)) > 0)) then
            if not DeleteFile(Path) then Log('Unable to remove old application shortcut: ' + Path);
        except
          Log('Unable to inspect old application shortcut: ' + Path);
        end;
      end;
    until not FindNext(Found);
  finally
    FindClose(Found);
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssInstall then Started := True;
  #ifdef TestFault
  if CurStep = ssPostInstall then begin
    Failed := True;
    #ifdef TestMissingBackup
    DeleteFile(BackupPath + '\HeroWarsBro.exe');
    #endif
    RaiseException('TITANMATIK_TEST_FAULT');
  end;
  #endif
  if CurStep = ssDone then begin
    Completed := not Failed;
    if Completed then begin
      RemoveDuplicateDesktopLinks(ExpandConstant('{userdesktop}'));
      RemoveDuplicateDesktopLinks(ExpandConstant('{commondesktop}'));
    end;
    if Completed then
      if not SaveStringToFile(ExpandConstant('{app}\.titanmatik-installed.sha256'),
        GetSHA256OfFile(ExpandConstant('{srcexe}')), False) then
        Log('Unable to save installed update identity');
  end;
end;

function GetCustomSetupExitCode(): Integer;
begin
  Result := 0;
  if Failed then Result := 12;
end;

procedure DeinitializeSetup();
begin
  if Started and not Completed then begin
    Log('Restoring files from backup');
    #include "rollback.iss"
  end;
end;

function InitializeSetup(): Boolean;
begin
  Log('InitializeSetup entry');
  Result := True;
end;

function ExistingInstallation(Directory: String): Boolean;
begin
  Result := FileExists(AddBackslash(Directory) + 'HeroWarsBro.exe') and
    FileExists(AddBackslash(Directory) + 'e_sqlite3.dll') and
    FileExists(AddBackslash(Directory) + 'WebView2Loader.dll');
end;

procedure AddInstallation(Directory: String);
begin
  Directory := RemoveBackslashUnlessRoot(ExpandFileName(Directory));
  if ExistingInstallation(Directory) and (InstallCandidates.IndexOf(Directory) < 0) then
    InstallCandidates.Add(Directory);
end;

procedure FindShortcutInstallations(Directory: String; Depth: Integer);
var Found: TFindRec; Shell, Link: Variant; Target, CopyPath: String;
begin
  if (Depth > 4) or not DirExists(Directory) then exit;
  if FindFirst(AddBackslash(Directory) + '*', Found) then begin
    try
      repeat
        if (Found.Name <> '.') and (Found.Name <> '..') and
          ((Found.Attributes and $400) = 0) then begin
          if (Found.Attributes and FILE_ATTRIBUTE_DIRECTORY) <> 0 then
            FindShortcutInstallations(AddBackslash(Directory) + Found.Name, Depth + 1)
          else if CompareText(ExtractFileExt(Found.Name), '.lnk') = 0 then begin
            try
              Shell := CreateOleObject('WScript.Shell');
              CopyPath := ExpandConstant('{tmp}\inspect-shortcut.lnk');
              if not FileCopy(AddBackslash(Directory) + Found.Name, CopyPath, False) then
                RaiseException('Cannot read shortcut');
              Link := Shell.CreateShortcut(GetShortName(CopyPath));
              Target := Link.TargetPath;
              if CompareText(ExtractFileName(Target), 'HeroWarsBro.exe') = 0 then
                AddInstallation(ExtractFileDir(Target));
            except
              Log('Unable to inspect an application shortcut');
            end;
          end;
        end;
      until not FindNext(Found);
    finally
      FindClose(Found);
    end;
  end;
end;

procedure InitializeWizard();
var Saved: String; Index: Integer;
begin
  Log('InitializeWizard entry');
  AutoInstallFound := False;
  InstallCandidates := TStringList.Create;
  InstallCandidates.CaseSensitive := False;
  if ExpandConstant('{param:DIR|}') = '' then begin
    if RegQueryStringValue(HKCU, 'Software\TitanMatik', 'InstallDir', Saved) and
      ExistingInstallation(Saved) then begin
      AddInstallation(Saved);
    end else begin
      AddInstallation(ExpandConstant('{src}'));
      FindShortcutInstallations(ExpandConstant('{userdesktop}'), 0);
      FindShortcutInstallations(ExpandConstant('{userprograms}'), 0);
      FindShortcutInstallations(ExpandConstant('{commondesktop}'), 0);
      FindShortcutInstallations(ExpandConstant('{commonprograms}'), 0);
      AddInstallation(ExpandConstant('{localappdata}\TitanMatik'));
      AddInstallation(ExpandConstant('{sd}\Games\HeroWars'));
      AddInstallation(ExpandConstant('{sd}\HeroWars'));
    end;
    if InstallCandidates.Count = 1 then begin
      WizardForm.DirEdit.Text := InstallCandidates[0];
      AutoInstallFound := True;
    end else if InstallCandidates.Count > 1 then begin
      ChooseInstall := CreateInputOptionPage(wpWelcome, 'Обновление TitanMatik',
        'Найдено несколько установленных копий',
        'Выберите копию для обновления. Настройки и лицензия останутся в её папке.', True, False);
      for Index := 0 to InstallCandidates.Count - 1 do
        ChooseInstall.Add(InstallCandidates[Index]);
      ChooseInstall.SelectedValueIndex := -1;
    end else begin
      InstallIntent := CreateInputOptionPage(wpWelcome, 'TitanMatik',
        'Установленная программа не найдена автоматически',
        'Для обновления старой версии выберите её существующую папку. Новая установка будет создана в стандартной папке пользователя.', True, False);
      InstallIntent.Add('Обновить уже установленную программу');
      InstallIntent.Add('Установить впервые');
      InstallIntent.SelectedValueIndex := -1;
    end;
    if AutoInstallFound or (InstallCandidates.Count > 1) then begin
      WizardForm.NextButton.Caption := 'Обновить';
      WizardForm.FinishedHeadingLabel.Caption := 'TitanMatik обновлён';
    end;
  end;
  Log('InitializeWizard complete');
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := (PageID = wpSelectDir) and (AutoInstallFound or
    ((InstallCandidates <> nil) and (InstallCandidates.Count > 1)) or
    ((InstallIntent <> nil) and not LocateLegacy));
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  { Silent installations cannot answer custom pages. PrepareToInstall below
    rejects missing/ambiguous choices without displaying a blocking MsgBox. }
  if WizardSilent then exit;
  if (InstallIntent <> nil) and (CurPageID = InstallIntent.ID) then begin
    Result := InstallIntent.SelectedValueIndex >= 0;
    if not Result then begin
      MsgBox('Выберите обновление существующей программы или первую установку.', mbInformation, MB_OK);
      exit;
    end;
    LocateLegacy := InstallIntent.SelectedValueIndex = 0;
    if LocateLegacy then WizardForm.DirEdit.Text := ''
    else WizardForm.DirEdit.Text := ExpandConstant('{localappdata}\TitanMatik');
  end;
  if (CurPageID = wpSelectDir) and LocateLegacy and
    not ExistingInstallation(WizardDirValue) then begin
    MsgBox('В выбранной папке программа не найдена. Выберите папку установленного TitanMatik. Новая копия создана не будет.', mbInformation, MB_OK);
    Result := False;
  end;
  if (ChooseInstall <> nil) and (CurPageID = ChooseInstall.ID) then begin
    Result := ChooseInstall.SelectedValueIndex >= 0;
    if Result then
      WizardForm.DirEdit.Text := InstallCandidates[ChooseInstall.SelectedValueIndex]
    else MsgBox('Выберите копию программы для обновления.', mbInformation, MB_OK);
  end;
end;

function Running(): Boolean;
var Handle: LongWord; Entry: TProcessEntry; Name: String; Index: Integer;
begin
  { Fail closed if process enumeration is unavailable. Never kill the application. }
  Result := True;
  Handle := CreateToolhelp32Snapshot(2, 0);
  if Handle = $FFFFFFFF then exit;
  try
    Entry.Size := SizeOf(Entry);
    if not Process32First(Handle, Entry) then exit;
    repeat
      Name := '';
      for Index := 0 to 259 do begin
        if Entry.ExeFile[Index] = #0 then break;
        Name := Name + Entry.ExeFile[Index];
      end;
      if CompareText(Name, 'HeroWarsBro.exe') = 0 then exit;
    until not Process32Next(Handle, Entry);
    Result := False;
  finally
    CloseHandle(Handle);
  end;
end;

function CopyTree(Source, Target: String): Boolean;
var Rec: TBackupFindData; Handle, Attr: LongWord;
    Name: String; Index, ErrorCode: Integer; More: Boolean;
begin
  Result := False;
  Attr := FileAttributes(Source);
  if (Attr = $FFFFFFFF) or ((Attr and FILE_ATTRIBUTE_DIRECTORY) = 0) or ((Attr and $400) <> 0) then exit;
  if not ForceDirectories(Target) then exit;
  Handle := BackupFindFirst(Source + '\*', Rec);
  ErrorCode := DLLGetLastError;
  if Handle = $FFFFFFFF then begin
    { Only ERROR_FILE_NOT_FOUND denotes an empty, already verified directory. }
    Result := ErrorCode = 2;
    if not Result then Log('Backup enumeration failed: error=' + IntToStr(ErrorCode) + ' ' + Source);
    exit;
  end;
  try
    repeat
      Name := '';
      for Index := 0 to 259 do begin
        if Rec.FileName[Index] = #0 then break;
        Name := Name + Rec.FileName[Index];
      end;
      if (Name <> '.') and (Name <> '..') then begin
        if (Rec.Attributes and $400) <> 0 then exit;
        if (Rec.Attributes and FILE_ATTRIBUTE_DIRECTORY) <> 0 then begin
          if not CopyTree(Source + '\' + Name, Target + '\' + Name) then exit;
        end else begin
          if not FileCopy(Source + '\' + Name, Target + '\' + Name, True) then exit;
          if GetSHA256OfFile(Source + '\' + Name) <> GetSHA256OfFile(Target + '\' + Name) then exit;
        end;
      end;
      More := BackupFindNext(Handle, Rec);
      ErrorCode := DLLGetLastError;
      #ifdef TestBackupNextFailure
      More := False;
      ErrorCode := 5;
      #endif
      if not More then begin
        { ERROR_NO_MORE_FILES is the only successful end of enumeration. }
        Result := ErrorCode = 18;
        if not Result then Log('Backup enumeration failed: error=' + IntToStr(ErrorCode) + ' ' + Source);
        exit;
      end;
    until False;
  finally
    BackupFindClose(Handle);
  end;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var Backup: String;
begin
  Result := '';
  BackupComplete := False;
  BackupPath := '';
  SetArrayLength(OriginallyAbsent, 0);
  Log('PrepareToInstall entry');
  if (InstallIntent <> nil) and (InstallIntent.SelectedValueIndex < 0) then begin
    Result := 'Установка не найдена. Выберите обновление или первую установку в окне установщика.';
    exit;
  end;
  if LocateLegacy and not ExistingInstallation(ExpandConstant('{app}')) then begin
    Result := 'Существующая программа не найдена в выбранной папке. Создание второй копии отменено.';
    exit;
  end;
  if (CompareText(RemoveBackslashUnlessRoot(ExpandConstant('{app}')), ExpandConstant('{userdesktop}')) = 0) or
     (CompareText(RemoveBackslashUnlessRoot(ExpandConstant('{app}')), ExpandConstant('{userdocs}')) = 0) or
     (CompareText(RemoveBackslashUnlessRoot(ExpandConstant('{app}')), ExpandConstant('{%USERPROFILE}\Downloads')) = 0) or
     (CompareText(RemoveBackslashUnlessRoot(ExpandConstant('{app}')), ExpandConstant('{%USERPROFILE}')) = 0) then begin
    Result := 'Установка прямо в рабочий стол, загрузки или документы запрещена. Используйте отдельную папку программы.';
    exit;
  end;
  if (ExpandConstant('{param:DIR|}') = '') and (InstallCandidates.Count > 1) then
    if (ChooseInstall = nil) or (ChooseInstall.SelectedValueIndex < 0) then begin
      Result := 'Найдено несколько копий TitanMatik. Выберите обновляемую копию в окне установщика.';
      exit;
    end;
  if AutoInstallFound and not ExistingInstallation(ExpandConstant('{app}')) then begin
    Result := 'Найденная установка изменилась. Запустите обновление повторно.';
    exit;
  end;
  if Length(RemoveBackslashUnlessRoot(ExpandConstant('{app}'))) <= 3 then begin
    Result := 'Выберите отдельную папку TitanMatik, а не корень диска.';
    exit;
  end;
  if Running() then begin
    Result := 'Закройте HeroWarsBro.exe (TitanMatik) и повторите установку.';
    exit;
  end;
  #include "snapshot.iss"
  if DirExists(ExpandConstant('{app}')) then begin
    Backup := ExpandConstant('{app}') + '.backup-' + GetDateTimeString('yyyymmdd-hhnnss', '-', ':');
    if DirExists(Backup) or not CopyTree(ExpandConstant('{app}'), Backup) then
      Result := 'Не удалось создать полную резервную копию. Обновление остановлено.'
    else begin BackupPath := Backup; BackupComplete := True; Log('Backup saved and verified: ' + Backup); end;
  end;
end;

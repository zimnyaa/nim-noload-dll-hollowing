# nim-noload-dll-hollowing
Unused DLL hollowing PoC in Nim
## tl;dr
> **update:** add unhooking
This repo accompanies a post on https://tishina.in/execution/nim-noload-dll-hollowing

It is essentially a Nim port of https://www.netero1010-securitylab.com/eavsion/alternative-process-injection with RW/RX mapping, syscalls, and PPID spoofing, partially taken from @ajpc500 examples.

## build
Proudly built with `nim c filename.nim` and no additional flags.

## usage
`module_scanner.exe <path_to_exe>` to get available modules.

Then, modify the process name, shellcode and the module name to stomp in `noload_dllhollow.nim`.

# credits
@[netero-1010](https://github.com/netero1010) for the original technique
@[ajpc500](https://github.com/byt3bl33d3r), @[khchen](https://github.com/khchen) and @[byt3bl33d3r](https://github.com/ajpc500) for the amazing work on Nim Windows interfacing and offensive tradecraft (I bet you guys are credited on any Nim-related repo)

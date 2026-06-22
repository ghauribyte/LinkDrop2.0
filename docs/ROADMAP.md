# Roadmap

## Phases

| Phase | Goal | What to build | Status |
|---|---|---|---|
| 1 | Core discovery | Devices find each other on the network, console logs only, no GUI | Not started |
| 2 | Basic transfer | Send/receive a file over TCP between two devices, no encryption yet | Not started |
| 3 | Security | Add TLS, add device verification before transfer | Not started |
| 4 | GUI | Build device list, send/accept popup, progress bar | Not started |
| 5 | Polish | Pause/resume, folder support, transfer history, error handling | Not started |
| 6 | Cross-platform testing | Test on Windows, Mac, Linux, fix network edge cases | Not started |

Suggested order: finish Phases 1-2 as a command-line tool first. Prove discovery and transfer work before adding the GUI.

## Feature List
- Auto-find nearby devices on the same Wi-Fi, no manual setup
- Device list with name/icon
- Send one or more files to a picked device
- Accept/reject popup on the receiving side
- Progress bar (% done, speed, time left)
- Pause, resume, or cancel a transfer
- Send whole folders, not just single files
- Transfer history (sent/received log)

## Non-Functional Goals
- Encrypted transfer (TLS) + device verification
- Full local network speed, no slow cloud relay
- Recovers if Wi-Fi drops mid-transfer
- 1-2 clicks, no account or login
- Works the same on Windows, Mac, Linux
- Handles multiple transfers and devices at once
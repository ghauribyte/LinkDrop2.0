# TODO — LinkDrop

---

## Phase 1: Core Discovery ✅

- [x] `broadcaster.dart` sends a packet every 2 seconds with name + id
- [x] `listener.dart` receives and prints found devices with the correct IP
- [x] No duplicate spam for the same device in listener output
- [x] Confirmed working between two separate physical devices on the same Wi-Fi *(still needs real-device test)*
- [x] Ctrl+C cleanly stops both scripts, no crash

---

## Phase 2: Basic TCP File Transfer

This is the exact spec for the second piece of code. No GUI, no TLS yet — just two plain Dart CLI scripts that prove a file can move from one device to another over TCP on the same Wi-Fi. Write the code, then bring it back here for review against this list.

### File 1: `receiver.dart`

What it should do:
1. Accept a target directory path as a command-line argument (e.g. `dart receiver.dart ./received/`)
2. Bind a TCP server socket to port `7979` on all interfaces (`InternetAddress.anyIPv4`)
3. Print its own local IP address and port on startup so the sender knows where to connect
4. Accept one incoming connection at a time
5. Read the file metadata header first (see Wire Protocol below)
6. Open a new file at `<target_dir>/<filename>` and stream incoming bytes into it
7. Print progress to console: bytes received vs total size, e.g. `Receiving photo.jpg — 1.2 MB / 4.5 MB`
8. Print `Transfer complete: photo.jpg` when done
9. Go back to listening for the next connection (loop, don't exit after one file)
10. Handle Ctrl+C cleanly — close server socket, exit 0

### File 2: `sender.dart`

What it should do:
1. Accept two command-line arguments: receiver IP and file path (e.g. `dart sender.dart 192.168.1.42 ./photo.jpg`)
2. Validate the file exists before connecting — exit with a clear error if not
3. Open a TCP connection to `<receiver_ip>:7979`
4. Send the file metadata header first (see Wire Protocol below)
5. Stream the file bytes over the socket
6. Print progress to console: bytes sent vs total size, e.g. `Sending photo.jpg — 1.2 MB / 4.5 MB`
7. Print `Transfer complete: photo.jpg` when done
8. Close the connection cleanly

### Wire Protocol (both files must agree on this)

The sender sends a fixed-format header before the file bytes, so the receiver knows the filename and size:

```
[4 bytes]  Header length as a big-endian uint32
[N bytes]  JSON header:
           {
             "filename": "<original filename, no path>",
             "size": <file size in bytes as integer>
           }
[remaining bytes]  Raw file content
```

Steps:
1. Sender encodes the JSON header as UTF-8
2. Sender writes the 4-byte length prefix (big-endian), then the JSON bytes, then the raw file bytes
3. Receiver reads the 4-byte prefix first to know how many bytes the header is
4. Receiver decodes the JSON to get `filename` and `size`
5. Receiver reads exactly `size` bytes and writes them to disk

### How to test

1. Run `receiver.dart ./received/` in one terminal (or on one device)
2. Run `sender.dart <receiver-ip> <path-to-any-file>` in another terminal
3. Confirm the file appears in `./received/` and its contents match the original (use `md5sum` or `diff`)
4. Test with a small file first (a `.txt`), then a large file (100 MB+) to check streaming
5. Easiest first check: run both scripts on the same machine using `127.0.0.1` as the IP before trying two real devices

### Definition of done
- [x] `receiver.dart` starts, prints its IP + port, waits for a connection
- [x] `sender.dart` connects, sends the header + file bytes, prints progress
- [x] Received file matches the original exactly (byte-for-byte)
- [x] Progress output appears in both terminals during transfer
- [x] Large file (100 MB+) transfers without error or memory spike
- [x] Tested on the same machine first (loopback), then two physical devices
- [x] Ctrl+C on receiver closes cleanly, no crash

### Not in scope yet
- No TLS / encryption (Phase 3)
- No accept/reject prompt on the receiver (Phase 4 GUI)
- No integration with discovery scripts yet — IP is typed manually for now
- No folder support yet (Phase 5)
- No pause/resume (Phase 5)

---

Once both files are written, bring them back here. Review against this checklist and against DECISIONS.md (Decision 002: TCP sockets, no TLS yet) before moving to Phase 3.
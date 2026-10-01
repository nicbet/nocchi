import Darwin
import Foundation
import NocchiHookProtocol

// nocchi-hook <claude|codex>
//
// Run by Claude Code and Codex hooks. Forwards the hook's stdin to the nocchi app and exits 0,
// quietly and quickly, whatever happens: it must never delay or disturb the agent (some hooks'
// stdout becomes context for the model, so it prints nothing).

let agent = CommandLine.arguments.dropFirst().first ?? "claude"
var input = FileHandle.standardInput.readDataToEndOfFile()

// Large tool payloads (a file being written) aren't needed: drop them.
if input.count > HookMessage.maxInputBytes,
   var object = try? JSONSerialization.jsonObject(with: input) as? [String: Any] {
    for key in ["tool_input", "tool_response", "prompt", "last_assistant_message"] { object[key] = nil }
    input = (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
}

let environment = ProcessInfo.processInfo.environment.filter { HookMessage.environmentKeys.contains($0.key) }
let message = HookMessage(agent: agent, parentPID: getppid(), environment: environment, input: input)
guard var line = try? JSONEncoder().encode(message) else { exit(0) }
line.append(0x0A)

let fd = socket(AF_UNIX, SOCK_STREAM, 0)
guard fd >= 0 else { exit(0) }
var on: Int32 = 1
setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
var timeout = timeval(tv_sec: 0, tv_usec: 300_000)
setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

var address = sockaddr_un()
address.sun_family = sa_family_t(AF_UNIX)
let path = ProcessInfo.processInfo.environment["NOCCHI_HOOK_SOCKET"] ?? HookMessage.socketPath()
guard path.utf8.count < MemoryLayout.size(ofValue: address.sun_path) else { exit(0) }
withUnsafeMutableBytes(of: &address.sun_path) { raw in
    raw.copyBytes(from: path.utf8)
    raw[path.utf8.count] = 0
}
let connected = withUnsafePointer(to: &address) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
}
// nocchi isn't running: nothing to do.
guard connected == 0 else { exit(0) }
_ = line.withUnsafeBytes { write(fd, $0.baseAddress!, $0.count) }
close(fd)
exit(0)

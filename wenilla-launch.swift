import Foundation

// wenilla local-trial launcher — a native arm64 binary that drives this repo's
// `realmctl` so a Mac user does not have to type the boot sequence by hand.
//
// It cannot replace Docker or the game data: it checks both, then runs extract
// (once), up, waits for readiness and opens the play page. Build:
//   swiftc -O wenilla-launch.swift -o wenilla-launch
// Run:
//   ./wenilla-launch                       # uses the compiled-in repo path
//   ./wenilla-launch /some/other/checkout  # override

let compiledRepo = "/Users/kubbo.ai/github/wenilla-realm"
let arguments = CommandLine.arguments
let repo = arguments.count > 1 ? arguments[1] : compiledRepo
let extractedMarker = repo + "/.local-trial-extracted"

func emit(_ line: String) {
    FileHandle.standardOutput.write(Data((line + "\n").utf8))
}

/// Run `command` through bash -lc, optionally with its output captured.
/// Long commands inherit the terminal so their progress is visible live.
func shell(_ command: String, capture: Bool = false) -> (status: Int32, text: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = ["-lc", "cd \"\(repo)\" && \(command)"]
    let pipe = Pipe()
    if capture {
        process.standardOutput = pipe
        process.standardError = pipe
    }
    do {
        try process.run()
    } catch {
        return (-1, "\(error)")
    }
    if capture {
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        return (process.terminationStatus, text)
    }
    process.waitUntilExit()
    return (process.terminationStatus, "")
}

func fail(_ message: String) -> Never {
    emit("ERROR: \(message)")
    exit(1)
}

emit("wenilla local-trial launcher")
emit("repo: \(repo)")

// 1. The checkout and its config.
guard FileManager.default.fileExists(atPath: repo + "/realmctl") else {
    fail("realmctl not found — first argument must be a wenilla-realm checkout")
}
guard FileManager.default.fileExists(atPath: repo + "/.env") else {
    fail(".env missing — copy .env.local-trial.example to .env and fill your passwords first")
}

// 2. Docker daemon and the compose plugin. Try to wake OrbStack/Docker once.
var (status, _) = shell("docker version --format '{{.Server.Os}}/{{.Server.Arch}}'", capture: true)
if status != 0 {
    emit("Docker daemon is down — trying to start OrbStack / Docker …")
    _ = shell("open -a OrbStack 2>/dev/null || open -a Docker 2>/dev/null || true", capture: true)
    for _ in 0..<30 {
        sleep(2)
        (status, _) = shell("docker version --format '{{.Server.Os}}/{{.Server.Arch}}'", capture: true)
        if status == 0 { break }
    }
}
guard status == 0 else {
    fail("Docker is still not responding — start OrbStack or Docker Desktop by hand, then rerun")
}
let (_, arch) = shell("docker version --format '{{.Server.Os}}/{{.Server.Arch}}'", capture: true)
emit("Docker up: \(arch.trimmingCharacters(in: .whitespacesAndNewlines))")

(status, _) = shell("docker compose version", capture: true)
guard status == 0 else {
    fail("the Docker Compose v2 plugin is missing — install it, then rerun")
}

// 3. The operator's game data, read from .env rather than hard-coded.
let (envStatus, envText) = shell("cat .env", capture: true)
guard envStatus == 0 else { fail("cannot read .env") }
var clientData = ""
for line in envText.split(separator: "\n") {
    if line.hasPrefix("CLIENT_DATA=") {
        clientData = String(line.dropFirst("CLIENT_DATA=".count)).trimmingCharacters(in: .whitespaces)
    }
}
guard !clientData.isEmpty else { fail("CLIENT_DATA is not set in .env") }
var isDirectory: ObjCBool = false
guard FileManager.default.fileExists(atPath: clientData, isDirectory: &isDirectory), isDirectory.boolValue else {
    fail("CLIENT_DATA is not a directory: \(clientData)")
}
let mpq = shell("find \"\(clientData)\" -maxdepth 2 -iname '*.mpq' | wc -l", capture: true).text
    .trimmingCharacters(in: .whitespacesAndNewlines)
guard mpq != "0" else { fail("no .MPQ archives under CLIENT_DATA — point .env at your 1.12.1 Data/") }
emit("client data: \(clientData) (\(mpq) archives)")

// 4. Server map data, once. mmaps take hours under amd64 emulation on Apple Silicon.
if FileManager.default.fileExists(atPath: extractedMarker) {
    emit("map data: already extracted (marker present) — skipping")
} else {
    emit("map data: extracting — this can take hours; the terminal stays live")
    let (extractStatus, _) = shell("./realmctl extract")
    guard extractStatus == 0 else { fail("realmctl extract failed — see the output above") }
    FileManager.default.createFile(atPath: extractedMarker, contents: nil)
    emit("map data: extracted; marker written")
}

// 5. Start the stack.
emit("starting the stack …")
let (upStatus, _) = shell("./realmctl up")
guard upStatus == 0 else { fail("realmctl up failed — see the output above") }

// 6. Wait for the play page to answer (healthz is outside the setup gate).
emit("waiting for https://localhost/healthz …")
var ready = false
for _ in 0..<180 {
    let (_, codeText) = shell("curl -sk --max-time 3 -o /dev/null -w '%{http_code}' https://localhost/healthz", capture: true)
    if codeText.trimmingCharacters(in: .whitespacesAndNewlines) == "200" {
        ready = true
        break
    }
    sleep(5)
}
guard ready else {
    fail("healthz did not come up in 15 minutes — check `./realmctl logs mangosd`")
}

// 7. Show the one-time setup token if the wizard has not consumed it, then open the page.
let (tokenStatus, token) = shell("docker compose exec -T realm cat /state/setup-token", capture: true)
if tokenStatus == 0 && !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
    emit("SETUP TOKEN: \(token.trimmingCharacters(in: .whitespacesAndNewlines))")
} else {
    emit("no setup token — the wizard has already run, or the token was deleted")
}
emit("opening https://localhost/ …")
_ = shell("open https://localhost/")
emit("done. If the page warns about the self-signed localhost certificate, accept it once.")

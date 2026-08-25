# Delegated Debugging: Codex exec_command on iSH Still Gives `exited -1 in 0ms` (Unresolved After v2 Patch)

> Target audience: Computer-side codex/agent. You do not have physical iSH hardware, so debugging is conducted via "source code analysis + remote execution of experiments on real hardware".
> You can run any experiment on real iSH hardware through the petitioner of this document (Minis agent).
> Generated: 2026-08-24.

---

## 0. Summary in One Sentence

Running `codex-cli 0.139.0` on iPhone iSH (iOS Linux emulator, Alpine 3.21 aarch64).
**Non-TTY `exec_command` fails 100% of the time: `exited -1 in 0ms` (child process immediately killed by signal, zero output).**
Two rounds of patches have been applied (`PR_SET_PDEATHSIG` EINVAL tolerance + tokio forced SIGCHLD fallback); **neither resolved the issue**. Exec with `tty: true` works completely normally. Plain Q&A and web search are unaffected.

---

## 1. Confirmed Facts (All Empirically Measured on iSH)

### 1.1 Syscall Layer (Empirically Measured via C / Python ctypes)

| syscall | iSH Behavior |
|---|---|
| `prctl(PR_SET_PDEATHSIG, SIGTERM)` | ❌ **EINVAL** (errno 22) — iSH only supports `PR_SET_KEEPCAPS` / `PR_SET_NAME` |
| `prctl(PR_SET_NAME)` | ✅ Normal |
| `setsid()` | ✅ Normal |
| `setpgid()` | ⚠️ EPERM when shell process group leader (standard Linux behavior) |
| `pidfd_open(pid, 0)` | ✅ Succeeded (returns fd) |
| `pidfd_open(pid, PIDFD_NONBLOCK)` | ✅ Succeeded |
| `poll()` on pidfd (live child) | ✅ 0 events (correct) |
| `poll()` on pidfd (dead child) | ✅ POLLIN (correct) |
| `epoll_create1 + epoll_ctl(ADD, pidfd) + epoll_pwait` | ✅ All normal (live: 0 events / dead: 1 event) |
| `waitid(P_PID, ...)` (traditional) | ✅ Normal |
| **`waitid(P_PIDFD, ...)`** | ❌ **Permanently EINVAL** (regardless of WNOHANG/WEXITED, live/dead) |
| `waitpid()` | ✅ Normal (though gcc exhibits intermittent "Interrupted system call" — EINTR suspected) |
| `fork()` (single thread) | ✅ Normal |
| `fork()` (multithreaded parent) | ✅ Normal (5/5) |
| `execv()` custom argv[0] | ✅ Normal |
| `strace` | ❌ PTRACE_SETOPTIONS EINVAL (no ptrace support) |
| `bash -i` | ❌ exit 2 (PTY job control incomplete) |

### 1.2 Full pre_exec Sequence Simulation (C)

Using C to fully simulate codex's spawn sequence:
`fork -> setsid -> prctl(PDEATHSIG tolerating EINVAL) -> getppid check -> execve(custom argv[0])`
- Single thread: **8/8 survived** (normal)
- Multithreaded parent (3 pthreads): **5/5 survived** (normal)

-> **C simulation of codex's spawn steps works completely normally on iSH**. The difference must reside somewhere in the Rust std / tokio layer.

### 1.3 Codex Empirical Measurements

| Command | Result |
|---|---|
| `codex exec "reply OK"` (pure response) | ✅ Normal |
| `codex exec` + exec_command non-TTY | ❌ `exited -1 in 0ms` (even `sleep 2; echo hi` dies in 1ms) |
| `codex exec` + exec_command `tty: true` | ✅ Normal output |
| web-search (DeepSeek native `web_search` tool) | ✅ Normal |
| session resume / memory | ✅ Normal |

### 1.4 Error Semantics (Source Code Confirmed)

codex 0.139.0 `core/src/exec.rs:770`:
```rust
let mut exit_code = raw_output.exit_status.code().unwrap_or(-1);
```
-> `-1` = `ExitStatus::code() == None` = **child process terminated by signal** (WIFSIGNALED), not exit code -1.

---

## 2. Two Patch Rounds Applied (Both Unresolved)

### Patch v1 (Built and Installed)
In `codex-rs/utils/pty/src/process_group.rs` -> `set_parent_death_signal()`:
```rust
pub fn set_parent_death_signal(parent_pid: libc::pid_t) -> io::Result<()> {
    if unsafe { libc::prctl(libc::PR_SET_PDEATHSIG, libc::SIGTERM) } == -1 {
        let err = io::Error::last_os_error();
        if err.raw_os_error() != Some(libc::EINVAL) {   // iSH: tolerate EINVAL
            return Err(err);
        }
    }
    if unsafe { libc::getppid() } != parent_pid {
        unsafe { libc::raise(libc::SIGTERM); }
    }
    Ok(())
}
```
**Result**: `CreateProcess EINVAL` error disappeared, but exec still died (`exited -1 in 0ms`).

### Patch v2 (Built and Installed, 2026-08-24)
At the start of `Pidfd::open()` in vendored tokio 1.52.3 `src/process/unix/pidfd_reaper.rs`:
```rust
// iSH: pidfd_open() succeeds but waitid(P_PIDFD) returns EINVAL,
// so the pidfd reap path can never obtain the exit status -> child
// gets killed by kill_on_drop. Force SIGCHLD fallback path.
return None;
```
-> tokio should switch to the SIGCHLD fallback reaper.
**Result**: **Still `exited -1 in 0ms`**. The SIGCHLD fallback path also fails on iSH.

### Comparison of the Two Binaries (strings Analysis)

| | v1 (`923a31a9...`) | v2 (`f626dda1...`) |
|---|---|---|
| tokio source path | `registry/src/.../tokio-1.52.3/...` | `vendor/tokio/src/...` (confirmed vendored+patch active) |
| pidfd strings count | 4 | 4 |
| waitid strings count | 2 | 1 (decreased — consistent with v2 patch) |
| Rust std pidfd.rs | Present | Present |

**Note**: Both binaries contain Rust std's `library/std/src/sys/pal/unix/linux/pidfd.rs` and `pidfd_spawnp` strings — **Rust std 1.95.0 itself might use a pidfd path** (`pidfd_spawnp`!).

---

## 3. Latest Hypotheses (Needing Assessment)

### Hypothesis A: Rust std 1.95.0 itself uses a pidfd spawn path
- Strings reveal `pidfd_spawnp succeeded but the child's PID could not be obtained`.
- **Could Rust 1.95's std::process::Command default to `pidfd_spawnp` glibc/musl extensions**?
- If std uses `pidfd_spawnp` and iSH's implementation is buggy -> child dies immediately.
- This is independent of tokio — even if tokio falls back to SIGCHLD, std's underlying spawn still uses `pidfd_spawnp`.
- **Investigation direction**: Check if Rust 1.95.0 std's `library/std/src/sys/pal/unix/process/process_unix.rs` uses `pidfd_spawnp` and under what conditions.

### Hypothesis B: SIGCHLD delivery is incomplete on iSH
- tokio's SIGCHLD fallback relies on signal-driven notifications (`Signal::signal(SIGCHLD)`).
- iSH has known signal delivery bugs (gcc's EINTR, ^C killing whole shell).
- If SIGCHLD does not arrive / arrives late / false reports -> tokio misjudges child state -> `kill_on_drop` mistakenly terminates child.
- **Investigation direction**: Write C test for SIGCHLD behavior on iSH (fork child + signal handler + timer).

### Hypothesis C: musl edition Rust std fork+exec has hidden issues on iSH
- Binary is musl (`aarch64-unknown-linux-musl`).
- musl's fork implementation under multithreaded parent uses `clone` + special handling.
- iSH may handle certain syscall combinations in musl fork improperly.
- **Investigation direction**: Compile multithreaded fork test with musl-gcc on iSH (not glibc edition).

### Hypothesis D: Combination of pipe fd + child immediate exit
- exec uses `stdin=/dev/null, stdout=pipe, stderr=pipe`.
- iSH behavior on pipe read/close after child death might be buggy.
- Prior C tests did not fully simulate this exact fd combination.
- **Investigation direction**: C test for `/dev/null stdin + pipe stdout/stderr + fork/exec + parent read pipe`.

---

## 4. Reproduction Steps (Real iSH Device)

```sh
# 1. Confirm environment
/var/minis/shared/codex-lab/codex-0139/codex --version   # codex-cli 0.139.0
sha256sum /var/minis/shared/codex-lab/codex-0139/codex   # f626dda1... (v2)

# 2. Confirm bridge is reachable
curl -fsS http://127.0.0.1:8787/ >/dev/null && echo bridge-ok

# 3. Reproduce bug
cd /root
CODEX_HOME=/var/minis/shared/codex-lab/codex-home \
/var/minis/shared/codex-lab/codex-0139/codex exec --skip-git-repo-check \
  "Must use exec_command to run echo hi, then report the output"

# Expected: Output contains "exited -1 in 0ms", no "hi"
# tty:true control group (should succeed):
#   "Always pass tty:true with exec_command. Run echo hi"
```

---

## 5. Experiments You Can Request Us to Run on Real iSH Hardware

We currently have the capability to run:
1. **C programs** (gcc is available; note that gcc itself encounters intermittent EINTR failures, simply retry).
2. **python3 ctypes direct syscall calls** (most reliable, already used to test pidfd/waitid/epoll).
3. **codex binary with `RUST_LOG=trace`** (inspect spawn flow).
4. **strings / disassemble binary** (no objdump? can install binutils).
5. **Run any test programs you write** (you provide source code, we compile/execute on iSH — or you build musl binaries for us to run).

Whatever data you need, specify in the document "Please run X on iSH", and I will execute and return full output.

---

## 6. Key Source Code Locations (codex 0.139.0 + tokio 1.52.3 + Rust 1.95.0)

```
codex 0.139.0:
  codex-rs/core/src/spawn.rs               ← spawn_child_async (arg0/pre_exec/kill_on_drop)
  codex-rs/core/src/exec.rs:770            ← exit_code unwrap_or(-1)
  codex-rs/utils/pty/src/process_group.rs  ← set_parent_death_signal (already patched)
tokio 1.52.3:
  tokio/src/process/unix/mod.rs            ← build_child (PidfdReaper vs SignalReaper selection)
  tokio/src/process/unix/pidfd_reaper.rs   ← Pidfd::open (v2 forced return None)
  tokio/src/process/unix/reap.rs           ← SignalReaper (SIGCHLD fallback path)
  tokio/src/process/unix/orphan.rs         ← OrphanQueue / kill_on_drop
Rust std 1.95.0:
  library/std/src/sys/pal/unix/process/process_unix.rs  ← Command::spawn main logic
  library/std/src/sys/pal/unix/linux/pidfd.rs           ← PidFd (waitid consumer)
  library/std/src/sys/pal/unix/process/process_common.rs
```

Available on real iSH device: `/var/minis/mounts/Codex-cli/codex-rs/` (codex source, `main 343074d`), `/tmp/tokio-1.52.3/` (tokio source, extracted).

---

## 7. Existing Debug Logs (Real iSH Device)

```
/var/minis/shared/codex-lab/debug-report-20260823.md  ← v1
/var/minis/shared/codex-lab/debug-report-v2.md        ← v2
/var/minis/shared/codex-lab/debug-report-v3.md        ← v3 (includes EINTR clues and gcc observations)
/var/minis/shared/codex-lab/investigation-einval.txt  ← first external agent investigation
```

---

## 8. Expected Output

1. **Assess which hypothesis is most plausible** (A/B/C/D or others you discover).
2. **Provide concrete experiment instructions** (write C source / Python script / specify commands to run).
3. We execute and return results -> you determine the next step.
4. Final goal: find out "on iSH, what signal does codex non-TTY exec child receive, and who sends it" — ideally with a minimal Rust reproducer.

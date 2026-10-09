# Prepared engine clock context

This module reconstructs the measured arm64 `GT_Ticks` calculation and the
prepared time-signature, samples-per-tick and tempo descriptor values. It is an
independent scalar component. Actual application clock production, queued
delivery, live project/voice scheduling and whole-plugin equivalence remain open.

`ticks` validates the prepared context and changes only the first double of a
caller-owned time packet. The second double remains untouched, including NaN
payload bits. The cached branch uses the measured cached tick value. An active
sender or future flag selects current tick plus sample position minus fractional
position, divided by samples per tick; this is clamped to the minimum tick, then
sender latency divided by samples per tick is subtracted. Requested local
rounding uses nearest-even, keeps the low 32 bits and, only in song mode 1,
subtracts the local start modulo 2^32. An optional nonzero input sample offset
is divided by samples per tick and added after that transformation.
The shared rounded-word helper uses `rint`, matching the original `FRINTX`
inexact flag for the focused finite nearest-even rounding cases.

The successful API domain requires finite cached ticks, fractional sample
position and input sample-offset magnitudes at most 2^52, samples per tick in
[1, 2^32], and nonnegative int32 latency. Tick, position, minimum, local-start and
song-mode fields use int32 storage. Valid C++ objects and their borrowed pointers
must remain alive during a call. Strict separate floating operations,
nearest-even rounding and gradual underflow are required. The implementation
allocates nothing, invokes no callbacks and accesses no engine globals. Invalid
prepared scalar inputs leave both output words unchanged. This safe rejection
contract is independently defined; invalid original host calls are not tested.

`delivery` builds prepared scalar descriptors. The direct engine producer sends
dispatcher 14 with a three-int32 time-signature packet, then dispatcher 20 with
signed-extended float samples-per-tick bits. The separate tempo producer sends
event 0 with float tempo bits and rounded samples-per-tick modulo 2^32 flags,
then dispatcher 20. Its context requires rates 8000..384000, positive signature
fields at most 1024, PPQ 4..2^20, finite tempo in (0, 1000], and the clock domain
above. The rate field is a prepared copy: the actual loader's dispatcher-4 rate
producer is mapped statically and is not executed by this fixture. No native
clock recomputation, manager, GUI, audio rate transition or scheduler is rebuilt.

The native fixture pins the installed universal engine hash and refuses any
executable architecture other than macOS arm64. It calls the intact C++ host
adapter and Pascal `TFruityHost` tick-time provider under controlled sender
fields and loaded-process scalar globals. It compares 12,064 tick cases: cached,
active-sender and future branches, minimum clamping, latency, input offsets,
rounding, local subtraction, signed zero, nearest-even ties and low-32-bit
wrapping. Every first-double result is bit-exact; the second time word and
nonzero outer guards survive. The API domain is broader than this finite corpus.

A further 6,000 descriptor fixtures execute the intact `TExPlugin` direct
producer functions and its interface-resolution helper. The refcounted manager
interface is a controlled substitution whose getter returns an actual engine
C++ plugin adapter; the final dispatcher/event callbacks capture the delivered
arguments. The interface remains caller-owned, balances 12,000 retains/releases,
and is not deleted by those callbacks. Four callbacks per fixture preserve
ordering and exact packets. The entire controlled 320-byte sender object is
compared, allowing only its measured 12-byte time-signature update. The producer
is forced into its direct-delivery branch; queued branches and application-owned
objects are excluded. All native callbacks are nonthrowing on the valid corpus;
all source/native fixture calls run serially in a standalone process.

The fixture snapshots twelve selected eight-byte spans of native globals,
restores them and checks their exact bytes before returning. Only that selected
state is asserted; no installed file is modified and no native asset/cache is
published. The native engine remains uninstrumented. Normal and source/harness
ASan, UBSan and float-cast-overflow runs compile and link the new dynamic library
separately and replay the same corpus. Thirty-four source rejection cases check
full output preservation. Original application clock production and sender/host
ownership, atomic lists, actual project/voice delivery, real-time behavior and
full generator/plugin equivalence remain false.

Forty focused cached tick cases cover positive/negative halves, integers,
signed zero and low-32-bit conversion edges with rounding both enabled and
disabled. Fourteen focused descriptor clocks cover integer/fractional values,
float-conversion loss and the 2^32 boundary. Each call starts with cleared
exceptions and compares output bits plus the complete `FE_ALL_EXCEPT` mask
against the intact engine; the measured mask is zero or `FE_INEXACT`. Both
focused cohorts snapshot and restore the caller's full floating environment.
General floating-status, arbitrary environments, enabled traps and untested
exception behavior are outside this focused proof. The prior `nearbyint`
result and independent inexact-flag finding are retained in private evidence.

Run `./reconstruction/plugins/generators/verify-clock-context.sh`, optionally
`--sanitize`. `VL_OSC_CLOCK_WORK_DIR` selects an isolated output directory for
independent review. Outputs default to ignored `.tools/plugin-work/generators/`
folders. `summarize_clock_context.py` binds both default runs to their source,
compiled artifacts, target identity and limitations. Independent copied-source
review accepted this bounded component after correcting the measured inexact
flag mismatch. The summary records local build results; whole-plugin and live
application certificates remain false.

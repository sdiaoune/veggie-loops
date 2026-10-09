# Purity live compressor classes

These independently written MIT C++ classes implement the measured compressor
object layout and virtual-method order. They build as real64-byte Peak and72-byte
RMS objects, not reinterpretations of prepared C records. Processing copies
defined numerical fields into the separately reviewed peak/RMS routines and
copies only resulting current controls, dirty, gain and RMS detector back. No
C++ object is aliased as a C prepared record. The two existing parent process
source files are read-only declared build dependencies.

`DynamicProcessor` supplies sixteen Itanium virtual slots, including the two
destructors, in measured order: nondeleting destructor, deleting destructor,
commonInit, init, setSampleRate, setBPM, setPPQ, value2string, getParamDisplay,
setParamValue, setWetOnly, commonPrepare, prepare, commonCalc, calc, process.
Peak overrides process; RMS overrides init and process. Their C++ names/typeinfo
and exported factory are original to this project. No original Purity native
factory symbol, VST/AU factory or complete class-export identity is claimed.

The bounded C factory accepts kinds5/6 (normalized Peak6) and7 (RMS7).
Enabled creation invokes conditional virtual initialization. Replacement creates
the new object before destroying the old one; allocation failure preserves the
old object and its complete history. This is an independent defensive extension
to the native factory, which deletes the old object first. All object and handle
access, including getters, formatting, raw-object inspection and destruction,
requires caller serialization. Host/application integration is not provided.

Constructor clocks and targets are-1; current controls are.5; dirty and wetOnly
are0. The original leaves padding, gain and RMS history uninitialized until a
successful init. The reconstruction independently sets those padding bytes to0,
gain to1 and detector to0. Those choices are excluded from comparisons of native
undefined constructor bytes. Disabled objects cannot process positive counts
through the C API until a successful numerical init and valid rate/targets.

Init returns without resetting history when dirty is nonzero. Otherwise it sets
dirty1 and gain1, and RMS also clears detector. CommonInit and preparation set
dirty1; calc delegates to a no-op. Setters only store clocks, targets or wetOnly;
they preserve current controls and numerical history. A count0 process accepts
null audio and clears dirty, including on an unconfigured disabled object. The
C API rejects init on an uninitialized dirty object because the analogous native
history is undefined; count0 then init provides safe recovery.

Run on the measured macOS arm64 installation:

```sh
bash reconstruction/plugins/external/purity/classes/verify.sh
```

Set `VL_PURITY_CLASSES_WORK` to a unique absolute output directory for independent
replays. The default is a dedicated private review directory. The new library,
native differential fixture and allocation fixture use AddressSanitizer and
UndefinedBehaviorSanitizer; the installed commercial reference is uninstrumented.
Numerical flags include `-ffp-contract=off -fno-fast-math -fno-builtin-log10f`.
Display strings use the system libc/libm and default C formatting environment.

The maintained comparison uses the actual original exported compressor factory
and its allocated objects, rather than fabricated class records. A controlled
32-byte factory descriptor has nonzero guards. It compares all native-defined
clock/current/target/dirty/wet/gain/detector fields and the corresponding compiled
object offsets, excluding differing vptrs and undefined bytes. It covers six
measured rates, both enabled states and all three factory selectors, control and clock changes,
prepare/calc/init orders, replacement/deleting destruction, default and
normalized display strings, guarded identical/disjoint audio, repeated blocks
through8192frames and raw calls through compiled virtual slots.

Initial builder replay passed864 actual native creations,4,608 audio calls,
5,512,320 stereo frames,10,512 defined-state records,31,104 display comparisons,
576 enabled/disabled replacement sequences,3,744 direct compiled virtual calls and44 atomic
invalid-input cases. The source allocation fixture passed18 injected allocation
failures, including every handle/object creation allocation and retained-history
replacement recovery. A separate copied-source replay passed the same cases
under both sanitizers, and independent source/fixture/contract review passed.
These are finite corpus counts, with whole-plugin completion still false.

The C API processes finite fresh stereo input[-4,4], rate8000..192000, normalized
targets0..1 and0..8192frames. Audio storage must be disjoint or identical and must
not overlap handle/object storage. Makeup output can exceed the input bound;
each later block must again satisfy the input contract. BPM and PPQ setters
accept finite doubles and do not affect compressor arithmetic. Display indexes
are0..2, output storage must be valid/nonoverlapping and insufficient capacity
rejects atomically. Constructor target sentinel-1 is supported by stored display;
explicit value formatting accepts only0..1. Raw C++ processing follows the same
prepared numerical, audio, overlap and count bounds; constructor sentinel
rate/targets must be configured before positive processing. Raw formatting also
requires64 writable bytes and index0..2, with normalized explicit values or the
stored constructor sentinel-1. The header records these caller preconditions;
raw C++ methods are not a total invalid-input C interface.

Target identity: installed Purity VST universal SHA-256
`ef2675ee69f9498ae10807820660e1158ba3c50684f44dea46b03efd7ceb1b07`,
arm64 SHA-256 `f05490472c0c170b99caa93ce9efa41eb712035bb253d53c29909ea00bc8816f`.
Original native code, assets, decompiler text and captured object payloads are
not embedded. Full application effect-chain preparation, wet/dry routing,
plugin state, editor, MIDI, VST/AU and realtime equivalence remain open.

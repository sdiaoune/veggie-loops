# Native engine state streams

The inspected arm64 FLEngine contains a real `TStreamAdapter` implementing the
plugin IStream boundary. Its Read/Write methods return a 32-bit HRESULT and store
a 32-bit completed count. They forward the low 32-bit length to the underlying
memory stream. This measured boundary differs from assuming every native integer
in the local C++ SDK's Mac stream declaration has the platform's pointer width.
The reconstruction follows the inspected binary protocol.

```sh
./reconstruction/plugins/effects/verify_engine_stream.sh
```

This identity-bound fixture loads the intact original engine, constructs its
actual `TMemoryStream` and `TStreamAdapter` through real constructors, and uses
the latter's real COM interface. It creates real engine wrappers around newly
compiled Balance and Mute 2 native plugins. Their state callbacks perform 256
saves and 256 restores through these original stream classes. The original
methods update only the lower 32-bit completion count and preserve an adjacent
sentinel. The original provider's invalid-buffer error is interpreted as a
negative 32-bit HRESULT.

Both native wrappers use signed 32-bit HRESULT results. A successful byte count
alone is insufficient: two synthetic providers report a complete read while
returning a failed 32-bit HRESULT. Both restorations reject that failure without
changing parameters. Wider zeroed completion storage safely handles the real
32-bit writes and the separate fixtures' 64-bit completion writes. Mute 2 clears
that storage between its version and parameter transfers.

The test checks the universal engine hash and refuses compilation outside macOS
arm64, because constructor, class, interface and callback offsets were measured
on that architecture. Original executable bytes remain in the local installation;
the public fixture contains protocol offsets and identity checks.

These checks establish the behavior of the actual engine stream provider classes
and plugin adapter boundary in a local process. Static analysis also identifies
an engine caller that constructs this same `TStreamAdapter` and passes its
interface at object offset `0x28` to the native plugin's state callback. This
connects the measured provider to a real engine call site; that full caller is
not executed by this fixture. No FL application instance, project serializer or
mixer host is created. Live application-created routing, project/preset envelopes
and whole-plugin equivalence remain separate gates.

# Own 3x Osc factory lifetimes

The stock, immediate-context and prevoice-preparation experimental factories
share an own C++ lifetime contract. Complete callback20 cleans the instance but
retains raw storage for matching caller deallocation. Ordinary callback0 and
deleting callback21 clean and deallocate once. Borrowed hosts, notes and shared
metadata remain caller-owned. Access is serialized across instances sharing
tables/RNG; no editor or general concurrent lifetime API is provided.

Two independent runtime critics accepted nine normal/fatal/O0 profiles and twelve
fatal semantic negatives. A critic also tested empty channels after explicit
voice removal. Its first supplemental build used an older factory because of
include precedence; that failure remains excluded. Corrected dependency pins and
supplemental runs passed. The first twenty table expressions and non-lifetime
callback bodies remain unchanged. Callback0's cleanup body changes intentionally.

```sh
python3 reconstruction/plugins/generators/lifetime/verify_public.py
```

Run on macOS arm64 with Xcode command-line tools. This recipe loads own source
and system frameworks only. `--check-only` verifies published hashes. The wrapper
creates a fresh ignored source tree and runs the unchanged reviewed recipe;
all own products are signed and strictly verified before execution. Optimized
Python is refused before creating outputs or compiling. The fixture tracks the
observed C++ allocation graph; direct malloc-owned buffers and general allocator
equivalence are excluded.

Peer/control voices use parameter20=0 for deterministic starting phases. An earlier
fixture used20 and diverged before cleanup because it enabled phase randomization;
its failure is preserved. This is same-source peer preservation, with 27,648 exact
PCM floats across the nine profiles. It is not original audio parity evidence.

Only matching raw deallocation is allowed after successful complete destruction;
the ended instance cannot be accessed or destroyed again. Original extra-destructor
ABI/class/GUI/allocator, application hosting, VST/AU, real-time and whole-plugin
equivalence remain unproved. Preparation and original-driven audio checks have
their separate [bounded module](../prevoice-preparation/README.md).

#pragma once
#include <array>
#include <cstdint>
namespace veggie_loops::three_osc::clock {
// Prepared scalar description of the measured arm64 GT_Ticks provider. This
// does not produce a live application clock or reproduce host scheduling.
// Strict separate operations, nearest-even and gradual underflow are required.
// Rounding uses rint. Finite nearest-even cached/descriptor cases compare the
// FRINTX inexact status; general fenv or enabled-trap parity is not established.
// Finite cached/sample-offset magnitudes must be <=2^52; samplesPerTick in
// [1,2^32]; latencySamples must be nonnegative. All int32 tick/mode fields are
// supported; only songMode==1 subtracts localStart when rounding is requested.
struct TicksContext {
 double cachedTicks=0, samplePositionFraction=0, samplesPerTick=1;
 int32_t currentTick=0, samplePosition=0, minimumTick=0, latencySamples=0;
 int32_t songMode=0, localStart=0;
 bool senderActive=false, future=false, roundLocal=false;
};
struct TimePacket { double t=0, t2=0; };
// Borrowed readable context and writable packet must be valid for the call.
// Only packet.t changes on success; packet.t2 is untouched, including its bits.
// Invalid prepared scalar inputs return false without changing either word.
// No allocation, callbacks, engine globals, synchronization or ownership occur.
bool ticks(const TicksContext&, TimePacket&) noexcept;

// Prepared descriptor values sent by measured TExPlugin direct-delivery paths.
// Valid rates8000..384000, signatures1..1024, PPQ4..2^20, tempo(0,1000], finite
// samplesPerTick[1,2^32]. Native producer stores signature at sender+0x120.
struct DeliveryContext {
 int32_t sampleRate=44100, signatureFirst=16, signatureSecond=4, ppq=240;
 float tempo=120;
 double samplesPerTick=441;
};
struct Delivery {
 std::array<int32_t,3> timeSignature{};
 int32_t sampleRate=0;
 intptr_t samplesPerTickDispatchValue=0; // signed extension of FLOAT bits
 int32_t tempoEventValue=0;             // FLOAT bits
 uint32_t tempoEventFlags=0;            // rounded samples/tick modulo2^32
};
// Builds caller-owned values for dispatcher4,14,20 and tempo event0. The actual
// producer direct callbacks send14 then20, and separately event0 then20. Queued
// delivery, plugin lookup/refcount implementation and live contexts are open.
// Invalid prepared scalar inputs leave destination unchanged.
bool delivery(const DeliveryContext&, Delivery&) noexcept;
}

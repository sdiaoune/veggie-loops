#pragma once
#include "allocation_gate.hpp"
#include <algorithm>
#include <array>
#include <cstring>

// Shared callback implementation: the native observer supplies a Mach copy
// primitive and API constants; controlled tests supply only caller-owned data.
// Scratch, destination, callback ranges and Snapshot must be live/disjoint.
// A failed OS read may partially alter scratch/destination; temporary output
// is always null on failure. No failure grants an inventory or Ready token.
namespace vl::tyrell::allocation_provider {
using namespace allocation_gate;
using Status = int;
using Task = std::uint32_t;
constexpr std::size_t maxCopyBytes = 16 * 1024 * 1024;
struct Codes { Status success, invalid, failure; };
using Primitive = Status (*)(void *, std::uint64_t, std::size_t, void *, std::uint64_t *) noexcept;

class ExactCopier {
  void *scratch_;
  std::size_t capacity_;
  Primitive primitive_;
  void *context_;
  Codes codes_;
public:
  ExactCopier(void *scratch, std::size_t capacity, Primitive primitive,
              void *context, Codes codes) noexcept
      : scratch_(scratch), capacity_(capacity), primitive_(primitive), context_(context), codes_(codes) {}
  Status read(std::uint64_t address, std::size_t bytes, void *destination) noexcept {
    if (!bytes || !capacity_ || capacity_ > maxCopyBytes || bytes > capacity_ || !destination ||
        bytes > UINT64_MAX - address || !primitive_) return codes_.invalid;
    std::uint64_t copied = 0;
    const auto result = primitive_(context_, address, bytes, destination, &copied);
    return result == codes_.success && copied == bytes ? codes_.success : codes_.failure;
  }
  Status temporary(std::uint64_t address, std::size_t bytes, void **out) noexcept {
    if (!out) return codes_.invalid;
    *out = nullptr;
    const auto result = read(address, bytes, scratch_);
    if (result == codes_.success) *out = scratch_;
    return result;
  }
};

struct Snapshot {
  std::array<Range, maxRanges> rows{};
  std::size_t used = 0;
  bool complete = false, failed = false, readerFailed = false;
  Status firstReaderFailure = 0;
  std::span<const Range> view() const { return {rows.data(), used}; }
  void reset(Status success) noexcept {
    used = 0; complete = failed = readerFailed = false;
    firstReaderFailure = success;
    // Unused records retain previous bytes; used defines the captured prefix.
  }
};

class Callbacks {
  ExactCopier *copier_ = nullptr;
  Snapshot *snapshot_ = nullptr;
  Task task_ = 0;
  unsigned rangeType_ = 0;
  Codes codes_;
public:
  explicit Callbacks(Codes codes) noexcept : codes_(codes) {}
  void activate(ExactCopier *copier, Snapshot *snapshot, Task task, unsigned rangeType) noexcept {
    copier_ = copier; snapshot_ = snapshot; task_ = task; rangeType_ = rangeType;
  }
  void deactivate() noexcept { copier_ = nullptr; snapshot_ = nullptr; }
  Status reader(Task task, std::uint64_t address, std::size_t bytes, void **out) noexcept {
    if (out) *out = nullptr;
    const auto result = task != task_ || !copier_ || !snapshot_
        ? codes_.invalid : copier_->temporary(address, bytes, out);
    if (result != codes_.success && snapshot_) {
      if (!snapshot_->readerFailed) snapshot_->firstReaderFailure = result;
      snapshot_->readerFailed = true;
    }
    return result;
  }
  // NativeRange is the API's immediate callback record (address,size), never
  // a foreign heap range. Pointer/count validity is a provider precondition;
  // null, wrong type/task and over-budget records are refused before reads.
  template<class NativeRange>
  void recorder(Task task, unsigned type, const NativeRange *ranges, unsigned count) noexcept {
    if (!snapshot_) return;
    if (snapshot_->readerFailed) { snapshot_->failed = true; return; }
    if (task != task_ || type != rangeType_ || !ranges || snapshot_->used > maxRanges ||
        count > maxRanges - snapshot_->used) { snapshot_->failed = true; return; }
    for (unsigned i = 0; i < count; ++i) {
      const Range r{ranges[i].address, ranges[i].size}; std::uint64_t end = 0;
      if (!r.base || !r.extent || !add(r.base, r.extent, end)) { snapshot_->failed = true; return; }
      snapshot_->rows[snapshot_->used++] = r;
    }
  }
};

inline bool finish(Snapshot &snapshot, bool providerSucceeded, bool threadCheck) noexcept {
  snapshot.complete = false;
  if (!providerSucceeded || !threadCheck || snapshot.failed || snapshot.readerFailed ||
      snapshot.used > maxRanges) return false;
  std::sort(snapshot.rows.begin(), snapshot.rows.begin() + snapshot.used,
            [](Range a, Range b) { return a.base < b.base; });
  snapshot.complete = inventory(snapshot.view(), true) == Error::none;
  return snapshot.complete;
}
} // namespace vl::tyrell::allocation_provider

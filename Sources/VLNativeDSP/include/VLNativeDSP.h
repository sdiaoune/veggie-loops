#pragma once
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct vl_native_oscillator vl_native_oscillator;
// Own VL preset on the reconstructed raw 3 Osc core. MIDI0..127, integer
// sample rate8000..192000. This API serializes all shared-engine access.
// A shared bank anchor avoids repeated table builds. A process-lifetime mutex
// and exit fence protect detached jobs from global teardown. Before exit,
// individual note cores and voices are released by destroy.
vl_native_oscillator* vl_native_oscillator_create(int32_t midi_note, int32_t sample_rate);
// A call writes at most1024 mono frames. The app supplies its note envelope
// and mixer; the original Fruity integrated modulation pipeline is absent.
int vl_native_oscillator_render(vl_native_oscillator*, float* mono, uint32_t frames);
void vl_native_oscillator_destroy(vl_native_oscillator*);
#ifdef __cplusplus
}
#endif

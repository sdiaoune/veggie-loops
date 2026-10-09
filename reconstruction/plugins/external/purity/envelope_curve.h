#pragma once
#ifdef __cplusplus
extern "C" {
#endif
// Independently generated mathematical curve. Output must hold259 floats.
// The verified amount domain is finite[-16,16]. Invalid arguments return0
// without writing. This new ABI is not a Purity plugin or native class ABI.
int vl_purity_envelope_curve(double amount, float* output);
#ifdef __cplusplus
}
#endif

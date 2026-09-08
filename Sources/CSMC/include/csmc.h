#ifndef CSMC_H
#define CSMC_H

// Minimal AppleSMC reader. Reads work as a normal user (no root). The SMC's
// packed request struct is kept here in C so Swift never has to mirror its
// exact layout. Temperatures come back in Celsius, fan speeds in RPM.

// Open the AppleSMC connection. Returns 0 on success.
int csmc_open(void);
void csmc_close(void);

// Number of SMC keys, and the 4-char key name at an index (out must hold 5 bytes).
int csmc_key_count(void);
int csmc_key_at(int index, char out[5]);

// Read a 4-char key and decode it to a double (Celsius for T*, RPM for F*Ac, etc).
// Returns 0 on success; leaves *value untouched and returns non-zero on failure or
// an unhandled data type.
int csmc_read(const char* key, double* value);

#endif

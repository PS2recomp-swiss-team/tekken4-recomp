# VU1 generator provenance

Source-only review, 2026-11-02. These statements come from this repository;
the upstream repository and its history were not checked.

`tools/vu1/vu1n_gen.py` identifies its source in lines 1-5:
`Waffle565/God-Of-War-Native-Port`, branch `main`, revision `b76921c`,
path `tools/vu1/vu1n_gen.py`. Its header records a T4 adaptation: native
OPMULA/OPMSUB generation for destination `xyz`, including MAC flags used
for backface culling. The import log in `docs/status.md`, under "Native
VU1 port (session 3, 2026-10-21)", says the script was initially copied
unchanged. The header describes the later T4 change; this copy has no
history with which to compare the imported script byte for byte.

The generator's applicable licence is **unresolved on the available
evidence**. Its header and the import log report that upstream `main`
had no LICENSE file. The same records call upstream's separate `runtime`
branch GPL-3.0. That runtime statement does not establish permission for
the generator copied from `main`. The project's GPL-3.0 declaration in
`README.md` and the GPL v3 text in `LICENSE` do not supply the missing
upstream grant. No generator-specific licence or written resolution is
recorded here.

Patch 11 contains the separately imported native VU1 runtime and build
integration. The import log calls that runtime GPL-3.0 and lists its copied
files; it does not pin the imported runtime head. The log's `c5a9d02` is a
common base, and its earlier GoW reference pin `514f891` is not the
generator's recorded `b76921c` origin.

The generator reads game micro-memory and writes game-specific C++.
`tools/vu1_micro_from_elf.py` reconstructs that memory from the player's
ELF. The generator header and patch 11 say the micro-memory and generated
C++ are game code and must not be committed or published. A source licence
for the port or generator would not itself grant rights in that game code.

Unknowns are the grant covering the exact imported script, its full
contributor chain, the full imported revision and byte-for-byte ancestry,
and the exact upstream notices to retain. Resolving those requires evidence
from the rights holders or the exact upstream revision. The packaging tool
requires a `vu1_generator` licence input (`tools/package_release.py:223`);
the presence of that input alone does not establish its correctness.

The broader inventory and existing trace are in
[THIRD_PARTY.md](THIRD_PARTY.md#vu1-generator-trace). No generator, build,
package or game was run for this review. A real build/game run can check
the technical path; it cannot prove a missing licence grant.

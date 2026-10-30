// Decompiles functions to text. Script arguments: <out_file> then any of
//   <hexaddr>        decompile the function containing it (created at that address when none exists)
//   x:<hexaddr>      list the references to that address with their containing functions
//   c:<hexaddr>      list the call sites of the function at that address
//   all              decompile every function
// Headless use (tools\ghidra_decomp.cmd): -process SLUS_203.28 -noanalysis -readOnly -postScript DecompileFuncs.java out.txt 0x222620 x:0x31a5c8
// @category PS2Recomp
import java.io.File;
import java.io.PrintWriter;

import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.symbol.Reference;
import ghidra.program.model.symbol.ReferenceIterator;

public class DecompileFuncs extends GhidraScript {
    @Override
    public void run() throws Exception {
        String[] args = getScriptArgs();
        try (PrintWriter w = new PrintWriter(new File(args[0]))) {
            DecompInterface di = new DecompInterface();
            di.openProgram(currentProgram);
            for (int i = 1; i < args.length; i++) {
                String a = args[i];
                if (a.equals("all")) {
                    for (Function f : currentProgram.getFunctionManager().getFunctions(true)) {
                        DecompileResults r = di.decompileFunction(f, 20, monitor);
                        w.println("// ===== " + f.getName() + " @ " + f.getEntryPoint());
                        w.println(r.decompileCompleted() ? r.getDecompiledFunction().getC() : "// decompile failed");
                    }
                    continue;
                }
                if (a.startsWith("x:") || a.startsWith("c:")) {
                    Address t = toAddr(Long.decode(a.substring(2)));
                    w.println("// references to " + t);
                    ReferenceIterator it = currentProgram.getReferenceManager().getReferencesTo(t);
                    while (it.hasNext()) {
                        Reference r = it.next();
                        Function f = getFunctionContaining(r.getFromAddress());
                        w.println("//   " + r.getFromAddress() + " " + r.getReferenceType() + " in " +
                                (f == null ? "-" : f.getName() + "@" + f.getEntryPoint()));
                    }
                    continue;
                }
                Address ad = toAddr(Long.decode(a));
                Function f = getFunctionContaining(ad);
                if (f == null) {
                    disassemble(ad);
                    f = createFunction(ad, null);
                }
                if (f == null) { w.println("// no function at " + ad); continue; }
                DecompileResults r = di.decompileFunction(f, 60, monitor);
                w.println("// ===== " + f.getName() + " @ " + f.getEntryPoint());
                w.println(r.decompileCompleted() ? r.getDecompiledFunction().getC() : "// decompile failed: " + r.getErrorMessage());
            }
        }
        println("DecompileFuncs done");
    }
}

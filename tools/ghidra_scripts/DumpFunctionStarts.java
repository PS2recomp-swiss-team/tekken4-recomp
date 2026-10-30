// Writes the entry address of every function in the current program, one hex address per line.
// Headless stand-in for the GhidraMCP query postprocess_ghidra_export.py makes (--starts <file>).
// @category PS2Recomp
import java.io.File;
import java.io.PrintWriter;

import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.Function;

public class DumpFunctionStarts extends GhidraScript {
    @Override
    public void run() throws Exception {
        File out = askFile("Function starts output", "Save");
        int n = 0;
        try (PrintWriter w = new PrintWriter(out)) {
            for (Function f : currentProgram.getFunctionManager().getFunctions(true)) {
                w.printf("0x%08x%n", f.getEntryPoint().getOffset());
                n++;
            }
        }
        println("DumpFunctionStarts: " + n + " functions -> " + out);
    }
}

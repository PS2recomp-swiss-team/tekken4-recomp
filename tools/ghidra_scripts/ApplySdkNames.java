// Applies the SCE SDK names from a ps2_analyzer TOML ("name@0xADDR" entries) to the current
// program: renames default-named (FUN_) functions at those addresses and creates the functions
// Ghidra's analysis missed. Addresses that fall inside an existing function are only reported,
// since splitting a function needs a manual look. Safe to run more than once.
// @category PS2Recomp
import java.io.File;
import java.nio.file.Files;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.symbol.SourceType;

public class ApplySdkNames extends GhidraScript {
    private static final Set<String> GENERIC_HANDLERS = Set.of("ret0", "ret1", "reta0");

    @Override
    public void run() throws Exception {
        File toml = askFile("Pick config/analyzer_seed.toml", "Apply");
        String text = Files.readString(toml.toPath());
        Matcher m = Pattern.compile("\"([^\"@]+)@0x([0-9A-Fa-f]+)\"").matcher(text);

        int renamed = 0, created = 0, alreadyNamed = 0, keptUserName = 0, inside = 0, failed = 0;
        while (m.find() && !monitor.isCancelled()) {
            String name = m.group(1);
            if (GENERIC_HANDLERS.contains(name)) {
                continue;
            }
            Address addr = toAddr(Long.parseLong(m.group(2), 16));
            Function f = getFunctionAt(addr);
            if (f == null) {
                Function owner = getFunctionContaining(addr);
                if (owner != null) {
                    println("inside " + owner.getName() + " @ " + owner.getEntryPoint() + ": " + name + " @ " + addr);
                    inside++;
                    continue;
                }
                if (getInstructionAt(addr) == null) {
                    disassemble(addr);
                }
                if (createFunction(addr, name) == null) {
                    println("FAILED to create " + name + " @ " + addr);
                    failed++;
                } else {
                    created++;
                }
            } else if (f.getName().equals(name)) {
                alreadyNamed++;
            } else if (f.getName().startsWith("FUN_")) {
                f.setName(name, SourceType.IMPORTED);
                renamed++;
            } else {
                keptUserName++;
            }
        }
        println(String.format("ApplySdkNames: renamed %d, created %d, already named %d, kept user names %d, "
            + "inside other functions %d, failed %d", renamed, created, alreadyNamed, keptUserName, inside, failed));
    }
}

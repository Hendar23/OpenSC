// Discover supplied direct-call/callback candidates missed by initial analysis.
// @category OpenSubCulture
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import java.nio.file.*;

public class RecoverOriginalFunctions extends GhidraScript {
    public void run() throws Exception {
        int created = 0;
        for (String line : Files.readAllLines(Paths.get(getScriptArgs()[0]))) {
            Address address = toAddr(Long.decode(line.trim()));
            if (getFunctionContaining(address) != null) continue;
            if (getInstructionAt(address) == null && !disassemble(address)) continue;
            if (createFunction(address, null) != null) created++;
        }
        println("Created " + created + " additional candidate functions");
    }
}

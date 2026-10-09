// Export local pseudocode and a function/call index from a headless Ghidra project.
// @category OpenSubCulture
import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.FunctionIterator;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;

public class ExportOriginalCode extends GhidraScript {
    public void run() throws Exception {
        Path output = Paths.get(getScriptArgs()[0]);
        Files.createDirectories(output);
        DecompInterface decompiler = new DecompInterface();
        decompiler.openProgram(currentProgram);
        int count = 0, failed = 0;
        try (BufferedWriter code = Files.newBufferedWriter(output.resolve("SC.c"), StandardCharsets.UTF_8);
             BufferedWriter index = Files.newBufferedWriter(output.resolve("functions.tsv"), StandardCharsets.UTF_8)) {
            code.write("/* Machine-generated pseudocode, NOT original source or buildable C.\n"
                + " * Input SHA-256: " + currentProgram.getExecutableSHA256() + "\n"
                + " * Ghidra types, boundaries and variable names may be incorrect. */\n\n");
            index.write("address\tname\tbytes\tcalled_functions\n");
            FunctionIterator functions = currentProgram.getFunctionManager().getFunctions(true);
            while (functions.hasNext() && !monitor.isCancelled()) {
                Function function = functions.next();
                if (function.isExternal()) continue;
                index.write(function.getEntryPoint() + "\t" + function.getName() + "\t" + function.getBody().getNumAddresses() + "\t");
                for (Function called : function.getCalledFunctions(monitor))
                    index.write(called.getEntryPoint() + ":" + called.getName() + ",");
                index.newLine();
                DecompileResults result = decompiler.decompileFunction(function, 15, monitor);
                code.write("\n/* Address: " + function.getEntryPoint() + " */\n");
                if (result.decompileCompleted() && result.getDecompiledFunction() != null) {
                    code.write(result.getDecompiledFunction().getC());
                } else {
                    failed++;
                    code.write("/* Decompilation failed: " + result.getErrorMessage().replace("*/", "* /") + " */\n");
                }
                count++;
                if (count % 500 == 0) println("Exported " + count + " functions");
            }
        } finally {
            decompiler.dispose();
        }
        Files.writeString(output.resolve("export-status.txt"), "functions=" + count + "\nfailed=" + failed + "\n");
        println("Export complete: " + count + " functions; " + failed + " failures");
    }
}

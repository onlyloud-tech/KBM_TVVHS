import java.nio.file.*;

/** Compile repository Lua with the installed game's Kahlua compiler. */
public final class LuaSyntaxChecks {
    public static void main(String[] args)throws Exception {
        int count=0;
        for(String root:args){
            try(var files=Files.walk(Path.of(root))){
                for(Path file:files.filter(p->p.toString().endsWith(".lua")).toList()){
                    try(var reader=Files.newBufferedReader(file)){
                        se.krka.kahlua.luaj.compiler.LuaCompiler.loadis(reader,file.toString(),null);
                    }
                    count++;
                }
            }
        }
        System.out.println("PASS installed Kahlua compiler: "+count+" runtime Lua files");
    }
}

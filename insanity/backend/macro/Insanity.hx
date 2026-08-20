package insanity.backend.macro;

#if macro
import haxe.macro.Compiler;
import haxe.macro.Context;

class Insanity {
	public static macro function init():Void {
		if (Context.defined('hl')) Compiler.addGlobalMetadata('', '@:build(insanity.backend.macro.HLMacro.fixLongMethods())');
	}
}
#end

package insanity.backend.macro;

#if macro
import haxe.macro.Compiler;
import haxe.macro.Context;

class Insanity {
	public static macro function init():Void {
		if (!Context.defined('insanity.noScriptableTypes')) Compiler.define('insanity.scriptableTypes');
		if (Context.defined('hl')) Compiler.addGlobalMetadata('', '@:build(insanity.backend.macro.Patcher.fixHLLongMethods())');
	}
	
	public static var ansiEsc:String = '\x1B[';
	public static var blob:String = '${ansiEsc}30;42m hscriptInsanity ${ansiEsc}0m';
	public static var blobWarn:String = '${ansiEsc}30;43m hscriptInsanity ${ansiEsc}0m';
	public static var blobError:String = '${ansiEsc}30;41m hscriptInsanity ${ansiEsc}0m';
	
	static var tags:Map<String, Bool> = [];
	public static var finishLog:Map<String, Void -> String> = [];
	
	static var preparedLog:Bool = false;
	public static function beginLog(tag:String, ?blob:String):Void {
		if (tags.exists(tag)) return;
		tags.set(tag, true);
		
		if (!preparedLog) Context.onAfterGenerate(finish);
		preparedLog = true;
		
		if (!isVerbose(false)) return;
		
		final ansiEsc:String = '\x1B[';
		haxe.Log.trace('${blob ?? Insanity.blob} $tag', null);
	}
	
	@:access(insanity.backend.macro.ScriptedMacro)
	@:access(insanity.backend.macro.AbstractMacro)
	@:access(insanity.backend.macro.Patcher)
	public static function finish():Void {
		if (!isVerbose(false)) return;
		
		var log = haxe.Log.trace.bind(_, null);
		
		log('$blob Done!');
		
		for (tag => f in finishLog) log('    ?  ${ansiEsc}49;32m$tag${ansiEsc}0m  ${f()}');
	}
	
	public static function isVerbose(fullOnly:Bool = true):Bool {
		final compilerVerbose:Bool = (haxe.macro.Compiler.getConfiguration()?.verbose ?? false);
		
		return (compilerVerbose || Context.defined('insanity.verboseFull') || (!fullOnly && Context.defined('insanity.verbose')));
	}
}
#end

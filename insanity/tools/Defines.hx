package insanity.tools;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
#end

/**
 * Compilation defines are stored here.
 * 
 * Used to allow Hscript to use these defines.
 */
class Defines {
	/**
	 * Map with all compilation defines.
	 */
	public static var compilerDefines(default, never):Map<String, Dynamic> #if (!macro) = getDefines() #end ;
	
	/**
	 * Appends compilation defines to `map`.
	 * 
	 * @param	map		The map to append to.
	 * @return	The map.
	 */
	public static function appendCompilerDefines(map:Map<String, Dynamic>):Map<String, Dynamic> {
		for (k => v in compilerDefines) {
			if (!map.exists(k))
				map.set(k, v);
		}
		
		return map;
	}
	
	static macro function getDefines():Expr #if macro {
		return macro $v {haxe.macro.Context.getDefines()};
	} #end ;
}
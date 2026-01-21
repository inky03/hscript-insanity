package insanity.backend.macro;

import haxe.macro.Context;

class Defines {
	public static var compilerDefines(default, never):Map<String, Dynamic> = haxe.macro.Context.getDefines();
	
	public static function appendCompilerDefines(map:Map<String, Dynamic>):Map<String, Dynamic> {
		for (k => v in compilerDefines) {
			if (!map.exists(k))
				map.set(k, v);
		}
		
		return map;
	}
}
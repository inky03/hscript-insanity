package insanity.backend.macro;

import haxe.macro.Context;

class Defines {
	public static var compilerDefines(default, never):Map<String, String> = haxe.macro.Context.getDefines();
	
	public static function appendCompilerDefines(map:Map<String, String>):Map<String, String> {
		for (k => v in compilerDefines) {
			if (!map.exists(k))
				map.set(k, v);
		}
		
		return map;
	}
}
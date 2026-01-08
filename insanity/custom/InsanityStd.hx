package insanity.custom;

import insanity.backend.types.Scripted.InsanityScriptedClass;

class InsanityStd {
	@:deprecated('Std.is is deprecated. Use Std.isOfType instead.')
	public static inline function is(v:Dynamic, t:Dynamic):Bool {
		return isOfType(v, t);
	}
	
	public static inline function isOfType(v:Dynamic, t:Dynamic):Bool {
		if (t is InsanityScriptedClass) {
			if (v is IScripted) {
				var base:InsanityScriptedClass = @:privateAccess v.__base;
				function match(base:Dynamic, c:InsanityScriptedClass) {
					if (base == c) {
						return true;
					} else if (base.extending != null && base.extending is InsanityScriptedClass) {
						return match(base.extending, c);
					} else {
						return false;
					}
				}
				return match(base, t);
			}
			return false;
		} else {
			return Std.isOfType(v, t);
		}
	}
	
	public static inline function downcast(value:Dynamic, c:Dynamic):Dynamic {
		if (c is InsanityScriptedClass) {
			if (value is IScripted) {
				var base:InsanityScriptedClass = @:privateAccess value.__base;
				function match(base:Dynamic, c:InsanityScriptedClass) {
					if (base == c) {
						return value;
					} else if (base.extending != null && base.extending is InsanityScriptedClass) {
						return match(base.extending, c);
					} else {
						return null;
					}
				}
				return match(base, c);
			}
			return false;
		} else {
			return Std.downcast(value, c);
		}
	}

	@:deprecated('Std.instance() is deprecated. Use Std.downcast() instead.')
	public static inline function instance(value:Dynamic, c:Dynamic):Dynamic {
		return downcast(value, c);
	}
	
	public static inline function string(s:Dynamic):String {
		return Std.string(s);
	}
	
	public static inline function int(x:Float):Int {
		return Std.int(x);
	}
	
	public static inline function parseInt(x:String):Null<Int> {
		return Std.parseInt(x);
	}
	
	public static inline function parseFloat(x:String):Float {
		return Std.parseFloat(x);
	}
	
	public static inline function random(x:Int):Int {
		return Std.random(x);
	}
}
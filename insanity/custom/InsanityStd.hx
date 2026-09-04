package insanity.custom;

#if (insanity.scriptableTypes)
import insanity.backend.types.Scripted.InsanityScriptedClass;

/**
 * HscriptInsanity's extended version of the `Std` class, to make working with scripted types easier.
 */
@:access(insanity.backend.types.InsanityScriptedClass)
class InsanityStd {
	@:deprecated('Std.is is deprecated. Use Std.isOfType instead.')
	public static inline function is(v:Dynamic, t:Dynamic):Bool {
		return isOfType(v, t);
	}
	
	static inline function __scriptedIsScripted(base:Dynamic, c:InsanityScriptedClass):Bool {
		if (base == c) {
			return true;
		} else if (base is InsanityScriptedClass) {
			var cc:InsanityScriptedClass = cast base;
			return (cc.extending != null && __scriptedIsScripted(cc.extending, c));
		} else {
			return false;
		}
	}
	static inline function __scriptedIs(base:InsanityScriptedClass, t:Dynamic):Bool {
		if (base.implementing?.contains(t)) {
			return true;
		} else if (base.extending != null && base.extending is InsanityScriptedClass) {
			return __scriptedIs(base.extending, t);
		} else {
			return false;
		}
	}
	
	public static inline function isOfType(v:Dynamic, t:Dynamic):Bool {
		if (t is InsanityScriptedClass) {
			return (v is IScripted ? __scriptedIsScripted(v.__base, t) : false);
		} else {
			return (v is IScripted ? __scriptedIs(v.__base, t) : Std.isOfType(v, t));
		}
	}
	
	public static inline function downcast(value:Dynamic, c:Dynamic):Dynamic {
		return (isOfType(value, c) ? value : null);
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
#end

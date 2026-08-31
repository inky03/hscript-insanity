package insanity;

#if (!macro) import insanity.tools.Defines; #end
import insanity.backend.Expr;
import insanity.custom.*;
#if hl import insanity.custom.HL; #end

/**
 * Configuration settings for HscriptInsanity.
 * 
 * You can change some behaviors for all scripts with this class.
 */
class Config { #if (!macro)
	/**
	 * The default interpreter to use for all scripts, modules and types.
	 * If changed, it must extend the base `Interp`.
	 */
	public static var interpClass:Class<insanity.backend.Interp> = insanity.backend.Interp;
	
	/**
	 * A map with all preprocessor values to allow scripts to check for conditional compilation (ex. `#if #else #end`).
	 */
	public static var preprocessorValues:Map<String, Dynamic> = Defines.appendCompilerDefines([
		'insanity' => '1'
	]);
	
	/**
	 * A map containing global variables to include in every module, script and type.
	 */
	public static var globalVariables:Map<String, Dynamic> = [
		'null' => null,
		'true' => true,
		'false' => false
	];
	
	/**
	 * A map containing paths to import by default in every script, and their respective import mode.
	 */
	public static var globalImports:Map<String, ImportMode> = [
		'' => IAll
	];
	
	/**
	 * A map containing redirects from types to other types.
	 * This can be used for sandboxing.
	 */
	@:unreflective public static var typeProxy:Map<String, Dynamic> = [
		#if hl
		'Math' => HLMath,
		#end
		
		'Reflect' => InsanityReflect,
		'Type' => InsanityType,
		'Std' => InsanityStd
	];
	
	/**
	 * A map containing paths to block any scripts from accessing.
	 * This can be used for sandboxing.
	 */
	@:unreflective public static var blacklist:Map<ConfigBlacklistKind, Array<String>> = [
		ByPackage(false) => [
		],
		ByPackage(true) => [
		],
		ByModule => [
		],
		ByType => [
			'insanity.custom.InsanityUnsafeType'
		],
	];
#end }

/**
 * Helper class for `Config` and type blacklisting.
 */
class ConfigUtil {
	/**
	 * Checks if a type is blacklisted.
	 * 
	 * @param	type	The type to check.
	 * @return	Whether the type is blacklisted or not.
	 */
	public static function typeIsBlacklisted(type:Dynamic):Bool {
		if (type == null) return false;
		
		var name:String = (type is Enum ? Type.getEnumName(type) : Type.getClassName(type));
		if (Config.blacklist.get(ByType)?.contains(name))
			return true;
		
		var info = insanity.backend.TypeCollection.main.fromCompilePath(name);
		if (info != null) {
			if (Config.blacklist.get(ByModule)?.contains(info[0].module))
				return true;
			if (Config.blacklist.get(ByPackage(false))?.contains(info[0].pack.join('.')))
				return true;
			if (Config.blacklist.exists(ByPackage(true))) {
				var eq:Bool = false;
				var pack:String = info[0].pack.join('.');
				
				for (p in Config.blacklist.get(ByPackage(true))) {
					if (StringTools.startsWith(pack, p))
						return true;
				}
			}
		}
		
		return false;
	}
	
	/**
	 * @param	type 	The type to assert.
	 * @return	The same type if it's not blacklisted, otherwise null.
	 */
	public inline static function assertBlacklisted(type:Dynamic):Dynamic {
		if (typeIsBlacklisted(type)) {
			trace('WARNING: ${type is Enum ? Type.getEnumName(type) : Type.getClassName(type)} is blacklisted');
			
			return null;
		} else {
			return type;
		}
	}
}

/**
 * Determines how a path is blacklisted.
 */
enum ConfigBlacklistKind {
	/**
	 * Blacklists a package. If recursive, any sub-packages will also be blacklisted.
	 */
	ByPackage(recursive:Bool);
	
	/**
	 * Blacklists a module, including types inside it.
	 */
	ByModule;
	
	/**
	 * Blacklists a single type.
	 */
	ByType;
}
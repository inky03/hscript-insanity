package insanity;

import insanity.backend.macro.Defines;
import insanity.backend.Expr;
import insanity.custom.*;
#if hl import insanity.custom.HL; #end

class Config {
	public static var preprocessorValues:Map<String, String> = Defines.appendCompilerDefines([
		'insanity' => '1'
	]);
	
	public static var globalVariables:Map<String, Dynamic> = [
		'null' => null,
		'true' => true,
		'false' => false
	];
	
	public static var globalImports:Map<String, ImportMode> = [
		'' => IAll
	];
	
	@:unreflective public static var typeProxy:Map<String, Dynamic> = [
		#if hl
		'Math' => HLMath,
		#end
		
		'Reflect' => InsanityReflect,
		'Type' => InsanityType,
		'Std' => InsanityStd
	];
	
	@:unreflective public static var blacklist:Map<ConfigBlacklistKind, Array<String>> = [
		ByPackage(false) => [
		],
		ByPackage(true) => [
		],
		ByModule => [
		],
		ByType => [
		],
	];
}

class ConfigUtil {
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
	
	public static function assertBlacklisted(type:Dynamic):Dynamic {
		if (typeIsBlacklisted(type)) {
			trace('WARNING: ${type is Enum ? Type.getEnumName(type) : Type.getClassName(type)} is blacklisted');
			
			return null;
		} else {
			return type;
		}
	}
}

enum ConfigBlacklistKind {
	ByPackage(recursive:Bool);
	ByModule;
	ByType;
}
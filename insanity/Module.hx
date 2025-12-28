package insanity;

import insanity.backend.types.Scripted;
import insanity.backend.Exception;
import insanity.backend.Parser;
import insanity.backend.Interp;
import insanity.backend.Tools;
import insanity.backend.Expr;

class Module {
	public static var snapshots:Map<String, Map<String, Dynamic>> = [];
	
	public var name:String;
	public var origin:String;
	public var pack:Array<String>;
	public var path(get, never):String;
	
	public var parser:Parser = new Parser();
	public var interp:Interp = null;
	
	public var decls:Array<ModuleDecl> = [];
	public var types:Map<String, IInsanityType> = [];
	
	public var importModules:Array<ImportModule> = [];
	
	public function new(string:String, name:String = 'Module', pack:Array<String>, origin:String = 'hscript'):Void {
		parser.allowTypes = parser.allowJSON = true;
		interp = new Interp();
		
		this.origin = origin;
		this.name = name;
		this.pack = pack;
		
		parse(string);
	}
	
	public function parse(string:String):Array<ModuleDecl> {
		decls.resize(0);
		types.clear();
		
		try {
			var declList:Array<ModuleDecl> = parser.parseModule(string, origin, pack);
			for (decl in declList) {
				decls.push(decl);
				
				var type = switch (decl.d) {
					default:
						continue;
					case DClass(m):
						new InsanityScriptedClass(m, this);
					case DEnum(m):
						new InsanityScriptedEnum(m, this);
					case DTypedef(m):
						trace('Scripted typedefs are currently unsupported');
						continue;
				}
				
				types.set(Tools.pathToString(type.name, pack), type);
			}
		} catch (e:haxe.Exception) {
			onParsingError(e);
		}
		
		return decls;
	}
	
	public function start(?environment:Environment):Void {
		try {
			if (decls.length == 0) throw 'Module is uninitialized';
			
			interp.environment = environment;
			interp.setDefaults();
			
			for (module in importModules) {
				module.start(environment);
				
				for (u in module.interp.usings) interp.usings.push(u);
				for (n => i in module.interp.imports) interp.imports.set(n, i);
			}
			
			for (type in types)
				interp.imports.set(type.name, type);
			
			interp.executeModule(decls, path);
		} catch (e:haxe.Exception) {
			onProgramError(e);
		}
	}
	
	public function startTypes(?environment:Environment):Map<String, IInsanityType> {
		for (type in types) {
			try {
				type.init(environment, interp);
			} catch (e:haxe.Exception) {
				onModuleError(e, type);
			}
		}
		
		return types;
	}
	
	public function snapshot():Void {
		for (type in types)
			type.snapshot();
	}
	
	public dynamic function onParsingError(e:haxe.Exception):Void {
		trace('Failed to initialize module program!\n' + e.details());
	}
	public dynamic function onProgramError(e:haxe.Exception):Void {
		trace('Module program stopped unexpectedly!\n' + e.details());
	}
	public dynamic function onModuleError(e:haxe.Exception, type:IInsanityType):Void {
		trace('Failed to load type ${type.name} for module $path!\n' + e.details());
	}
	
	function get_path():String {
		var path:String = pack.join('.');
		
		if (path.length > 0) {
			return ('$path.$name');
		} else {
			return name;
		}
	}
}
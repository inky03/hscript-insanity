package insanity.backend.types;

import insanity.custom.InsanityReflect;
import insanity.custom.InsanityType;

import insanity.backend.Interp;
import insanity.backend.Tools;
import insanity.backend.Expr;
import insanity.Environment;
import insanity.Module;

using StringTools;
using insanity.backend.TypeCollection;

class ScriptedTools {
	public static function resolve(path:String):Class<IInsanityScripted> {
		var t = (TypeCollection.main.fromPath(path) ?? TypeCollection.main.fromCompilePath(path));
		
		if (t != null) {
			var a = Type.resolveClass(t[0].pack.join('.') + (t[0].pack.length > 0 ? '.' : '') + 'InsanityScripted_' + StringTools.replace(t[0].compilePath(), '.', '_'));
			
			if (a != null)
				return cast a;
		}
		
		throw 'Class $path can\'t be extended for scripting';
		return null;
	}
}

@:access(insanity.Module)
@:access(insanity.backend.Interp)
@:access(insanity.backend.types.IInsanityScripted)
class InsanityScriptedClass implements InsanityType {
	public var name:String;
	public var module:Module;
	public var pack:Array<String>;
	public var instanceClass:Class<IInsanityScripted>;
	public var constructorFunction:Dynamic;
	public var path:String;
	
	var decl:ClassDecl;
	
	var interp:Interp;
	var initializing:Bool = false;
	public var initialized:Bool = false;
	
	public function new(decl:ClassDecl, module:Module) {
		this.name = decl.name;
		this.pack = module.pack;
		this.module = module;
		this.decl = decl;
		
		path = Tools.pathToString(name, pack);
		
		interp = new Interp();
	}
	
	public function load(?env:Environment):Void {
		initializing = true;
		
		interp.environment = env;
		interp.setDefaults();
		interp.executeModule(module.decls, module.path);
		
		var knownFields:Array<String> = [];
		for (field in decl.fields) {
			var f:String = field.name;
			
			if (knownFields.contains(f)) {
				interp.error(ECustom('Duplicate class field declalarion: $name.$f'));
			} else {
				knownFields.push(f);
			}
			
			if (!field.access.contains(AStatic)) continue;
			
			switch (field.kind) {
				case KFunction(fun):
					interp.curExpr = fun.expr;
					
					interp.locals.set(f, {
						r: interp.buildFunction(f, fun.args, fun.expr, fun.ret),
						access: field.access
					});
				case KVar(v):
					interp.locals.set(f, {
						r: interp.exprReturn(v.expr),
						access: field.access
					});
			}
		}
		
		instanceClass = switch (decl.extend) {
			case null:
				InsanityDummyClass;
			case CTPath(path, _):
				ScriptedTools.resolve(path.join('.'));
			default:
				throw 'Invalid extend ${decl.extend}';
				null;
		}
		
		initializing = false;
		initialized = true;
	}
	
	public function toString():String {
		return (Type.getClassName(Type.getClass(this)) + '<$path>');
	}
	
	public function typeCreateInstance(arguments:Array<Dynamic>):Dynamic {
		if (!initialized) throw 'Type $path is not initialized';
		
		var inst:IInsanityScripted = Type.createEmptyInstance(instanceClass);
		inst.__construct(this, arguments);
		return inst;
	}
	
	public function reflectHasField(field:String):Bool {
		return false;
	}
	public function reflectGetField(field:String):Dynamic {
		var field:Variable = interp.locals.get(field);
		
		return (field != null && field.access.contains(FieldAccess.AStatic) ? field.r : null);
	}
	public function reflectSetField(field:String, value:Dynamic):Dynamic {
		return null;
	}
	public function reflectGetProperty(property:String):Dynamic {
		var field:Variable = interp.locals.get(property);
		
		if (field != null && field.access.contains(FieldAccess.AStatic)) {
			return field.r;
		}
		
		return null;
	}
	public function reflectSetProperty(property:String, value:Dynamic):Dynamic {
		return null;
	}
	public function reflectListFields():Array<String> {
		return [for (field in interp.locals.keys()) field];
	}
}

interface InsanityType extends ICustomReflection extends ICustomClassType {
	public var name:String;
	public var pack:Array<String>;
	
	public function load(?env:Environment):Void;
}

class InsanityDummyClass implements IInsanityScripted {
	public function new() {}
}

@:autoBuild(insanity.backend.macro.ScriptedMacro.build())
interface IInsanityScripted extends ICustomReflection {
	private function __construct(base:InsanityScriptedClass, arguments:Array<Dynamic>):Void;
}
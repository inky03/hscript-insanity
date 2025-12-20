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
	public static var scriptedClasses(default, never):Map<String, Class<IInsanityScripted>> = insanity.backend.macro.ScriptedMacro.listScriptedClasses();
	
	public static function resolve(t:Dynamic):Class<IInsanityScripted> {
		if (t is InsanityScriptedClass)
			return cast t;
		
		var cls:String = Type.getClassName(t);
		if (scriptedClasses.exists(cls))
			return scriptedClasses.get(cls);
		
		throw 'Class $cls can\'t be extended for scripting';
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
	public var extending:Dynamic = null;
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
	
	public function init(?env:Environment):Void {
		initializing = true;
		
		interp.environment = env;
		interp.setDefaults();
		interp.executeModule(module.decls, module.path);
		for (type in module.types) interp.imports.set(type.name, type);
		
		var overridingFields:Array<String> = [];
		var knownFields:Array<String> = [];
		for (field in decl.fields) {
			var f:String = field.name;
			
			if (f == 'new') continue;
			
			if (insanity.backend.macro.ScriptedMacro.ignoreFields.contains(f)) {
				throw 'Field $f reserved for internal use!!! - HScriptInsanity';
			} else if (knownFields.contains(f)) {
				throw 'Duplicate class field declaration: $name.$f';
			} else {
				knownFields.push(f);
				if (field.access.contains(AOverride)) overridingFields.push(f);
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
						access: field.access,
						get: v.get,
						set: v.set
					});
			}
		}
		
		extending = switch (decl.extend) {
			case CTPath(path, _):
				var p:String = path.join('.');
				
				var type = (interp.imports.get(p) ?? Tools.resolve(p, env));
				if (type == null) throw 'Type not found: $p';
				
				ScriptedTools.resolve(type);
			case null:
				null;
			default:
				throw 'Invalid extend ${decl.extend}';
				null;
		}
		
		var foundOverridingFields:Array<String> = [];
		function overrideFieldCheck(extending:Dynamic) {
			if (extending is InsanityScriptedClass) {
				var extend:InsanityScriptedClass = cast extending;
				
				for (field in extend.decl.fields) {
					var f:String = field.name;
					
					if (f == 'new' || field.access.contains(AStatic)) continue;
					
					if (overridingFields.contains(f)) {
						if (!foundOverridingFields.contains(f))
							foundOverridingFields.push(f);
					} else if (knownFields.contains(f)) {
						throw 'Field $f should be declared with \'override\' since it is inherited from superclass ${extend.name}';
					}
				}
				
				if (extend.extending != null) overrideFieldCheck(extend.extending);
			} else {
				var cls = getInstanceClass();
				if (cls == null) return;
				
				for (field in Type.getInstanceFields(cls)) {
					if (insanity.backend.macro.ScriptedMacro.ignoreFields.contains(field)) continue;
					
					if (overridingFields.contains(field)) {
						if (!foundOverridingFields.contains(field))
							foundOverridingFields.push(field);
					} else if (knownFields.contains(field)) {
						throw 'Field $field should be declared with \'override\' since it is inherited from superclass ${Reflect.field(cls, 'baseClass')}';
					}
				}
			}
		}
		overrideFieldCheck(extending);
		if (foundOverridingFields.length < overridingFields.length) {
			for (f in overridingFields) {
				if (!foundOverridingFields.contains(f))
					throw 'Field $f is declared \'override\' but doesn\'t override any field'; // TODO (Suggestion: ) ?
			}
		}
		
		initializing = false;
		initialized = true;
	}
	
	public function getInstanceClass():Class<IInsanityScripted> {
		return (extending is InsanityScriptedClass ? cast(extending, InsanityScriptedClass).getInstanceClass() : extending ?? InsanityDummyClass);
	}
	
	public function toString():String {
		return path; //(Type.getClassName(Type.getClass(this)) + '<$path>');
	}
	
	public function typeCreateInstance(arguments:Array<Dynamic>):Dynamic {
		if (!initialized) throw 'Type $path is not initialized';
		
		var inst:IInsanityScripted = Type.createEmptyInstance(getInstanceClass());
		inst.__construct(this, arguments);
		return inst;
	}
	public function typeGetClass():Dynamic {
		return null;
	}
	
	public function reflectHasField(field:String):Bool {
		return (interp.locals.exists(field));
	}
	public function reflectGetField(field:String):Dynamic {
		return (interp.locals.exists(field) != null ? interp.locals.get(field).r : null);
	}
	public function reflectSetField(field:String, value:Dynamic):Dynamic {
		return (interp.locals.exists(field) ? interp.locals.get(field).r = value : null);
	}
	public function reflectGetProperty(property:String):Dynamic {
		return (interp.locals.exists(property) ? interp.getLocal(property) : null);
	}
	public function reflectSetProperty(property:String, value:Dynamic):Dynamic {
		return (interp.locals.exists(property) ? interp.setLocal(property, value) : null);
	}
	public function reflectListFields():Array<String> {
		return [for (field in interp.locals.keys()) field];
	}
}

interface InsanityType extends ICustomReflection extends ICustomClassType {
	public var name:String;
	public var pack:Array<String>;
	
	public function init(?env:Environment):Void;
}

class InsanityDummyClass implements IInsanityScripted {
	public function new() {}
}

@:autoBuild(insanity.backend.macro.ScriptedMacro.build())
interface IInsanityScripted extends ICustomReflection extends ICustomClassType {
	private var __base:InsanityScriptedClass;
	private function __construct(base:InsanityScriptedClass, arguments:Array<Dynamic>):Void;
}
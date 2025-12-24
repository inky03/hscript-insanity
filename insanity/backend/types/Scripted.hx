package insanity.backend.types;

import insanity.custom.InsanityReflect;
import insanity.custom.InsanityType;

import insanity.backend.Printer;
import insanity.backend.Interp;
import insanity.backend.Tools;
import insanity.backend.Expr;
import insanity.Environment;
import insanity.Module;

using StringTools;
using insanity.backend.TypeCollection;

class ScriptedTools {
	public static var scriptedClasses(default, never):Map<String, Class<IInsanityScripted>> = insanity.backend.macro.ScriptedMacro.listScriptedClasses();
	
	public static function resolve(t:Dynamic):Dynamic {
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
class InsanityScriptedClass implements IInsanityType implements ICustomClassType {
	public var name:String;
	public var module:Module;
	public var pack:Array<String>;
	public var extending:Dynamic = null;
	public var constructorFunction:Dynamic;
	public var path:String;
	
	public var safe:Bool = false;
	
	var decl:ClassDecl;
	
	var interp:Interp;
	var initializing:Bool = false;
	public var initialized:Bool = false;
	
	public function new(decl:ClassDecl, ?module:Module) {
		this.name = decl.name;
		this.pack = (module?.pack ?? []);
		this.module = module;
		this.decl = decl;
		
		path = Tools.pathToString(name, pack);
		
		interp = new Interp();
	}
	
	public function init(?env:Environment, ?baseInterp:Interp):Void {
		initializing = true;
		
		interp.environment = env;
		
		if (baseInterp != null) {
			interp.usings.resize(0);
			interp.imports.clear();
			interp.variables.clear();
			for (u in baseInterp.usings) interp.usings.push(u);
			for (k => i in baseInterp.imports) interp.imports.set(k, i);
			for (k => v in baseInterp.variables) interp.variables.set(k, v);
		} else {
			interp.setDefaults();
		}
		
		interp.pushStack(insanity.backend.CallStack.StackItem.SModule(module?.path ?? name));
		
		safe = false;
		for (meta in decl.meta) {
			if (meta.name == ':safe')
				safe = true;
		}
		
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
					interp.position = fun.expr.pos;
					
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
				
				var instanceFields:Array<String> = (cls.instanceFields ?? Type.getInstanceFields(cast cls));
				var inlinedFields:Array<String> = cls.inlinedFields;
				var unexposedFields:Array<String> = cls.unexposedFields;
				
				for (field in instanceFields) {
					if (insanity.backend.macro.ScriptedMacro.ignoreFields.contains(field)) continue;
					
					if (overridingFields.contains(field)) {
						if (inlinedFields?.contains(field)) { throw 'Field $field is inlined and cannot be overridden'; }
						else if (unexposedFields?.contains(field)) { throw 'Field $field is unexposed and cannot be overridden'; }
						
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
	
	public function getInstanceClass():Dynamic {
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
	public function typeCreateEmptyInstance():Dynamic {
		if (!initialized) throw 'Type $path is not initialized';
		
		return Type.createEmptyInstance(getInstanceClass());
	}
	public function typeGetClass():Dynamic {
		return null;
	}
	public function typeGetClassFields():Array<String> {
		var fields:Array<String> = [for (loc => _ in interp.locals) loc];
		return fields;
	}
	public function typeGetInstanceFields():Array<String> {
		var fields:Array<String> = [];
		
		function getFields(c:Dynamic) {
			if (c is InsanityScriptedClass) {
				for (field in cast(c, InsanityScriptedClass).decl.fields) {
					var f:String = field.name;
					if (f == 'new' || field.access.contains(AStatic)) continue;
					if (!fields.contains(f)) fields.push(f);
				}
				
				var instance = c.getInstanceClass();
				if (instance != InsanityScriptedClass)
					getFields(instance);
				
				if (c.extending != null) {
					getFields(c.extending);
				}
			} else if (c is Class) {
				for (f in Type.getInstanceFields(c)) {
					if (!fields.contains(f) && !insanity.backend.macro.ScriptedMacro.ignoreFields.contains(f))
						fields.push(f);
				}
			}
		}
		
		getFields(this);
		
		return fields;
	}
	
	public function reflectHasField(field:String):Bool {
		return (interp.locals.exists(field));
	}
	public function reflectGetField(field:String):Dynamic {
		return (interp.locals.exists(field) ? interp.locals.get(field).r : null);
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
	
	public dynamic function onInstanceError(error:Dynamic, ?instance:IInsanityScripted):Void {
		trace('Error on instance of $name: $error');
	}
}

@:access(insanity.Module)
class InsanityScriptedEnum implements IInsanityType implements ICustomEnumType {
	public var name:String;
	public var module:Module;
	public var pack:Array<String>;
	public var path:String;
	
	public var values:Array<String>;
	public var constructs:Map<String, EnumFieldDecl>;
	var constructFunctions:Map<String, Array<Dynamic> -> InsanityScriptedEnumValue>;
	
	var decl:EnumDecl;
	
	public function new(decl:EnumDecl, ?module:Module) {
		this.name = decl.name;
		this.pack = (module?.pack ?? []);
		this.module = module;
		this.decl = decl;
		
		path = Tools.pathToString(name, pack);
	}
	
	public function init(?env:Environment, ?baseInterp:Interp):Void {
		values = decl.names;
		constructs = decl.constructs;
		constructFunctions = new Map();
		
		for (name => construct in constructs) {
			var params = construct.arguments;
			if (params != null) {
				var minParams:Int = 0;
				for (i => p in params) {
					if (!p.opt) minParams = (i + 1);
				}
				
				constructFunctions.set(name, Reflect.makeVarArgs(function(args:Array<Dynamic>) {
					if (args.length < minParams) {
						var arg = params[args.length];
						var argType:String = arg.name;
						if (arg.t != null) argType += (':' + new Printer().typeToString(arg.t));
						
						throw 'Not enough arguments, expected $argType';
					}
					if (args.length > params.length && params.length > 0) {
						throw 'Too many arguments';
					}
					
					return new InsanityScriptedEnumValue(this, values.indexOf(name), args);
				}));
			}
		}
	}
	
	public function toString():String { return path; }
	
	public function typeGetEnumName():String { return path; }
	public function typeCreateEnum(constr:String, ?arguments:Array<Dynamic>):Dynamic {
		var construct:EnumFieldDecl = constructs.get(constr);
		if (construct != null) {
			if (constructFunctions.exists(constr)) {
				return Reflect.callMethod(this, constructFunctions.get(constr), arguments ?? []);
			} else {
				return new InsanityScriptedEnumValue(this, values.indexOf(constr));
			}
		}
		return null;
	}
	public function typeCreateEnumIndex(index:Int, ?arguments:Array<Dynamic>):Dynamic {
		return typeCreateEnum(values[index], arguments);
	}
	public function typeGetEnumConstructs():Array<String> {
		return values.copy();
	}
	public function typeAllEnums():Array<Dynamic> {
		var enums:Array<InsanityScriptedEnumValue> = [];
		
		for (index => constr in values) {
			if (constructs.get(constr).arguments == null)
				enums.push(new InsanityScriptedEnumValue(this, index));
		}
		
		return enums;
	}
	
	public function reflectHasField(field:String):Bool { return false; }
	public function reflectGetField(field:String):Dynamic {
		var construct:EnumFieldDecl = constructs.get(field);
		if (construct != null) {
			if (constructFunctions.exists(field)) {
				return constructFunctions.get(field);
			} else {
				return new InsanityScriptedEnumValue(this, values.indexOf(field));
			}
		}
		return null;
	}
	public function reflectSetField(field:String, value:Dynamic):Dynamic { return null; }
	public function reflectGetProperty(property:String):Dynamic { return reflectGetField(property); }
	public function reflectSetProperty(property:String, value:Dynamic):Dynamic { return null; }
	public function reflectListFields():Array<String> { return null; }
}

class InsanityScriptedEnumValue implements ICustomEnumValueType {
	var base:InsanityScriptedEnum;
	
	public var index:Int;
	public var constructor:String;
	public var arguments:Array<Dynamic>;
	
	public function new(base:InsanityScriptedEnum, index:Int, ?arguments:Array<Dynamic>) {
		this.base = base;
		this.arguments = arguments;
		
		this.index = index;
		this.constructor = base.values[index];
	}
	
	public function toString():String {
		if (arguments != null) return '$constructor(${arguments.join(',')})';
		
		return constructor;
	}
	
	public function typeGetEnum():Dynamic { return base; }
	public function eq(o:ICustomEnumValueType):Bool {
		if (!(o is InsanityScriptedEnumValue)) return false;
		
		var o:InsanityScriptedEnumValue = cast o;
		if (o.base == base) {
			if (o.arguments == null && arguments == null) return true;
			
			for (i => argument in arguments) {
				if (argument != o.arguments[i])
					return false;
			}
			
			return true;
		}
		
		return false;
	}
}

class InsanityDummyClass implements IInsanityScripted {
	public function new() {}
}

interface IInsanityType extends ICustomReflection {
	public var name:String;
	public var pack:Array<String>;
	
	public function init(?env:Environment, ?baseInterp:Interp):Void;
}

@:autoBuild(insanity.backend.macro.ScriptedMacro.build())
interface IInsanityScripted extends ICustomReflection extends ICustomClassType {
	private var __base:InsanityScriptedClass;
	private function __construct(base:InsanityScriptedClass, arguments:Array<Dynamic>):Void;
}